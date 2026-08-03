# finish-bringup.ps1
# 等 NSX Manager 重啟後 MONITORING=STABLE → PATCH retry bringup → 監控到完成
param(
    [string]$Nsx='192.168.110.143', [string]$NsxPass='<NSX_SDDC_OPS_PASSWORD>',
    [string]$CB='192.168.110.140',  [string]$CBPass='<CLOUDBUILDER_PASSWORD>',
    [string]$Id='f668f2b1-1b24-4995-944a-2f177aa4f641',
    [int]$Poll=60, [int]$MaxCeipRetry=4, [int]$NsxWaitMax=1800
)
$log="finish-bringup.log"
function Log([string]$m){$t=Get-Date -Format 'HH:mm:ss';Write-Host "[$t] $m";"[$t] $m"|Out-File -Append -LiteralPath $log}
if(-not ("TrustAllCertsPolicy" -as [type])){Add-Type "using System.Net;using System.Security.Cryptography.X509Certificates;public class TrustAllCertsPolicy:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}"}
[Net.ServicePointManager]::CertificatePolicy=New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$nx=@{Authorization="Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:$NsxPass")))";Accept='application/json';'Content-Type'='application/json'}
$cb=@{Authorization="Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:$CBPass")))";Accept='application/json';'Content-Type'='application/json'}
$body=Get-Content -Raw "vcf-config.json"
$sddcUrl="https://$CB/v1/sddcs/$Id"

Log "=== 等 NSX Manager 重啟並 MONITORING 恢復 STABLE ==="
Start-Sleep 90   # 讓 NSX 真的關機重啟
$mon='';$elapsed=90
while($elapsed -lt $NsxWaitMax){
    try{
        $c=Invoke-RestMethod -Uri "https://$Nsx/api/v1/cluster/status" -Headers $nx -TimeoutSec 8
        $mon=($c.detailed_cluster_status.groups|Where-Object{$_.group_type -eq 'MONITORING'}).group_status
        Log "NSX API up，MONITORING=$mon"
        if($mon -eq 'STABLE'){ break }
    }catch{ Log "NSX 重啟中... ($elapsed s)" }
    Start-Sleep 30; $elapsed+=30
}
# 確保 telemetry 服務啟動 (idempotent)
try{ Invoke-RestMethod -Uri "https://$Nsx/api/v1/node/services/telemetry?action=start" -Method POST -Headers $nx -TimeoutSec 30|Out-Null }catch{}
Start-Sleep 20
Log "MONITORING 最終=$mon，開始 PATCH retry bringup"

$retries=0
Invoke-RestMethod -Uri $sddcUrl -Method PATCH -Headers $cb -Body $body -TimeoutSec 60 | Out-Null
Start-Sleep 15
while($true){
    Start-Sleep $Poll
    try{ $s=Invoke-RestMethod -Uri $sddcUrl -Headers $cb -TimeoutSec 20 }catch{ Log "輪詢失敗，繼續"; continue }
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
            # 每次 CEIP retry 前先確保 telemetry 在跑
            try{ Invoke-RestMethod -Uri "https://$Nsx/api/v1/node/services/telemetry?action=start" -Method POST -Headers $nx -TimeoutSec 30|Out-Null }catch{}
            Log "CEIP 非關鍵 → PATCH retry #$retries"
            try{ Invoke-RestMethod -Uri $sddcUrl -Method PATCH -Headers $cb -Body $body -TimeoutSec 60|Out-Null; Start-Sleep 15 }catch{ Log "PATCH 失敗：$($_.Exception.Message)"; break }
            continue
        } else { Log "=== 需人工介入：$($f.name) ==="; break }
    }
}
