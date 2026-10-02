# =============================================================================
# Converge 目標端:vCenter 裝好後,把 cluster 補齊成一套可以 converge 的 vSphere
#
#   1. 加 esx02-04 進 cluster
#   2. 建 VDS + 3 個 portgroup(mgmt / vMotion / vSAN),把 vmnic 與 vmk0 搬上去
#   3. 建 vMotion / vSAN vmkernel
#   4. 把 esx02-04 的磁碟收進 vSAN(OSA)
#   5. 開 DRS / HA
#
# 跑法:$env:VCPASS='...'; $env:ESXPASS='...'; pwsh ./Build-ConvergeTarget.ps1
# =============================================================================
param(
    [switch] $SkipHostAdd,
    [switch] $SkipVds,
    [switch] $SkipVsan
)
$ErrorActionPreference = 'Stop'

$VC       = 'vcf-m02-vc01.home.lab'
$VCUser   = 'administrator@vsphere.local'
$VCPass   = if ($env:VCPASS)  { $env:VCPASS }  else { throw 'set $env:VCPASS' }
$ESXPass  = if ($env:ESXPASS) { $env:ESXPASS } else { throw 'set $env:ESXPASS' }

$DC       = 'vcf-m02-dc01'
$ClusterN = 'vcf-m02-cl01'
$NewHosts = @('vcf-m02-esx02.home.lab','vcf-m02-esx03.home.lab','vcf-m02-esx04.home.lab')

$VdsName  = 'vcf-m02-cl01-vds01'
$VdsMtu   = 9000
$PgMgmt   = 'SDDC-DPortGroup-VM-Mgmt'      # VLAN 0(untagged),vmk0 搬到這
$PgVmot   = 'vcf-m02-cl01-vds01-pg-vmotion'
$PgVsan   = 'vcf-m02-cl01-vds01-pg-vsan'
$VlanVmot = 13
$VlanVsan = 14
$UplinkNics = @('vmnic0','vmnic1')          # vmnic2/3 留著不用

# vMotion / vSAN 的 IP(對齊 inventory)
$VmkMap = @{
    'vcf-m02-esx01.home.lab' = @{ vmotion='192.168.23.9';  vsan='192.168.24.9'  }
    'vcf-m02-esx02.home.lab' = @{ vmotion='192.168.23.10'; vsan='192.168.24.10' }
    'vcf-m02-esx03.home.lab' = @{ vmotion='192.168.23.11'; vsan='192.168.24.11' }
    'vcf-m02-esx04.home.lab' = @{ vmotion='192.168.23.12'; vsan='192.168.24.12' }
}
$VmkMask = '255.255.255.0'

function Log($m) { "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m | Tee-Object -Append 'E:\9.1\converge-target\build-target.log' }

# 🔴 這台機器的 OneDrive Modules 目錄殘留 PowerCLI 13.3.0 的 VMware.VimAutomation.Vds,
#    自動載入時會配到 13.5.0 的 Core/Sdk,VDS 相關 cmdlet 全部噴
#    "Field not found: 'VMware.VimAutomation.Sdk.Util10.VIObjectImpl._connectionId'"。
#    一律明確指定版本載入。
$PCLI = '13.5.1.25718932'
Import-Module VMware.VimAutomation.Sdk  -RequiredVersion $PCLI -ErrorAction Stop | Out-Null
Import-Module VMware.VimAutomation.Core -RequiredVersion $PCLI -ErrorAction Stop | Out-Null
Import-Module VMware.VimAutomation.Vds  -RequiredVersion $PCLI -ErrorAction Stop | Out-Null
Import-Module VMware.VimAutomation.Storage -RequiredVersion $PCLI -ErrorAction Stop | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null

Log "connecting $VC"
$srv = Connect-VIServer $VC -User $VCUser -Password $VCPass -Force
$cl  = Get-Cluster -Name $ClusterN
$dc  = Get-Datacenter -Name $DC
Log "cluster $($cl.Name), hosts now: $((Get-VMHost -Location $cl).Name -join ', ')"

# ── 1. 加主機 ──────────────────────────────────────────────────────────────
if (-not $SkipHostAdd) {
    foreach ($h in $NewHosts) {
        if (Get-VMHost -Name $h -ErrorAction SilentlyContinue) { Log "  $h already added"; continue }
        Log "  adding $h ..."
        Add-VMHost -Name $h -Location $cl -User root -Password $ESXPass -Force -Confirm:$false | Out-Null
    }
    Log "hosts: $((Get-VMHost -Location $cl | Sort-Object Name).Name -join ', ')"
}

$hosts = Get-VMHost -Location $cl | Sort-Object Name

# ── 2. VDS ────────────────────────────────────────────────────────────────
if (-not $SkipVds) {
    $vds = Get-VDSwitch -Name $VdsName -ErrorAction SilentlyContinue
    if (-not $vds) {
        Log "creating VDS $VdsName (MTU $VdsMtu, 2 uplinks)"
        $vds = New-VDSwitch -Name $VdsName -Location $dc -Mtu $VdsMtu -NumUplinkPorts 2
    }
    foreach ($pg in @(@{n=$PgMgmt;v=0}, @{n=$PgVmot;v=$VlanVmot}, @{n=$PgVsan;v=$VlanVsan})) {
        if (-not (Get-VDPortgroup -VDSwitch $vds -Name $pg.n -ErrorAction SilentlyContinue)) {
            Log "  portgroup $($pg.n) (VLAN $($pg.v))"
            $p = New-VDPortgroup -VDSwitch $vds -Name $pg.n -VlanId $pg.v
            # nested lab:三項安全性全開,否則 nested VM / vmk 會不通。
            # Get-VDSecurityPolicy 在這版 PowerCLI 會噴 _connectionId,改走原生 API。
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
    }

    foreach ($h in $hosts) {
        # 加主機進 VDS(可能上一次跑到一半只加了主機、沒加 uplink)
        if (-not (Get-VDSwitch -VMHost $h -Name $VdsName -ErrorAction SilentlyContinue)) {
            Log "  adding $($h.Name) to VDS"
            Add-VDSwitchVMHost -VDSwitch $vds -VMHost $h -Confirm:$false | Out-Null
        }
        # 🔴 uplink 一定要分開檢查:主機在 VDS 上不代表 pnic 也掛上去了。
        #    沒有 uplink 就把 VM 搬到 VDS portgroup = 直接把 VM(含 VCSA)斷線。
        $vdsPnics = @(Get-VMHostNetworkAdapter -VMHost $h -Physical -DistributedSwitch $vds -ErrorAction SilentlyContinue)
        if ($vdsPnics.Name -notcontains $UplinkNics[1]) {
            Log "  attaching $($UplinkNics[1]) on $($h.Name) to VDS"
            $nic1 = Get-VMHostNetworkAdapter -VMHost $h -Physical -Name $UplinkNics[1]
            Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vds -VMHostPhysicalNic $nic1 -Confirm:$false | Out-Null
            $vdsPnics = @(Get-VMHostNetworkAdapter -VMHost $h -Physical -DistributedSwitch $vds)
        }
        if ($vdsPnics.Count -lt 1) { throw "$($h.Name): VDS 上沒有任何 uplink,中止(再往下會把 VM 搬到沒有上行的 portgroup)" }
        Log "  $($h.Name) VDS uplinks: $($vdsPnics.Name -join ', ')"

        # 有 uplink 了才把這台主機上的 VM(含 VCSA 自己)搬到 VDS 的管理 portgroup。
        # 不先搬的話,等一下 vmnic0 被移走,vSwitch0 就沒有上行,VM 會整個斷線。
        $mgmtPgObj = Get-VDPortgroup -VDSwitch $vds -Name $PgMgmt
        foreach ($vm in (Get-VM -Location $h -ErrorAction SilentlyContinue)) {
            foreach ($na in (Get-NetworkAdapter -VM $vm)) {
                if ($na.NetworkName -ne $PgMgmt) {
                    Log "  moving VM $($vm.Name) NIC '$($na.NetworkName)' -> $PgMgmt"
                    Set-NetworkAdapter -NetworkAdapter $na -Portgroup $mgmtPgObj -Confirm:$false | Out-Null
                }
            }
        }

        # vmk0 + vmnic0 搬過去(一次做完,避免中斷管理連線)
        $vmk0 = Get-VMHostNetworkAdapter -VMHost $h -Name vmk0
        if ($vmk0.PortGroupName -ne $PgMgmt) {
            Log "  migrating vmk0 + $($UplinkNics[0]) on $($h.Name) -> $PgMgmt"
            $nic0 = Get-VMHostNetworkAdapter -VMHost $h -Physical -Name $UplinkNics[0]
            $mgmtPg = Get-VDPortgroup -VDSwitch $vds -Name $PgMgmt
            Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vds -VMHostPhysicalNic $nic0 `
                -VirtualNicPortgroup $mgmtPg -VMHostVirtualNic $vmk0 -Confirm:$false | Out-Null
        }
    }
}

# ── 3. vMotion / vSAN vmkernel ────────────────────────────────────────────
if (-not $SkipVds) {
    $vds = Get-VDSwitch -Name $VdsName
    foreach ($h in $hosts) {
        $ips = $VmkMap[$h.Name]
        if (-not $ips) { Log "  !! no vmk IP mapping for $($h.Name), skip"; continue }
        foreach ($spec in @(
            @{ pg=$PgVmot; ip=$ips.vmotion; svc='vmotion' },
            @{ pg=$PgVsan; ip=$ips.vsan;    svc='vsan'    })) {
            $exists = Get-VMHostNetworkAdapter -VMHost $h -VMKernel |
                      Where-Object { $_.PortGroupName -eq $spec.pg }
            if ($exists) { Log "  $($h.Name) $($spec.svc) vmk exists ($($exists.IP))"; continue }
            Log "  $($h.Name) new vmk $($spec.svc) $($spec.ip) on $($spec.pg)"
            $pg = Get-VDPortgroup -VDSwitch $vds -Name $spec.pg
            $nic = New-VMHostNetworkAdapter -VMHost $h -PortGroup $pg -VirtualSwitch $vds `
                     -IP $spec.ip -SubnetMask $VmkMask -Mtu $VdsMtu `
                     -VMotionEnabled:($spec.svc -eq 'vmotion') `
                     -VsanTrafficEnabled:($spec.svc -eq 'vsan') -Confirm:$false
        }
        # vmk0 只留 management
        $vmk0 = Get-VMHostNetworkAdapter -VMHost $h -Name vmk0
        if ($vmk0.VMotionEnabled -or $vmk0.VsanTrafficEnabled) {
            Log "  $($h.Name) vmk0: 關掉 vmotion/vsan 服務(改走專用 vmk)"
            $vmk0 | Set-VMHostNetworkAdapter -VMotionEnabled $false -VsanTrafficEnabled $false -Confirm:$false | Out-Null
        }
    }
}

# ── 4. vSAN 收碟 ───────────────────────────────────────────────────────────
if (-not $SkipVsan) {
    foreach ($h in $hosts) {
        if (Get-VsanDiskGroup -VMHost $h -ErrorAction SilentlyContinue) { Log "  $($h.Name) disk group exists"; continue }
        $disks = Get-VMHostDisk -VMHost $h | Where-Object { -not $_.ExtensionData.Ssd -or $true }
        $all = Get-ScsiLun -VmHost $h -LunType disk | Where-Object { $_.CapacityGB -gt 50 }
        $cache    = $all | Where-Object { [math]::Round($_.CapacityGB) -ge 95  -and [math]::Round($_.CapacityGB) -le 105 } | Select-Object -First 1
        $capacity = $all | Where-Object { [math]::Round($_.CapacityGB) -ge 900 } | Select-Object -First 1
        if (-not $cache -or -not $capacity) { Log "  !! $($h.Name): cache/capacity disk not found, skip"; continue }
        Log "  $($h.Name) new disk group: cache $($cache.CanonicalName) + capacity $($capacity.CanonicalName)"
        New-VsanDiskGroup -VMHost $h -SsdCanonicalName $cache.CanonicalName `
            -DataDiskCanonicalName $capacity.CanonicalName -Confirm:$false | Out-Null
    }
}

# ── 5. DRS / HA ───────────────────────────────────────────────────────────
Log "enabling DRS (FullyAutomated) + HA"
Set-Cluster -Cluster $cl -DrsEnabled $true -DrsAutomationLevel FullyAutomated -Confirm:$false | Out-Null
Set-Cluster -Cluster $cl -HAEnabled $true -Confirm:$false | Out-Null

Log "=== summary ==="
Get-VMHost -Location $cl | Sort-Object Name |
    Select-Object Name, ConnectionState, PowerState, Version, Build |
    Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
Get-Datastore | Select-Object Name, Type, CapacityGB, FreeSpaceGB |
    Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }

Disconnect-VIServer $srv -Confirm:$false | Out-Null
Log "done"
