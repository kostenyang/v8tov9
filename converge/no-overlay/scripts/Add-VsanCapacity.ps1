# 把每台 nested ESXi 新加的 1000 GB 磁碟收進既有的 vSAN disk group(當第二顆 capacity)。
#   $env:VCPASS='...'; pwsh ./Add-VsanCapacity.ps1
$ErrorActionPreference = 'Stop'
$PCLI = '13.5.1.25718932'
Import-Module VMware.VimAutomation.Sdk     -RequiredVersion $PCLI | Out-Null
Import-Module VMware.VimAutomation.Core    -RequiredVersion $PCLI | Out-Null
Import-Module VMware.VimAutomation.Storage -RequiredVersion $PCLI | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null

$VC     = 'vcf-m02-vc01.home.lab'
$VCPass = if ($env:VCPASS) { $env:VCPASS } else { throw 'set $env:VCPASS' }
function Log($m) { "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m | Tee-Object -Append 'E:\9.1\converge-target\add-vsan-capacity.log' }

$srv = Connect-VIServer $VC -User 'administrator@vsphere.local' -Password $VCPass -Force
foreach ($h in (Get-VMHost | Sort-Object Name)) {
    $dg = Get-VsanDiskGroup -VMHost $h
    if (-not $dg) { Log "$($h.Name): 沒有 disk group,跳過"; continue }
    $claimed = (Get-VsanDisk -VsanDiskGroup $dg).CanonicalName
    $cand = Get-ScsiLun -VmHost $h -LunType disk |
            Where-Object { [math]::Round($_.CapacityGB) -ge 900 -and $claimed -notcontains $_.CanonicalName }
    if (-not $cand) { Log "$($h.Name): 沒有未收編的 1000 GB 磁碟"; continue }
    foreach ($d in $cand) {
        Log "$($h.Name): 加入 capacity disk $($d.CanonicalName) ($([math]::Round($d.CapacityGB)) GB)"
        # 這版 PowerCLI 沒有 Add-VsanDisk;往既有 disk group 加 capacity 用 New-VsanDisk,
        # 而且參數是 -CanonicalName(不是 New-VsanDiskGroup 的 -DataDiskCanonicalName)
        New-VsanDisk -VsanDiskGroup $dg -CanonicalName $d.CanonicalName -Confirm:$false | Out-Null
    }
}
Start-Sleep 10
Log '=== 結果 ==='
Get-VsanDiskGroup | ForEach-Object {
    $n = (Get-VsanDisk -VsanDiskGroup $_).Count
    Log ("  {0,-24} disks={1}" -f $_.VMHost.Name, $n)
}
Get-Datastore -Name vsanDatastore | ForEach-Object {
    Log ("  vsanDatastore  capacity={0:N0} GB  free={1:N0} GB" -f $_.CapacityGB, $_.FreeSpaceGB)
}
Disconnect-VIServer $srv -Confirm:$false | Out-Null
