# =============================================================================
# Coverage lab 階段 2:部署 workload domain 來源端的 nested ESXi(8.0U3b)
#
#   vcf-w01-esx01~03 / 10.0.1.46-48,各 16 vCPU / 96 GB
#   cache 100 GB + capacity 500 GB,網路 Trunk-Nobinding
#   刻意**不設 reservation**(mgmt 那 4 台已佔 512 GB)
#
#   $env:VIPASS='...'; $env:ESXPASS='...'; pwsh ./Deploy-W01-NestedESXi.ps1
# =============================================================================
$ErrorActionPreference = 'Stop'
$PCLI = '13.5.1.25718932'
Import-Module VMware.VimAutomation.Sdk  -RequiredVersion $PCLI | Out-Null
Import-Module VMware.VimAutomation.Core -RequiredVersion $PCLI | Out-Null
Import-Module VMware.VimAutomation.Vds  -RequiredVersion $PCLI | Out-Null   # 不釘版本 -> VDS cmdlet 噴 _connectionId
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null

$VIServer = '10.0.0.101'
$VIUser   = 'administrator@vsphere.local'
$VIPass   = if ($env:VIPASS)  { $env:VIPASS }  else { throw 'set $env:VIPASS' }
$ESXPass  = if ($env:ESXPASS) { $env:ESXPASS } else { throw 'set $env:ESXPASS' }

$OVA      = 'C:\Users\Administrator\OneDrive\桌面\VCF\Nested_ESXi8.0u3b_Appliance_Template_v1.ova'
$Net      = 'Trunk-Nobinding'
$Cluster  = 'Cluster'
$Folder   = 'VCF'
$TargetHost = '10.0.0.95'
$VAppName = 'Nested-VCF-W01'

$Mask='255.255.254.0'; $GW='10.0.0.1'; $DNS='10.0.0.200'; $NTP='10.0.1.254'; $Domain='home.lab'
$vCPU=16; $vMEMGB=96; $CacheGB=100; $CapGB=500

$Hosts = [ordered]@{
    'vcf-w01-esx01' = @{ ip='10.0.1.46'; ds='ForNFS' }
    'vcf-w01-esx02' = @{ ip='10.0.1.47'; ds='vmfs-wdblue4t' }
    'vcf-w01-esx03' = @{ ip='10.0.1.48'; ds='ForNFS' }
}

function Log($m) { "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m | Tee-Object -Append 'E:\9.1\converge-target\w01-deploy.log' }

Log "connecting $VIServer"
$vi = Connect-VIServer $VIServer -User $VIUser -Password $VIPass -Force -WarningAction SilentlyContinue
$cl = Get-Cluster -Name $Cluster
$vmhost = Get-VMHost -Name $TargetHost
$fld = Get-Folder -Name $Folder -Type VM | Select-Object -First 1

$ovfTemplate = Get-OvfConfiguration $OVA
$nml = ($ovfTemplate.ToHashTable().keys | Where-Object { $_ -match 'NetworkMapping' }) `
        -replace 'NetworkMapping\.', '' -replace '-', '_' -replace ' ', '_'
Log "OVA network mapping key: $nml"

$created = @()
foreach ($name in $Hosts.Keys) {
    if (Get-VM -Name $name -ErrorAction SilentlyContinue) { Log "$name 已存在,跳過"; continue }
    $ip = $Hosts[$name].ip; $ds = Get-Datastore -Name $Hosts[$name].ds
    $ovf = Get-OvfConfiguration $OVA
    $ovf.NetworkMapping.$nml.value              = $Net
    # 注意:ToHashTable() 會把 Common. 前綴吃掉,但物件存取仍要走 $ovf.Common.guestinfo.*
    $ovf.Common.guestinfo.hostname.value   = "$name.$Domain"
    $ovf.Common.guestinfo.ipaddress.value  = $ip
    $ovf.Common.guestinfo.netmask.value    = $Mask
    $ovf.Common.guestinfo.gateway.value    = $GW
    $ovf.Common.guestinfo.dns.value        = $DNS
    $ovf.Common.guestinfo.domain.value     = $Domain
    $ovf.Common.guestinfo.ntp.value        = $NTP
    $ovf.Common.guestinfo.password.value   = $ESXPass
    $ovf.Common.guestinfo.ssh.value        = $true
    $ovf.Common.guestinfo.createvmfs.value = $false      # 碟要留給 vSAN,不要自動建 VMFS
    Log "deploying $name ($ip) on $($ds.Name) ..."
    $vm = Import-VApp -Source $OVA -OvfConfiguration $ovf -Name $name `
            -Location $cl -VMHost $vmhost -Datastore $ds -InventoryLocation $fld -DiskStorageFormat thin

    Log "  adding vmnic2/vmnic3"
    $pg = Get-VDPortgroup -Name $Net -ErrorAction SilentlyContinue
    if ($pg) { 1..2 | ForEach-Object { New-NetworkAdapter -VM $vm -Portgroup $pg -StartConnected -Type Vmxnet3 -Confirm:$false | Out-Null } }
    else     { 1..2 | ForEach-Object { New-NetworkAdapter -VM $vm -NetworkName $Net -StartConnected -Type Vmxnet3 -Confirm:$false | Out-Null } }

    Log "  vCPU=$vCPU vMEM=${vMEMGB}GB"
    Set-VM -VM $vm -NumCpu $vCPU -MemoryGB $vMEMGB -Confirm:$false | Out-Null

    # 🔴 不要用容量排序挑碟!這顆 8.0U3b OVA 的第一顆(16 GB)才是 ESXi 開機碟,
    #    4 GB / 8 GB 分別是 cache / capacity。照裝置順序取,不要排序。
    $disks = Get-HardDisk -VM $vm
    Log "  disks(device order): $(($disks | ForEach-Object { [math]::Round($_.CapacityGB) }) -join ',') -- [0]=boot 不動"
    Log "  cache -> ${CacheGB}GB, capacity -> ${CapGB}GB"
    Set-HardDisk -HardDisk $disks[1] -CapacityGB $CacheGB -Confirm:$false | Out-Null
    Set-HardDisk -HardDisk $disks[2] -CapacityGB $CapGB   -Confirm:$false | Out-Null

    Log "  powering on"
    Start-VM -VM $vm -RunAsync | Out-Null
    $created += $vm
}

if ($created.Count -gt 0) {
    if (-not (Get-VApp -Name $VAppName -ErrorAction SilentlyContinue)) {
        Log "creating vApp $VAppName"
        New-VApp -Name $VAppName -Location $cl | Out-Null
    }
    Log "moving VMs into $VAppName"
    Get-VM -Name 'vcf-w01-esx0*' | Move-VM -Destination (Get-VApp -Name $VAppName) -Confirm:$false | Out-Null
    Move-VApp -VApp (Get-VApp -Name $VAppName) -Destination $fld -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
}

Log "=== summary ==="
Get-VM -Name 'vcf-w01-esx0*' | Select-Object Name, NumCpu, MemoryGB, PowerState |
    Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
Disconnect-VIServer $vi -Confirm:$false | Out-Null
Log 'done'
