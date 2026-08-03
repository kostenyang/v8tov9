# prep-dns-opslic.ps1 — 在 ADSrv (192.168.110.1) 上執行，為 Ops/License 加 A+PTR
# 用法：登入 ADSrv → 系統管理員 PowerShell → 執行本檔
$Zone = "kosten.lab"
$Records = [ordered]@{
    "vcf-ops01" = "192.168.110.150"   # VCF Operations
    "vcf-lic01" = "192.168.110.151"   # VCF License Server
}
Import-Module DnsServer -ErrorAction Stop
foreach($name in $Records.Keys){
    $ip = $Records[$name]
    try { Remove-DnsServerResourceRecord -ZoneName $Zone -Name $name -RRType A -Force -ErrorAction SilentlyContinue } catch {}
    Add-DnsServerResourceRecordA -ZoneName $Zone -Name $name -IPv4Address $ip -CreatePtr -ErrorAction Stop
    Write-Host "A+PTR: $name.$Zone -> $ip" -ForegroundColor Green
}
Write-Host "`n驗證：" -ForegroundColor Cyan
foreach($name in $Records.Keys){
    $fqdn="$name.$Zone"; $ip=$Records[$name]
    $fwd=(Resolve-DnsName $fqdn -Type A -ErrorAction SilentlyContinue).IPAddress
    $rev=(Resolve-DnsName $ip -Type PTR -ErrorAction SilentlyContinue).NameHost
    Write-Host ("  {0,-22} A={1,-16} PTR={2}" -f $fqdn,$fwd,$rev)
}
