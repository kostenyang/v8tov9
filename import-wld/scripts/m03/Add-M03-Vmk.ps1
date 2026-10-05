# m03:補上專用的 vMotion / vSAN vmkernel(m02 驗過的配方),並關掉 vmk0 的 vmotion
$ErrorActionPreference='Stop'
$PCLI='13.5.1.25718932'
'Sdk','Core','Vds','Storage' | ForEach-Object { Import-Module "VMware.VimAutomation.$_" -RequiredVersion $PCLI | Out-Null }
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null
$VC='vcf-m03-vc01.home.lab'
$VCPass= if($env:VCPASS){$env:VCPASS}else{throw 'set $env:VCPASS'}
$VdsName='vcf-m03-cl01-vds01'
$PgVmot='vcf-m03-cl01-vds01-pg-vmotion'; $PgVsan='vcf-m03-cl01-vds01-pg-vsan'
$Mtu=1500   # 跟 vmk0 一致,外層路徑只有 1500
$VmkMap=@{
  'vcf-m03-esx01.home.lab'=@{vmotion='192.168.35.11'}
  'vcf-m03-esx02.home.lab'=@{vmotion='192.168.35.12'}
  'vcf-m03-esx03.home.lab'=@{vmotion='192.168.35.13'}
  'vcf-m03-esx04.home.lab'=@{vmotion='192.168.35.14'}
}
function Log($m){ "[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -Append 'E:\9.1\m03\vmk.log' }
$srv=Connect-VIServer $VC -User 'administrator@vsphere.local' -Password $VCPass -Force
$vds=Get-VDSwitch -Name $VdsName
foreach($h in (Get-VMHost | Sort-Object Name)){
  $ips=$VmkMap[$h.Name]; if(-not $ips){ Log "no map for $($h.Name)"; continue }
  $ex=Get-VMHostNetworkAdapter -VMHost $h -VMKernel | Where-Object { $_.PortGroupName -eq $PgVmot }
  if($ex){ Log "$($h.Name) vMotion vmk 已存在 $($ex.IP)" }
  else{
    Log "$($h.Name) 建 vMotion vmk $($ips.vmotion) mtu=$Mtu"
    $pg=Get-VDPortgroup -VDSwitch $vds -Name $PgVmot
    New-VMHostNetworkAdapter -VMHost $h -PortGroup $pg -VirtualSwitch $vds `
      -IP $ips.vmotion -SubnetMask '255.255.255.0' -Mtu $Mtu -VMotionEnabled:$true -Confirm:$false | Out-Null
  }
  $vmk0=Get-VMHostNetworkAdapter -VMHost $h -Name vmk0
  if($vmk0.VMotionEnabled){
    Log "  $($h.Name) vmk0 關掉 vMotion(保留 management + vSAN)"
    $vmk0 | Set-VMHostNetworkAdapter -VMotionEnabled $false -Confirm:$false | Out-Null
  }
}
Log "=== vmk 總覽 ==="
foreach($h in (Get-VMHost | Sort-Object Name)){
  Get-VMHostNetworkAdapter -VMHost $h -VMKernel |
    Select-Object @{n='Host';e={$h.Name}},Name,PortGroupName,IP,Mtu,VMotionEnabled,VsanTrafficEnabled |
    Format-Table -AutoSize | Out-String | ForEach-Object { Log $_ }
}
Disconnect-VIServer $srv -Confirm:$false | Out-Null
