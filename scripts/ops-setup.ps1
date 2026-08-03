# ops-setup.ps1 — VCF Operations 9.1 單節點 express 初始化（CaSA API）
# 參考：William Lam configure_vcf_operations.ps1
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

$ip       = '192.168.110.150'
$adminPw  = '<NSX_SDDC_OPS_PASSWORD>'      # >=15 字元
$ntp      = @('192.168.110.1')
$base     = "https://$ip"
$headers  = @{ 'Content-Type'='application/json'; 'Accept'='application/json' }

Write-Host "==> [1/3] 取 node thumbprint ..." -ForegroundColor Cyan
$thumb = (Invoke-WebRequest -Uri "$base/casa/node/thumbprint" -Headers $headers -Method GET -UseBasicParsing).Content
$thumb = $thumb.Trim('"')
Write-Host "    thumbprint = $thumb"

Write-Host "==> [2/3] POST /casa/cluster（建單節點、init=true）..." -ForegroundColor Cyan
$body = @{
  master = @{ name='master'; address=$ip; thumbprint=$thumb }
  admin_password = $adminPw
  ntp_servers = $ntp
  init = $true
  'dry-run' = $false
} | ConvertTo-Json -Depth 6
try {
  $r = Invoke-WebRequest -Uri "$base/casa/cluster" -Headers $headers -Method POST -Body $body -UseBasicParsing
  Write-Host "    POST status: $($r.StatusCode)"
} catch {
  Write-Host "    POST 回應: $($_.Exception.Message)" -ForegroundColor Yellow
  if($_.Exception.Response){ $sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host $sr.ReadToEnd() }
}

Write-Host "==> [3/3] 輪詢 cluster status 直到 INITIALIZED（最多 25 分）..." -ForegroundColor Cyan
$auth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:$adminPw"))
$h2 = @{ 'Accept'='application/json'; 'Authorization'=$auth }
$deadline = (Get-Date).AddMinutes(25)
$state = ''
while((Get-Date) -lt $deadline){
  try {
    $s = Invoke-RestMethod -Uri "$base/casa/cluster/status" -Headers $h2 -Method GET -TimeoutSec 15
    $state = $s.cluster_state
    Write-Host ("    {0}  cluster_state={1}" -f (Get-Date -Format HH:mm:ss), $state)
    if($state -eq 'INITIALIZED'){ break }
  } catch { Write-Host "    (status 尚未就緒: $($_.Exception.Message))" }
  Start-Sleep -Seconds 20
}
Write-Host "FINAL cluster_state = $state" -ForegroundColor $(if($state -eq 'INITIALIZED'){'Green'}else{'Yellow'})
