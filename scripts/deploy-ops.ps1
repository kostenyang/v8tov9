# deploy-ops.ps1 — 部署 VCF Operations Appliance (xsmall) 到 nested vCenter 9.1
# 用 ovftool 對 vCenter target 注入 vApp OVF 屬性（host client 會漏注入 → 一定走 vCenter）
$ErrorActionPreference = 'Stop'
$ovf  = "C:\Program Files\VMware\VMware OVF Tool\ovftool.exe"
$ova  = "E:\Operations-Appliance-9.1.0.0400.25541561.ova"

# --- vCenter target（帳密特殊字元需 URL-encode：@=%40  !=%21）---
$vcUser = "administrator%40vsphere.local"
$vcPass = "VMware1%21PSO"
$vcHost = "192.168.110.142"
$dc     = "vcf-m01-dc01"
$cluster= "vcf-m01-cl01"
$target = "vi://${vcUser}:${vcPass}@${vcHost}/${dc}/host/${cluster}/Resources"  # DRS 叢集根資源池

# --- 部署參數 ---
$args = @(
  "--acceptAllEulas"
  "--allowExtraConfig"
  "--noSSLVerify"
  "--name=vcf-ops01"
  "--deploymentOption=xsmall"                       # 2 vCPU / 8GB（lab 最小）
  "--datastore=vcf-m01-cl01-ds-vsan01"
  "--diskMode=thin"
  "--net:Network 1=SDDC-DPortGroup-VM-Mgmt"
  "--prop:root_password=<NSX_SDDC_OPS_PASSWORD>"            # >=15 字元
  "--prop:timezone=Asia/Taipei"
  "--prop:domain=kosten.lab"
  "--prop:searchpath=kosten.lab"
  "--prop:DNS=192.168.110.1"
  "--prop:ipv4_type=Static"
  "--prop:ipv4_address=192.168.110.150"
  "--prop:ipv4_gateway=192.168.110.254"
  "--prop:ipv4_netmask=255.255.255.0"
  "--prop:ipv6_type=Disabled"
  # 注意：不加 --powerOn。部署後先用 API 設好 Static IP，再單次開機，避免 firstboot 被打斷。
  $ova
  $target
)
Write-Host "==> Deploying VCF Operations (vcf-ops01, .150) ..." -ForegroundColor Cyan
& $ovf @args
Write-Host "ExitCode=$LASTEXITCODE"
