# w01 繞道:vMotion / vSAN 直接走 vmk0(管理網)。
# 原因:這套 nested ESXi 8.0.3 上,除了 vmk0 之外的 dvPort 都收不到 unicast,
#       portgroup / VLAN / MTU / 安全性政策逐項排除後仍然如此(見 w01-vmk-rebuild.log)。
#       vmk0 是唯一通的路徑,nested lab 用它跑 vSAN 完全可行。
#   $env:VCPASS='...'; pwsh ./Use-Vmk0-ForVsan.ps1
$ErrorActionPreference = 'Stop'
$PCLI = '13.5.1.25718932'
'Sdk','Core','Vds','Storage' | ForEach-Object { Import-Module "VMware.VimAutomation.$_" -RequiredVersion $PCLI | Out-Null }
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null

$VC     = 'vcf-w01-vc01.home.lab'
$VCPass = if ($env:VCPASS) { $env:VCPASS } else { throw 'set $env:VCPASS' }
$PgVmot = 'vcf-w01-cl01-vds01-pg-vmotion'
$PgVsan = 'vcf-w01-cl01-vds01-pg-vsan'
function Log($m) { "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m | Tee-Object -Append 'E:\9.1\converge-target\w01-vmk0-vsan.log' }

$srv = Connect-VIServer $VC -User 'administrator@vsphere.local' -Password $VCPass -Force

foreach ($h in (Get-VMHost | Sort-Object Name)) {
    # 砍掉走不通的 vmk1 / vmk2
    foreach ($pgName in @($PgVmot, $PgVsan)) {
        $vmk = Get-VMHostNetworkAdapter -VMHost $h -VMKernel | Where-Object { $_.PortGroupName -eq $pgName }
        if ($vmk) { Log "remove $($h.Name) $($vmk.Name)"; Remove-VMHostNetworkAdapter -Nic $vmk -Confirm:$false }
    }
    # vmk0 打開 vMotion + vSAN
    $vmk0 = Get-VMHostNetworkAdapter -VMHost $h -Name vmk0
    Log "$($h.Name) vmk0 ($($vmk0.IP)) -> enable vMotion + vSAN"
    $vmk0 | Set-VMHostNetworkAdapter -VMotionEnabled $true -VsanTrafficEnabled $true -Confirm:$false | Out-Null
}

Log "=== vmk summary ==="
foreach ($h in (Get-VMHost | Sort-Object Name)) {
    Get-VMHostNetworkAdapter -VMHost $h -VMKernel |
        Select-Object @{n='Host';e={$h.Name}}, Name, PortGroupName, IP, VMotionEnabled, VsanTrafficEnabled |
        Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
}
Disconnect-VIServer $srv -Confirm:$false | Out-Null
Log 'done'
