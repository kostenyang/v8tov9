# deploy-ops-pcli.ps1 — 用 PowerCLI Import-VApp 部署 VCF Operations（一次設對含 instance 的網路屬性）
$ErrorActionPreference='Stop'
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Connect-VIServer -Server 192.168.110.142 -User 'administrator@vsphere.local' -Password '<VC_ESXI_PASSWORD>' | Out-Null

$ova = "E:\Operations-Appliance-9.1.0.0400.25541561.ova"
$cfg = Get-OvfConfiguration $ova

# deployment size + 網路
$cfg.DeploymentOption.Value = 'xsmall'
$cfg.NetworkMapping.Network_1.Value = 'SDDC-DPortGroup-VM-Mgmt'

# 預設段屬性
$cfg.Common.root_password.Value = '<NSX_SDDC_OPS_PASSWORD>'
$cfg.Common.timezone.Value      = 'Asia/Taipei'

# instance 段（VMware_Aria_Operations）網路屬性 — 用完整路徑賦值
$cfg.Common.VMware_Aria_Operations.domain.Value       = 'kosten.lab'
$cfg.Common.VMware_Aria_Operations.searchpath.Value   = 'kosten.lab'
$cfg.Common.VMware_Aria_Operations.DNS.Value          = '192.168.110.1'
$cfg.Common.VMware_Aria_Operations.ipv4_type.Value    = 'Static'
$cfg.Common.VMware_Aria_Operations.ipv4_address.Value = '192.168.110.150'
$cfg.Common.VMware_Aria_Operations.ipv4_gateway.Value = '192.168.110.254'
$cfg.Common.VMware_Aria_Operations.ipv4_netmask.Value = '255.255.255.0'
$cfg.Common.VMware_Aria_Operations.ipv6_type.Value    = 'Disabled'

# 印出將套用的值確認
"=== 將套用 ==="
"size=$($cfg.DeploymentOption.Value) net=$($cfg.NetworkMapping.Network_1.Value)"
"ipv4=$($cfg.Common.VMware_Aria_Operations.ipv4_type.Value) $($cfg.Common.VMware_Aria_Operations.ipv4_address.Value)/$($cfg.Common.VMware_Aria_Operations.ipv4_netmask.Value) gw=$($cfg.Common.VMware_Aria_Operations.ipv4_gateway.Value) dns=$($cfg.Common.VMware_Aria_Operations.DNS.Value) domain=$($cfg.Common.VMware_Aria_Operations.domain.Value)"

$vmhost = Get-VMHost | Sort-Object MemoryUsageGB | Select-Object -First 1
$ds     = Get-Datastore 'vcf-m01-cl01-ds-vsan01'
"=== Import-VApp 到 $($vmhost.Name) / $($ds.Name) (thin, 不開機) ==="
$vapp = Import-VApp -Source $ova -OvfConfiguration $cfg -Name 'vcf-ops01' -VMHost $vmhost -Datastore $ds -DiskStorageFormat Thin
"Imported: $($vapp.Name)  Power=$((Get-VM vcf-ops01).PowerState)"
Disconnect-VIServer -Confirm:$false
