# m03 converge 目標端 + 既有 Operations/License Server 的 DNS 正反解
$ErrorActionPreference='Stop'
Import-Module DnsServer
$Zone='home.lab'; $Rev='1.0.10.in-addr.arpa'
$recs=@(
  @{Name='vcf-m03-esx01';    IP='10.0.1.56'},
  @{Name='vcf-m03-esx02';    IP='10.0.1.57'},
  @{Name='vcf-m03-esx03';    IP='10.0.1.58'},
  @{Name='vcf-m03-esx04';    IP='10.0.1.59'},
  @{Name='vcf-m03-vc01';     IP='10.0.1.60'},
  @{Name='vcf-m03-ops01';    IP='10.0.1.61'},   # 既有的 VCF Operations
  @{Name='vcf-m03-lic01';    IP='10.0.1.62'},   # License Server
  @{Name='vcf-m03-nsx01';    IP='10.0.1.63'},   # NSX VIP
  @{Name='vcf-m03-nsx01a';   IP='10.0.1.64'},
  @{Name='vcf-m03-sddcm01';  IP='10.0.1.65'},
  @{Name='vcf-m03-opsc01';   IP='10.0.1.66'},   # cloud proxy
  @{Name='vcf-m03-fleet01';  IP='10.0.1.67'},
  @{Name='vcf-m03-vsp-inst'; IP='10.0.1.68'},
  @{Name='vcf-m03-vsp01';    IP='10.0.1.69'},
  @{Name='vcf-m03-vidb';     IP='10.0.1.70'}
)
foreach($r in $recs){
  $last=$r.IP.Split('.')[-1]
  $ex = Get-DnsServerResourceRecord -ZoneName $Zone -Name $r.Name -RRType A -ErrorAction SilentlyContinue
  if($ex){
    $cur = $ex.RecordData.IPv4Address.IPAddressToString
    if($cur -ne $r.IP){
      Remove-DnsServerResourceRecord -ZoneName $Zone -Name $r.Name -RRType A -Force
      Add-DnsServerResourceRecordA -ZoneName $Zone -Name $r.Name -IPv4Address $r.IP
      Write-Output ("  [A]   {0,-18} {1} -> {2} UPDATED" -f $r.Name,$cur,$r.IP)
    } else { Write-Output ("  [A]   {0,-18} {1} OK" -f $r.Name,$cur) }
  } else {
    Add-DnsServerResourceRecordA -ZoneName $Zone -Name $r.Name -IPv4Address $r.IP
    Write-Output ("  [A]   {0,-18} -> {1} ADDED" -f $r.Name,$r.IP)
  }
  $pex = Get-DnsServerResourceRecord -ZoneName $Rev -Name $last -RRType Ptr -ErrorAction SilentlyContinue
  if($pex){ Remove-DnsServerResourceRecord -ZoneName $Rev -Name $last -RRType Ptr -Force }
  Add-DnsServerResourceRecordPtr -ZoneName $Rev -Name $last -PtrDomainName "$($r.Name).$Zone"
  Write-Output ("  [PTR] {0,-18} {1}.{2}" -f ($r.Name+'.'+$Zone),$last,$Rev)
}
