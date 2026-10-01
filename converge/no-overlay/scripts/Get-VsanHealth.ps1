# 列出 vSAN health 裡非綠色的檢查項(testId + status),用來決定要靜音哪些。
#   $env:VCPASS='...'; ./Get-VsanHealth.ps1
$ErrorActionPreference = 'Stop'
$vc      = '10.0.1.19'
$cluster = 'domain-c9'
$u       = 'administrator@vsphere.local'
$p       = if ($env:VCPASS) { $env:VCPASS } else { throw 'set $env:VCPASS' }

$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$hdr  = @{ 'Content-Type' = 'text/xml; charset=utf-8' }
$login = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
$null = Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $hdr -WebSession $sess -UseBasicParsing -SkipCertificateCheck

$req = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<VsanQueryVcClusterHealthSummary xmlns="urn:vsan">
<_this type="VsanVcClusterHealthSystem">vsan-cluster-health-system</_this>
<cluster type="ClusterComputeResource">$cluster</cluster>
<includeObjUuids>false</includeObjUuids>
<fetchFromCache>false</fetchFromCache>
</VsanQueryVcClusterHealthSummary>
</soapenv:Body></soapenv:Envelope>
"@
$vhdr = @{ 'Content-Type' = 'text/xml; charset=utf-8'; 'SOAPAction' = 'urn:vsan/8.0.2.0' }
$r = Invoke-WebRequest -Uri "https://$vc/vsanHealth" -Method Post -Body $req -Headers $vhdr -WebSession $sess -UseBasicParsing -SkipCertificateCheck

[xml]$x = $r.Content
$nodes = $x.SelectNodes('//*[local-name()="groups"]/*[local-name()="groupTests"]')
$out = foreach ($t in $nodes) {
    [pscustomobject]@{
        TestId = $t.testId
        Health = $t.testHealth
        Name   = $t.testName
    }
}
"`n=== 非綠色的檢查 ==="
$out | Where-Object { $_.Health -ne 'green' } | Sort-Object Health, TestId | Format-Table -AutoSize
"`n=== 可直接貼進 Silence 腳本的清單 ==="
"'" + (($out | Where-Object { $_.Health -ne 'green' } | ForEach-Object { $_.TestId }) -join "','") + "'"
"`n(總共 $($out.Count) 項檢查)"
