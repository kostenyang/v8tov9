# deploy-lic-pcli.ps1 — 部署 VCF License Server（PowerCLI Import-VApp）
# air-gapped：otk 用 placeholder（真實註冊需 Broadcom BSC/網路，此處僅為部署示範+截圖）
$ErrorActionPreference='Stop'
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Connect-VIServer -Server 192.168.110.142 -User 'administrator@vsphere.local' -Password '<VC_ESXI_PASSWORD>' | Out-Null
$ova = "$env:TEMP\lic-ova\Vcf-License-Server-9.1.0.0400.25541557.ovf"  # 已移除簽章的 unsigned OVF
$cfg = Get-OvfConfiguration $ova
$cfg.NetworkMapping.Network_1.Value = 'SDDC-DPortGroup-VM-Mgmt'
$cfg.Common.hostname.Value = 'vcf-lic01'
$cfg.Common.otk.Value = 'AIRGAP-PLACEHOLDER-NO-BSC-REGISTRATION'
$cfg.Common.dns.VCF_License_Server_Appliance.Value = '192.168.110.1'
$cfg.Common.domain.VCF_License_Server_Appliance.Value = 'kosten.lab'
$cfg.Common.searchpath.VCF_License_Server_Appliance.Value = 'kosten.lab'
$cfg.Common.gateway.VCF_License_Server_Appliance.Value = '192.168.110.254'
$cfg.Common.ip0.VCF_License_Server_Appliance.Value = '192.168.110.151'
$cfg.Common.netmask0.VCF_License_Server_Appliance.Value = '255.255.255.0'
"=== 將套用 ==="
"host=$($cfg.Common.hostname.Value) ip=$($cfg.Common.ip0.VCF_License_Server_Appliance.Value) gw=$($cfg.Common.gateway.VCF_License_Server_Appliance.Value) dns=$($cfg.Common.dns.VCF_License_Server_Appliance.Value) domain=$($cfg.Common.domain.VCF_License_Server_Appliance.Value)"
$vmhost = Get-VMHost | Sort-Object MemoryUsageGB | Select-Object -First 1
$ds = Get-Datastore 'vcf-m01-cl01-ds-vsan01'
"=== Import-VApp 到 $($vmhost.Name) (thin, 不開機) ==="
$vapp = Import-VApp -Source $ova -OvfConfiguration $cfg -Name 'vcf-lic01' -VMHost $vmhost -Datastore $ds -DiskStorageFormat Thin
"Imported: $($vapp.Name)  Power=$((Get-VM vcf-lic01).PowerState)"
Disconnect-VIServer -Confirm:$false
