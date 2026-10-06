# =============================================================================
# 把舊的 m03 nested 主機瘦身,騰出 CPU 給新的 greenfield 叢集
#
#   舊叢集之後的唯一工作 = 讓 vcf-m03-ops01 / vcf-m03-lic01 繼續活著當「既有元件」,
#   不需要 16 vCPU x4。縮到 4 vCPU / 64 GB。
#
#   🔴 CPU 超配是這個 lab 的已知地雷(216 vCPU / 32 核 曾害 vMotion 卡死 0%)。
#      舊 4x16 + 新 4x16 = 128 vCPU on 32 核 = 4:1,縮完變 80 vCPU = 2.5:1。
#
#   $env:VIPASS='...'; $env:NVCPASS='...'; pwsh ./Shrink-OldM03.ps1
# =============================================================================
$ErrorActionPreference = 'Stop'
$PCLI = '13.5.1.25718932'
Import-Module VMware.VimAutomation.Sdk  -RequiredVersion $PCLI | Out-Null
Import-Module VMware.VimAutomation.Core -RequiredVersion $PCLI | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Multiple -Confirm:$false -Scope Session | Out-Null

$Outer   = '10.0.0.101'; $OuterUser = 'administrator@vsphere.local'
$Nested  = '10.0.1.60';  $NestedUser = 'administrator@vsphere.local'
$VIPass  = if ($env:VIPASS)  { $env:VIPASS }  else { throw 'set $env:VIPASS' }
$NVCPass = if ($env:NVCPASS) { $env:NVCPASS } else { throw 'set $env:NVCPASS' }

$OldHosts = 'vcf-m03-esx01','vcf-m03-esx02','vcf-m03-esx03','vcf-m03-esx04'
$Guests   = 'vcf-m03-ops01','vcf-m03-lic01'       # vc01 最後關
$NewCpu = 4; $NewMemGB = 64

function Log($m) { "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m | Tee-Object -Append 'E:\9.1\m03\shrink.log' }

# --- 1) 在 nested vCenter 裡把 appliance 優雅關機 -----------------------------
Log "連 nested vCenter $Nested"
$nvc = Connect-VIServer $Nested -User $NestedUser -Password $NVCPass -Force -WarningAction SilentlyContinue
foreach ($g in $Guests) {
    $vm = Get-VM -Server $nvc -Name $g -ErrorAction SilentlyContinue
    if ($vm -and $vm.PowerState -eq 'PoweredOn') {
        Log "  guest shutdown $g"
        Stop-VMGuest -VM $vm -Confirm:$false | Out-Null
    }
}
Log "  等 appliance 關完(最多 5 分鐘)"
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
    $still = Get-VM -Server $nvc -Name $Guests -ErrorAction SilentlyContinue |
             Where-Object { $_.PowerState -eq 'PoweredOn' }
    if (-not $still) { break }
    Start-Sleep 15
}
Log ("  剩下還開著: " + ((Get-VM -Server $nvc -Name $Guests -ErrorAction SilentlyContinue |
      Where-Object PowerState -eq 'PoweredOn').Name -join ',' | ForEach-Object { if ($_) { $_ } else { '(無)' } }))
Disconnect-VIServer $nvc -Confirm:$false | Out-Null

# --- 2) 在外層把 vc01 與 nested 主機關掉 --------------------------------------
Log "連外層 vCenter $Outer"
$ovc = Connect-VIServer $Outer -User $OuterUser -Password $VIPass -Force -WarningAction SilentlyContinue

# vc01 是 nested VM,用 guest shutdown(它就在 nested 叢集裡,只能從主機層關)
# 直接關 nested 主機即可:先 guest shutdown 主機,ESXi 會自己處理上面的 VM
foreach ($h in $OldHosts) {
    $vm = Get-VM -Server $ovc -Name $h
    if ($vm.PowerState -eq 'PoweredOn') {
        Log "  guest shutdown nested host $h"
        try { Stop-VMGuest -VM $vm -Confirm:$false | Out-Null } catch { Log "    (guest shutdown 失敗,改硬關) $_"; Stop-VM -VM $vm -Confirm:$false | Out-Null }
    }
}
Log "  等主機關完(最多 6 分鐘)"
$deadline = (Get-Date).AddMinutes(6)
while ((Get-Date) -lt $deadline) {
    $still = Get-VM -Server $ovc -Name $OldHosts | Where-Object { $_.PowerState -eq 'PoweredOn' }
    if (-not $still) { break }
    Start-Sleep 15
}
$still = Get-VM -Server $ovc -Name $OldHosts | Where-Object { $_.PowerState -eq 'PoweredOn' }
if ($still) { Log ("  逾時,硬關: " + ($still.Name -join ',')); $still | Stop-VM -Confirm:$false | Out-Null; Start-Sleep 10 }

# --- 3) 瘦身 -----------------------------------------------------------------
foreach ($h in $OldHosts) {
    $vm = Get-VM -Server $ovc -Name $h
    Log ("  {0}: {1} vCPU / {2} GB  ->  {3} vCPU / {4} GB" -f $h, $vm.NumCpu, [int]$vm.MemoryGB, $NewCpu, $NewMemGB)
    Set-VM -VM $vm -NumCpu $NewCpu -MemoryGB $NewMemGB -Confirm:$false | Out-Null
}

# --- 4) 開回來 ----------------------------------------------------------------
foreach ($h in $OldHosts) { Log "  power on $h"; Start-VM -Server $ovc -VM (Get-VM -Server $ovc -Name $h) -RunAsync | Out-Null }

Log '=== 結果 ==='
Get-VM -Server $ovc -Name $OldHosts | Select-Object Name, NumCpu, MemoryGB, PowerState |
    Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
Disconnect-VIServer $ovc -Confirm:$false | Out-Null
Log 'done — nested 主機開機約 3-5 分鐘,之後 vc01/ops01/lic01 會自己跟著起來(若沒有要手動開)'
