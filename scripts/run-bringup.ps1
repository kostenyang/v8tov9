# ============================================================================
#  run-bringup.ps1  — VCF 5.2.1 Bringup 提交與監控 (Phase 2)
#
#  對 Cloud Builder 5.2.1 API：先 validate → 再 start deploy → 持續監控。
#  Cloud Builder 5.2 用 HTTP Basic Auth (admin/password)，非 9.x 的 token 流程。
#
#  前置：deploy-vcf521-m01.ps1 已跑完、所有 Nested ESXi + Cloud Builder 已開機、
#        prep-dns.ps1 的正/反解都 OK。
#
#  執行： pwsh -File .\run-bringup.ps1
# ============================================================================

param(
    [string]$JsonFile      = "vcf-config.json",
    [string]$CloudBuilderIP = "192.168.110.140",
    [string]$AdminUsername = "admin",
    [string]$AdminPassword = "<CLOUDBUILDER_PASSWORD>",
    [switch]$ValidateOnly,                     # 只驗證不部署 → 加上 -ValidateOnly
    [int]$PollIntervalSec  = 60,
    [int]$CBReadyTimeoutSec = 1800
)

$log = "vcf521-bringup.log"
Function Log { param([string]$m,[string]$c="green")
    $t = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"
    Write-Host -NoNewline -ForegroundColor White "[$t]"; Write-Host -ForegroundColor $c " $m"
    "[$t] $m" | Out-File -Append -LiteralPath $log
}

# 憑證忽略：Core 用 @skip，Windows PowerShell 5.1 用 ServicePointManager
if($PSVersionTable.PSEdition -eq "Core") {
    $skip = @{ SkipCertificateCheck = $true }
} else {
    if(-not ("TrustAllCertsPolicy" -as [type])) {
        Add-Type "using System.Net;using System.Security.Cryptography.X509Certificates;public class TrustAllCertsPolicy:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}"
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $skip = @{}
}
if(-not (Test-Path $JsonFile)) { Log "找不到 $JsonFile，請先跑 deploy-vcf521-m01.ps1" "red"; exit 1 }

$pair    = "$($AdminUsername):$($AdminPassword)"
$b64     = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$Headers = @{ "Authorization"="Basic $b64"; "Content-Type"="application/json"; "Accept"="application/json" }
$Base    = "https://$CloudBuilderIP/v1/sddcs"
$body    = Get-Content -Raw $JsonFile

# ── 等 Cloud Builder API ready ────────────────────────────────────────────────
Log "等待 Cloud Builder API ($CloudBuilderIP) 就緒 ..." "cyan"
$elapsed = 0
while($elapsed -lt $CBReadyTimeoutSec) {
    try {
        $r = Invoke-WebRequest -Uri $Base -Method GET -Headers $Headers @skip -TimeoutSec 5
        if($r.StatusCode -eq 200) { Log "Cloud Builder API 就緒" "cyan"; break }
    } catch {}
    Start-Sleep 30; $elapsed += 30
    Log "  ...尚未就緒，已等 $elapsed 秒"
}
if($elapsed -ge $CBReadyTimeoutSec) { Log "等 Cloud Builder 逾時，請確認 VM 已開機並用瀏覽器開 https://$CloudBuilderIP" "red"; exit 1 }

# ── Step 1：Validation ────────────────────────────────────────────────────────
Log "提交組態驗證 (validation) ..." "cyan"
try {
    $v = Invoke-RestMethod -Uri "$Base/validations" -Method POST -Headers $Headers -Body $body @skip -TimeoutSec 60
    $vid = $v.id
} catch {
    $msg = if($_.ErrorDetails.Message){$_.ErrorDetails.Message}else{$_.Exception.Message}
    Log "驗證提交失敗：$msg" "red"; exit 1
}
Log "Validation id=$vid，輪詢中 ..."
do {
    Start-Sleep $PollIntervalSec
    try {
        $vs = Invoke-RestMethod -Uri "$Base/validations/$vid" -Method GET -Headers $Headers @skip -TimeoutSec 15
        Log "  validation 狀態：$($vs.executionStatus) / $($vs.resultStatus)"
    } catch { Log "  輪詢 validation 失敗 (可能忙線)，繼續 ..." "yellow"; continue }
} while($vs.executionStatus -eq "IN_PROGRESS")

if($vs.resultStatus -notin "SUCCEEDED","SUCCEEDED_WITH_WARNINGS") {
    Log "驗證未通過 (resultStatus=$($vs.resultStatus))。失敗項目：" "red"
    $vs.validationChecks | Where-Object { $_.resultStatus -notin 'SUCCEEDED','WARNING' } |
        ForEach-Object { Log ("  [{0}] {1}" -f $_.resultStatus, $_.description) "red" }
    Log "請修正後重跑。細節見 https://$CloudBuilderIP" "red"
    exit 1
}
$vs.validationChecks | Where-Object { $_.resultStatus -eq 'WARNING' } |
    ForEach-Object { Log ("  [WARNING] {0}" -f $_.description) "yellow" }
Log "驗證通過 (resultStatus=$($vs.resultStatus)) ✔" "cyan"
if($ValidateOnly) { Log "ValidateOnly=true，結束 (未部署)。"; exit 0 }

# ── Step 2：開始部署 (bringup) ────────────────────────────────────────────────
Log "提交 bringup，開始部署管理域 ..." "cyan"
try {
    $d = Invoke-RestMethod -Uri $Base -Method POST -Headers $Headers -Body $body @skip -TimeoutSec 60
    $sddcId = $d.id
} catch {
    $msg = if($_.ErrorDetails.Message){$_.ErrorDetails.Message}else{$_.Exception.Message}
    Log "bringup 提交失敗：$msg" "red"; exit 1
}
Log "Bringup id=$sddcId。預計 ~2-4 小時。進度：https://$CloudBuilderIP" "cyan"

# ── Step 3：監控 ──────────────────────────────────────────────────────────────
$last = ""
while($true) {
    Start-Sleep $PollIntervalSec
    try {
        $s = Invoke-RestMethod -Uri "$Base/$sddcId" -Method GET -Headers $Headers @skip -TimeoutSec 15
        $st = $s.status
        if($st -ne $last) { Log "部署狀態：$st" "yellow"; $last = $st } else { Log "  仍在 $st ..." }
        if($st -in "COMPLETED_WITH_SUCCESS","SUCCESS") { Log "=== VCF 5.2.1 Bringup 成功完成！SDDC Manager: https://vcf-m01-sddcm01.<domain> ===" "cyan"; break }
        if($st -in "COMPLETED_WITH_FAILURE","FAILED")  { Log "=== Bringup 失敗，請看 Cloud Builder UI 的 failed task，可修正後 retry ===" "red"; break }
    } catch { Log "  輪詢失敗 (Cloud Builder 忙線)，繼續 ..." "yellow" }
}
