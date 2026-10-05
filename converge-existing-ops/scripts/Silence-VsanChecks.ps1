# nested lab:把 HCL / controller 這類一定不會綠的 vSAN health check 靜音,
# 否則 vLCM remediate 會直接 FAILED("Health Check for '<cluster>' failed")。
#   $env:VCPASS='...'; ./Silence-VsanChecks.ps1
$ErrorActionPreference = 'Stop'
# PowerShell 7 沒有 ICertificatePolicy,改用 Invoke-WebRequest -SkipCertificateCheck

$vc      = '10.0.1.60'
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
Write-Host "logged in to $vc"

$checks = @(
    # 用 Get-VsanHealth.ps1 查出來、這座 nested lab 真正非綠色的三項。
    # 注意:靜音 API 吃的是「短 id」,不是 health summary 裡的
    #       com.vmware.vsan.health.test.<id> 全名;給不存在的 id 會整批 500。
    'nvmeonhcl',                 # yellow - NVMe device is VMware certified(nested 一定不在 HCL)
    'perfsvcstatus',             # yellow - Performance service status
    'vsanenablesupportinsight'   # info   - vSAN Support Insight(air-gap 連不出去)
)
$adds = ($checks | ForEach-Object { "<addSilentChecks>$_</addSilentChecks>" }) -join ''
$req = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<VsanHealthSetVsanClusterSilentChecks xmlns="urn:vsan">
<_this type="VsanVcClusterHealthSystem">vsan-cluster-health-system</_this>
<cluster type="ClusterComputeResource">$cluster</cluster>
$adds
</VsanHealthSetVsanClusterSilentChecks>
</soapenv:Body></soapenv:Envelope>
"@
$vhdr = @{ 'Content-Type' = 'text/xml; charset=utf-8'; 'SOAPAction' = 'urn:vsan/8.0.2.0' }
try {
    $r = Invoke-WebRequest -Uri "https://$vc/vsanHealth" -Method Post -Body $req -Headers $vhdr -WebSession $sess -UseBasicParsing -SkipCertificateCheck
    Write-Host "SILENCE OK ($($checks.Count) checks)"
} catch {
    Write-Host "SILENCE ERR: $($_.Exception.Message)"
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message }
    throw
}
