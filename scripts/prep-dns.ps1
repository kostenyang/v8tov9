# ============================================================================
#  prep-dns.ps1
#  在 ADSrv (192.168.110.1) 上為 VCF 5.2.1 所有元件建立 正解(A) + 反解(PTR) DNS
#
#  VCF bringup 的 pre-check 會硬性驗證每個 FQDN 的正/反解，缺一即失敗。
#
#  執行方式 (擇一)：
#    A) 直接登入 ADSrv 用系統管理員 PowerShell 執行本檔
#    B) 在 AlanPC 遠端執行：本檔已用 -ComputerName $DnsServer，需 RSAT DnsServer 模組
#       Install-WindowsFeature RSAT-DNS-Server   (或 Windows 10/11: 新增選用功能 RSAT DNS)
# ============================================================================

$DnsServer = "192.168.110.1"          # ADSrv
$Zone      = "kosten.lab"              # 必須與 deploy 腳本的 $VMDomain 一致
$RevZone   = "110.168.192.in-addr.arpa" # 192.168.110.0/24 的反解區域

# 所有需要建立的 A 記錄 (短名 → IP)。全部落在 192.168.110.0/24 管理網段。
$Records = [ordered]@{
    "vcf-m01-cb01"    = "192.168.110.140"   # Cloud Builder
    "vcf-m01-sddcm01" = "192.168.110.141"   # SDDC Manager
    "vcf-m01-vc01"    = "192.168.110.142"   # vCenter
    "vcf-m01-nsx01"   = "192.168.110.143"   # NSX Manager VIP
    "vcf-m01-nsx01a"  = "192.168.110.144"   # NSX Manager node1
    "vcf-m01-esx01"   = "192.168.110.145"
    "vcf-m01-esx02"   = "192.168.110.146"
    "vcf-m01-esx03"   = "192.168.110.147"
    "vcf-m01-esx04"   = "192.168.110.148"
}

Import-Module DnsServer -ErrorAction Stop

# 確認正解區域存在 (不存在則建立 AD-integrated primary)
if(-not (Get-DnsServerZone -ComputerName $DnsServer -Name $Zone -ErrorAction SilentlyContinue)) {
    Write-Host "建立正解區域 $Zone ..." -ForegroundColor Cyan
    Add-DnsServerPrimaryZone -ComputerName $DnsServer -Name $Zone -ReplicationScope "Domain" -ErrorAction Stop
}
# 確認反解區域存在
if(-not (Get-DnsServerZone -ComputerName $DnsServer -Name $RevZone -ErrorAction SilentlyContinue)) {
    Write-Host "建立反解區域 $RevZone ..." -ForegroundColor Cyan
    Add-DnsServerPrimaryZone -ComputerName $DnsServer -NetworkId "192.168.110.0/24" -ReplicationScope "Domain" -ErrorAction Stop
}

foreach($name in $Records.Keys) {
    $ip = $Records[$name]
    # 先移除舊記錄避免重複 (忽略不存在)
    try { Remove-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $Zone -Name $name -RRType A -Force -ErrorAction SilentlyContinue } catch {}
    Write-Host "A   : $name.$Zone -> $ip" -ForegroundColor Green
    Add-DnsServerResourceRecordA -ComputerName $DnsServer -ZoneName $Zone -Name $name -IPv4Address $ip -CreatePtr -ErrorAction Stop
}

Write-Host "`n驗證正/反解 ..." -ForegroundColor Cyan
foreach($name in $Records.Keys) {
    $fqdn = "$name.$Zone"; $ip = $Records[$name]
    $fwd = (Resolve-DnsName -Server $DnsServer -Name $fqdn -Type A -ErrorAction SilentlyContinue).IPAddress
    $rev = (Resolve-DnsName -Server $DnsServer -Name $ip   -Type PTR -ErrorAction SilentlyContinue).NameHost
    $okF = if($fwd -eq $ip)   {"OK"} else {"FAIL($fwd)"}
    $okR = if($rev -like "$name*") {"OK"} else {"FAIL($rev)"}
    Write-Host ("  {0,-32} 正解:{1,-12} 反解:{2}" -f $fqdn,$okF,$okR)
}
Write-Host "`n完成。若有 FAIL 請檢查 ADSrv DNS 後再跑 bringup。" -ForegroundColor Yellow
