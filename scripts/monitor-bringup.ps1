# monitor-bringup.ps1 — 監控 (並在 CEIP 這類非關鍵步驟失敗時自動 PATCH retry) 直到完成
param(
    [string]$Id   = 'f668f2b1-1b24-4995-944a-2f177aa4f641',
    [string]$CB   = '192.168.110.140',
    [string]$Pass = '<CLOUDBUILDER_PASSWORD>',
    [int]$Poll    = 60,
    [int]$MaxCeipRetry = 3
)
$log = "monitor-bringup.log"
function Log([string]$m){ $t=Get-Date -Format 'HH:mm:ss'; Write-Host "[$t] $m"; "[$t] $m"|Out-File -Append -LiteralPath $log }

if(-not ("TrustAllCertsPolicy" -as [type])){Add-Type "using System.Net;using System.Security.Cryptography.X509Certificates;public class TrustAllCertsPolicy:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}"}
[Net.ServicePointManager]::CertificatePolicy=New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$b64=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:$Pass"))
$h=@{Authorization="Basic $b64";'Content-Type'='application/json';Accept='application/json'}
$body=Get-Content -Raw "vcf-config.json"
$url="https://$CB/v1/sddcs/$Id"
$retries=0

Log "=== 監控開始 (id=$Id) ==="
while($true){
    Start-Sleep $Poll
    try{ $s=Invoke-RestMethod -Uri $url -Headers $h -TimeoutSec 20 }catch{ Log "輪詢失敗，繼續 ..."; continue }
    $st=$s.sddcSubTasks
    $done=($st|Where-Object{$_.status -like '*SUCCESS*'}).Count
    $cur=($st|Where-Object{$_.status -eq 'IN_PROGRESS'}|Select-Object -First 1).name
    Log "$($s.status)  $done/$($st.Count)  >> $cur"

    if($s.status -in 'COMPLETED_WITH_SUCCESS','SUCCESS'){ Log "=== BRINGUP 成功完成！ ($done/$($st.Count)) ==="; break }

    if($s.status -in 'COMPLETED_WITH_FAILURE','FAILED'){
        $f=$st|Where-Object{$_.status -like '*FAIL*'}|Select-Object -First 1
        Log "失敗 task：$($f.name)"
        if($f.name -like '*CEIP*' -and $retries -lt $MaxCeipRetry){
            $retries++
            Log "CEIP 為非關鍵步驟 → PATCH 自動 retry #$retries ..."
            try{ Invoke-RestMethod -Uri $url -Method PATCH -Headers $h -Body $body -TimeoutSec 60 | Out-Null; Start-Sleep 15 }
            catch{ Log "PATCH retry 失敗：$($_.Exception.Message)"; break }
            continue
        } else {
            Log "=== 需人工介入：非 CEIP 失敗或已達 retry 上限 ==="; break
        }
    }
}
