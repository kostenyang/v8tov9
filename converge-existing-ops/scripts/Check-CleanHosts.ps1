# =============================================================================
# 用 VCF Installer 驗證的六項標準,逐台檢查 nested ESXi 是不是「乾淨主機」
#
#   對照的錯誤碼(來自 9.1.1 Installer 實測):
#     MANAGEMENT_VSWITCH_VMNIC_IN_USE   vSwitch0 要剛好 1 張 pnic
#     VMNIC_IN_USE                      其餘 vmnic 要未指派
#     MORE_THAN_ONE_VMKERNEL_CONFIGURED 只能有 vmk0
#     VSAN_PARTITION_FOUND_ON_HOST      磁碟不能有 vSAN partition
#     VSAN_ZERO_SSD_DISKS_VALIDATION    至少一顆要是 SSD
#     VSWITCH_EXISTS                    不能有 VDS
#
#   $env:ESXPASS='...'; pwsh ./Check-CleanHosts.ps1 [-Hosts a,b,c]
# =============================================================================
param([string[]]$Hosts = @('10.0.1.110','10.0.1.111','10.0.1.112','10.0.1.113'))
$ErrorActionPreference = 'Stop'
$PCLI = '13.5.1.25718932'
'Sdk','Core' | ForEach-Object { Import-Module "VMware.VimAutomation.$_" -RequiredVersion $PCLI | Out-Null }
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Multiple -Confirm:$false -Scope Session | Out-Null

$EsxPass = if ($env:ESXPASS) { $env:ESXPASS } else { throw 'set $env:ESXPASS' }
$ok = $true

foreach ($h in $Hosts) {
    Write-Output "=============================================================="
    Write-Output "  $h"
    Write-Output "=============================================================="
    try { $c = Connect-VIServer $h -User root -Password $EsxPass -Force -WarningAction SilentlyContinue }
    catch { Write-Output "  [X] 連不上:$_"; $ok = $false; continue }

    $vmh = Get-VMHost -Server $c
    $esx = Get-View -Server $c $vmh.Id

    # 1) vSwitch0 的 pnic 數
    $vsw = $esx.Config.Network.Vswitch | Where-Object { $_.Name -eq 'vSwitch0' }
    $n = @($vsw.Pnic).Count
    $r = if ($n -eq 1) { '[v]' } else { '[X]'; $ok = $false }
    Write-Output ("  {0} vSwitch0 pnic 數 = {1}   (期待 1)" -f $r, $n)

    # 2) 未指派的 vmnic
    $all = $esx.Config.Network.Pnic.Device
    $used = @()
    $esx.Config.Network.Vswitch | ForEach-Object { $used += ($_.Pnic -replace '^key-vim\.host\.PhysicalNic-','') }
    $esx.Config.Network.ProxySwitch | ForEach-Object { $used += ($_.Pnic -replace '^key-vim\.host\.PhysicalNic-','') }
    $free = $all | Where-Object { $_ -notin $used }
    Write-Output ("      實體網卡 = {0};已用 = {1};未指派 = {2}" -f ($all -join ','), (($used | Sort-Object -Unique) -join ','), (($free -join ',') -replace '^$','(無)'))

    # 3) VMkernel 數
    $vmks = $esx.Config.Network.Vnic.Device
    $r = if (@($vmks).Count -eq 1 -and $vmks -contains 'vmk0') { '[v]' } else { '[X]'; $ok = $false }
    Write-Output ("  {0} VMkernel = {1}   (期待只有 vmk0)" -f $r, ($vmks -join ','))

    # 4) VDS(proxy switch)
    # 🔴 PowerShell 陷阱:@($null).Count 是 1 不是 0,要先過濾掉 null
    $pswitch = @($esx.Config.Network.ProxySwitch | Where-Object { $_ })
    $r = if ($pswitch.Count -eq 0) { '[v]' } else { '[X]'; $ok = $false }
    Write-Output ("  {0} 分散式交換器 = {1}   (期待沒有)" -f $r, ((($pswitch.DvsName) -join ',') -replace '^$','(無)'))

    # 5/6) 磁碟:SSD 標記 + 有沒有被佔用
    $disks = $esx.Config.StorageDevice.ScsiLun | Where-Object { $_.DeviceType -eq 'disk' }
    $ssd = @($disks | Where-Object { $_.Ssd })
    $r = if ($ssd.Count -ge 1) { '[v]' } else { '[X]'; $ok = $false }
    Write-Output ("  {0} SSD 磁碟數 = {1} / 總磁碟 {2}   (期待 >=1)" -f $r, $ssd.Count, @($disks).Count)
    foreach ($d in $disks) {
        $cap = [math]::Round(($d.Capacity.Block * $d.Capacity.BlockSize) / 1GB)
        Write-Output ("      {0,-42} {1,5} GB  SSD={2}  local={3}" -f $d.CanonicalName, $cap, $d.Ssd, $d.LocalDisk)
    }
    $vsanDs = Get-Datastore -Server $c -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'vsan' }
    $r = if (-not $vsanDs) { '[v]' } else { '[X]'; $ok = $false }
    Write-Output ("  {0} vSAN datastore = {1}   (期待沒有)" -f $r, (($vsanDs.Name -join ',') -replace '^$','(無)'))

    Write-Output ("      版本 {0} build {1}" -f $vmh.Version, $vmh.Build)
    Disconnect-VIServer $c -Confirm:$false | Out-Null
}
Write-Output ""
Write-Output $(if ($ok) { 'ALL-CLEAN — 四台都符合 Installer 的乾淨主機標準' } else { 'NOT-CLEAN — 上面有 [X] 的項目要處理' })
