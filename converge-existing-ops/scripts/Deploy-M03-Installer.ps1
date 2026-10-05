# =============================================================================
# m03:部署 VCF Installer appliance(vcf-m03-inst01 / 10.0.1.71)到外層 vCenter
#
#   這台是「lab 基礎設施」,不是被文件化的 VCF 程序的一部分 —— VCF 的程序
#   是從這台的 UI 精靈開始。appliance 本身用 PowerCLI 部,省時且可重現。
#
#   🔴 9.1.1 OVA 的 vami 屬性 key 是 `vami.<屬性>.SDDC-Manager`
#      (9.1.0 的腳本寫 $ovf.vami.SDDC_Manager.ip0 在 9.1.1 會失敗)
#      → 一律用 indexer $ovf['vami.ip0.SDDC-Manager'].Value 指定,不要用屬性路徑。
# =============================================================================
$ErrorActionPreference='Stop'
$PCLI='13.5.1.25718932'
Import-Module VMware.VimAutomation.Sdk  -RequiredVersion $PCLI | Out-Null
Import-Module VMware.VimAutomation.Core -RequiredVersion $PCLI | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false `
    -DefaultVIServerMode Single -Confirm:$false -Scope Session | Out-Null

$VIServer='10.0.0.101'; $VIUser='administrator@vsphere.local'
$VIPass = if ($env:VIPASS) { $env:VIPASS } else { throw 'set $env:VIPASS' }
$Pw     = if ($env:APPPASS) { $env:APPPASS } else { throw 'set $env:APPPASS' }

$OVA='E:\9.1\VCF-SDDC-Manager-Appliance-9.1.1.0.25713928.ova'
$Net='Trunk-Nobinding'          # 與 vcf-m02-inst06-911 相同(已驗證可達 10.0.1.x)
$DS='ForNFS'; $Cluster='Cluster'; $TargetHost='10.0.0.95'; $Folder='VCF'
$name='vcf-m03-inst01'; $fqdn='vcf-m03-inst01.home.lab'; $ip='10.0.1.71'
$mask='255.255.254.0'; $gw='10.0.0.1'; $dns='10.0.0.200'; $domain='home.lab'; $ntp='10.0.1.254'

function Log($m){ "[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m | Tee-Object -Append 'E:\9.1\m03\inst-deploy.log' }

Log "connecting $VIServer"
$c=Connect-VIServer $VIServer -User $VIUser -Password $VIPass -Force -WarningAction SilentlyContinue
if (Get-VM -Name $name -ErrorAction SilentlyContinue) { Log "$name 已存在,中止"; Disconnect-VIServer $c -Confirm:$false; exit 1 }

$ds=Get-Datastore -Name $DS | Select-Object -First 1
$cl=Get-Cluster -Name $Cluster
$vmhost=Get-VMHost -Name $TargetHost
$fld=Get-Folder -Name $Folder -Type VM | Select-Object -First 1
Log "host=$($vmhost.Name) ds=$($ds.Name) net=$Net"

$ovf=Get-OvfConfiguration $OVA
$ovf.NetworkMapping.Network_1.Value = $Net
Log "network mapping Network_1 -> $Net"

# 🔴 ToHashTable() 把 key 攤平成 `vami.ip0.SDDC-Manager`,但「物件路徑」是
#    $ovf.vami.SDDC_Manager.ip0 —— 兩者順序不同,照攤平後的 key 去 index 會失敗
#    (indexer 回傳的物件沒有 .Value)。一律用物件路徑。
$ovf.Common.vami.hostname.Value              = $fqdn
$ovf.vami.SDDC_Manager.ip_address_version.Value = 'IPv4'   # 🔴 大小寫敏感:只接受 'IPv4' 或 'IPv4 and IPv6'
$ovf.vami.SDDC_Manager.ip0.Value             = $ip
$ovf.vami.SDDC_Manager.netmask0.Value        = $mask
$ovf.vami.SDDC_Manager.gateway.Value         = $gw
$ovf.vami.SDDC_Manager.DNS.Value             = $dns
$ovf.vami.SDDC_Manager.domain.Value          = $domain
$ovf.vami.SDDC_Manager.searchpath.Value      = $domain
$ovf.Common.guestinfo.ntp.Value              = $ntp
$ovf.Common.ROOT_PASSWORD.Value              = $Pw
$ovf.Common.LOCAL_USER_PASSWORD.Value        = $Pw

Log "deploying $name ($ip) ..."
$vm=Import-VApp -Source $OVA -OvfConfiguration $ovf -Name $name `
      -Location $cl -VMHost $vmhost -Datastore $ds -InventoryLocation $fld -DiskStorageFormat thin
Log "powering on"
$vm | Start-VM -RunAsync | Out-Null
Log "submitted;appliance 開機約 10-15 分鐘"
Disconnect-VIServer $c -Confirm:$false | Out-Null
