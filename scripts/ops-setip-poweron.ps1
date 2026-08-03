# ops-setip-poweron.ps1 — 在關機狀態設好 vApp Static IP，再單次開機（不打斷 firstboot）
$ErrorActionPreference='Stop'
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Connect-VIServer -Server 192.168.110.142 -User 'administrator@vsphere.local' -Password '<VC_ESXI_PASSWORD>' | Out-Null
$view = Get-VM vcf-ops01 | Get-View
if($view.Runtime.PowerState -ne 'poweredOff'){ throw "VM 不是關機狀態，先確認" }
$props = $view.Config.VAppConfig.Property
$want = @{
  'ipv4_type'='Static'; 'ipv4_address'='192.168.110.150'; 'ipv4_netmask'='255.255.255.0'
  'ipv4_gateway'='192.168.110.254'; 'DNS'='192.168.110.1'; 'domain'='kosten.lab'
  'searchpath'='kosten.lab'; 'ipv6_type'='Disabled'
}
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.VAppConfig = New-Object VMware.Vim.VmConfigSpec
$specs=@()
foreach($p in $props){ if($want.ContainsKey($p.Id)){
  $ps=New-Object VMware.Vim.VAppPropertySpec; $ps.Operation='edit'
  $ps.Info=New-Object VMware.Vim.VAppPropertyInfo; $ps.Info.Key=$p.Key; $ps.Info.Value=$want[$p.Id]
  $specs+=$ps; "set {0}(key={1})={2}" -f $p.Id,$p.Key,$want[$p.Id]
}}
$spec.VAppConfig.Property=$specs
$view.ReconfigVM($spec)
"vApp 屬性已設。開機（單次，不打斷）..."
Start-VM -VM (Get-VM vcf-ops01) | Out-Null
"Powered on. firstboot 開始，勿打斷。"
Disconnect-VIServer -Confirm:$false
