# =============================================================================
# Coverage lab 階段 2(續):把 workload domain 的 cluster 補齊
#   加 esx02/03 → 建 VDS + 3 個 portgroup → 搬 vmk0 → 建 vMotion/vSAN vmk
#   → 收 vSAN → 開 DRS/HA
#
#   w01 用自己的 VLAN/網段,與 mgmt(VLAN 13/14)分開:
#     vMotion  VLAN 15  192.168.25.x
#     vSAN     VLAN 16  192.168.26.x
#
#   $env:VCPASS='...'; $env:ESXPASS='...'; pwsh ./Build-W01-Cluster.ps1
# =============================================================================
param([switch] $SkipHostAdd, [switch] $SkipVds, [switch] $SkipVsan)
$ErrorActionPreference = 'Stop'

# 🔴 四個模組都要釘版本,少一個 VDS/vSAN cmdlet 就噴 VIObjectImpl._connectionId
$PCLI = '13.5.1.25718932'
Import-Module VMware.VimAutomation.Sdk     -RequiredVersion $PCLI | Out-Null
Import-Module VMware.VimAutomation.Core    -RequiredVersion $PCLI | Out-Null
Import-Module VMware.VimAutomation.Vds     -RequiredVersion $PCLI | Out-Null
Import-Module VMware.VimAutomation.Storage -RequiredVersion $PCLI | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null

$VC       = 'vcf-w01-vc01.home.lab'
$VCPass   = if ($env:VCPASS)  { $env:VCPASS }  else { throw 'set $env:VCPASS' }
$ESXPass  = if ($env:ESXPASS) { $env:ESXPASS } else { throw 'set $env:ESXPASS' }

$DC       = 'vcf-w01-dc01'
$ClusterN = 'vcf-w01-cl01'
$NewHosts = @('vcf-w01-esx02.home.lab','vcf-w01-esx03.home.lab')

$VdsName  = 'vcf-w01-cl01-vds01'
$VdsMtu   = 9000
$PgMgmt   = 'w01-DPortGroup-VM-Mgmt'
$PgVmot   = 'vcf-w01-cl01-vds01-pg-vmotion'
$PgVsan   = 'vcf-w01-cl01-vds01-pg-vsan'
$VlanVmot = 15
$VlanVsan = 16
$UplinkNics = @('vmnic0','vmnic1')

$VmkMap = @{
    'vcf-w01-esx01.home.lab' = @{ vmotion='192.168.25.11'; vsan='192.168.26.11' }
    'vcf-w01-esx02.home.lab' = @{ vmotion='192.168.25.12'; vsan='192.168.26.12' }
    'vcf-w01-esx03.home.lab' = @{ vmotion='192.168.25.13'; vsan='192.168.26.13' }
}
$VmkMask = '255.255.255.0'

function Log($m) { "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m | Tee-Object -Append 'E:\9.1\converge-target\w01-cluster.log' }

Log "connecting $VC"
$srv = Connect-VIServer $VC -User 'administrator@vsphere.local' -Password $VCPass -Force
$cl  = Get-Cluster -Name $ClusterN
$dc  = Get-Datacenter -Name $DC
Log "cluster $($cl.Name), hosts now: $((Get-VMHost -Location $cl).Name -join ', ')"

# ── 1. 加主機 ──
if (-not $SkipHostAdd) {
    foreach ($h in $NewHosts) {
        if (Get-VMHost -Name $h -ErrorAction SilentlyContinue) { Log "  $h already added"; continue }
        Log "  adding $h ..."
        Add-VMHost -Name $h -Location $cl -User root -Password $ESXPass -Force -Confirm:$false | Out-Null
    }
}
$hosts = Get-VMHost -Location $cl | Sort-Object Name
Log "hosts: $($hosts.Name -join ', ')"

# ── 2. VDS ──
if (-not $SkipVds) {
    $vds = Get-VDSwitch -Name $VdsName -ErrorAction SilentlyContinue
    if (-not $vds) { Log "creating VDS $VdsName (MTU $VdsMtu)"; $vds = New-VDSwitch -Name $VdsName -Location $dc -Mtu $VdsMtu -NumUplinkPorts 2 }

    foreach ($pg in @(@{n=$PgMgmt;v=0}, @{n=$PgVmot;v=$VlanVmot}, @{n=$PgVsan;v=$VlanVsan})) {
        if (Get-VDPortgroup -VDSwitch $vds -Name $pg.n -ErrorAction SilentlyContinue) { continue }
        Log "  portgroup $($pg.n) (VLAN $($pg.v))"
        $p = New-VDPortgroup -VDSwitch $vds -Name $pg.n -VlanId $pg.v
        # nested lab:三項安全性全開(Get-VDSecurityPolicy 在這版會壞,走原生 API)
        $spec = New-Object VMware.Vim.DVPortgroupConfigSpec
        $spec.ConfigVersion = $p.ExtensionData.Config.ConfigVersion
        $spec.DefaultPortConfig = New-Object VMware.Vim.VMwareDVSPortSetting
        $sec = New-Object VMware.Vim.DVSSecurityPolicy
        foreach ($f in 'AllowPromiscuous','ForgedTransmits','MacChanges') {
            $b = New-Object VMware.Vim.BoolPolicy; $b.Value = $true; $sec.$f = $b
        }
        $sec.Inherited = $false
        $spec.DefaultPortConfig.SecurityPolicy = $sec
        $p.ExtensionData.ReconfigureDVPortgroup_Task($spec) | Out-Null
    }

    foreach ($h in $hosts) {
        if (-not (Get-VDSwitch -VMHost $h -Name $VdsName -ErrorAction SilentlyContinue)) {
            Log "  adding $($h.Name) to VDS"
            Add-VDSwitchVMHost -VDSwitch $vds -VMHost $h -Confirm:$false | Out-Null
        }
        # 🔴 uplink 分開檢查:主機在 VDS 上不代表 pnic 掛上去了
        $vdsPnics = @(Get-VMHostNetworkAdapter -VMHost $h -Physical -DistributedSwitch $vds -ErrorAction SilentlyContinue)
        if ($vdsPnics.Name -notcontains $UplinkNics[1]) {
            Log "  attaching $($UplinkNics[1]) on $($h.Name)"
            $nic1 = Get-VMHostNetworkAdapter -VMHost $h -Physical -Name $UplinkNics[1]
            Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vds -VMHostPhysicalNic $nic1 -Confirm:$false | Out-Null
            $vdsPnics = @(Get-VMHostNetworkAdapter -VMHost $h -Physical -DistributedSwitch $vds)
        }
        if ($vdsPnics.Count -lt 1) { throw "$($h.Name): VDS 上沒有 uplink,中止" }
        Log "  $($h.Name) VDS uplinks: $($vdsPnics.Name -join ', ')"

        # 有 uplink 才搬 VM(含 VCSA 自己)
        $mgmtPgObj = Get-VDPortgroup -VDSwitch $vds -Name $PgMgmt
        foreach ($vm in (Get-VM -Location $h -ErrorAction SilentlyContinue)) {
            foreach ($na in (Get-NetworkAdapter -VM $vm)) {
                if ($na.NetworkName -ne $PgMgmt) {
                    Log "  moving VM $($vm.Name) NIC '$($na.NetworkName)' -> $PgMgmt"
                    Set-NetworkAdapter -NetworkAdapter $na -Portgroup $mgmtPgObj -Confirm:$false | Out-Null
                }
            }
        }
        $vmk0 = Get-VMHostNetworkAdapter -VMHost $h -Name vmk0
        if ($vmk0.PortGroupName -ne $PgMgmt) {
            Log "  migrating vmk0 + $($UplinkNics[0]) on $($h.Name)"
            $nic0 = Get-VMHostNetworkAdapter -VMHost $h -Physical -Name $UplinkNics[0]
            Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vds -VMHostPhysicalNic $nic0 `
                -VirtualNicPortgroup $mgmtPgObj -VMHostVirtualNic $vmk0 -Confirm:$false | Out-Null
        }
    }

    # ── 3. vMotion / vSAN vmk ──
    $vds = Get-VDSwitch -Name $VdsName
    foreach ($h in $hosts) {
        $ips = $VmkMap[$h.Name]
        if (-not $ips) { Log "  !! no vmk mapping for $($h.Name)"; continue }
        foreach ($spec in @(@{ pg=$PgVmot; ip=$ips.vmotion; svc='vmotion' }, @{ pg=$PgVsan; ip=$ips.vsan; svc='vsan' })) {
            if (Get-VMHostNetworkAdapter -VMHost $h -VMKernel | Where-Object { $_.PortGroupName -eq $spec.pg }) { continue }
            Log "  $($h.Name) new vmk $($spec.svc) $($spec.ip)"
            $pg = Get-VDPortgroup -VDSwitch $vds -Name $spec.pg
            New-VMHostNetworkAdapter -VMHost $h -PortGroup $pg -VirtualSwitch $vds `
                -IP $spec.ip -SubnetMask $VmkMask -Mtu $VdsMtu `
                -VMotionEnabled:($spec.svc -eq 'vmotion') -VsanTrafficEnabled:($spec.svc -eq 'vsan') -Confirm:$false | Out-Null
        }
        $vmk0 = Get-VMHostNetworkAdapter -VMHost $h -Name vmk0
        if ($vmk0.VMotionEnabled -or $vmk0.VsanTrafficEnabled) {
            Log "  $($h.Name) vmk0: 關掉 vmotion/vsan"
            $vmk0 | Set-VMHostNetworkAdapter -VMotionEnabled $false -VsanTrafficEnabled $false -Confirm:$false | Out-Null
        }
    }
}

# ── 4. vSAN 收碟 ──
if (-not $SkipVsan) {
    foreach ($h in $hosts) {
        if (Get-VsanDiskGroup -VMHost $h -ErrorAction SilentlyContinue) { Log "  $($h.Name) disk group exists"; continue }
        $all = Get-ScsiLun -VmHost $h -LunType disk
        $cache    = $all | Where-Object { [math]::Round($_.CapacityGB) -ge 95  -and [math]::Round($_.CapacityGB) -le 105 } | Select-Object -First 1
        $capacity = $all | Where-Object { [math]::Round($_.CapacityGB) -ge 450 } | Select-Object -First 1
        if (-not $cache -or -not $capacity) { Log "  !! $($h.Name): cache/capacity 找不到"; continue }
        Log "  $($h.Name) disk group: cache $($cache.CanonicalName) + capacity $($capacity.CanonicalName)"
        New-VsanDiskGroup -VMHost $h -SsdCanonicalName $cache.CanonicalName -DataDiskCanonicalName $capacity.CanonicalName -Confirm:$false | Out-Null
    }
}

Log "enabling DRS + HA"
Set-Cluster -Cluster $cl -DrsEnabled $true -DrsAutomationLevel FullyAutomated -Confirm:$false | Out-Null
Set-Cluster -Cluster $cl -HAEnabled $true -Confirm:$false | Out-Null

Log "=== summary ==="
Get-VMHost -Location $cl | Sort-Object Name | Select-Object Name, ConnectionState, Version, Build |
    Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
Get-Datastore | Select-Object Name, Type, CapacityGB, FreeSpaceGB |
    Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
Disconnect-VIServer $srv -Confirm:$false | Out-Null
Log 'done'
