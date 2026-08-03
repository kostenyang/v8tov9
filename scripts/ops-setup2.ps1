# ops-setup2.ps1 — VCF Operations 9.1 單節點 express 初始化（用 curl.exe，PS5.1 TLS 太舊）
$ip='192.168.110.150'; $base="https://$ip"; $adminPw='<NSX_SDDC_OPS_PASSWORD>'
$curl='curl.exe'

Write-Host "==> [1/4] 等 CaSA 就緒（thumbprint 不再回 503）..." -ForegroundColor Cyan
$thumb=$null; $deadline=(Get-Date).AddMinutes(30)
while((Get-Date) -lt $deadline){
  $out = & $curl -sk --max-time 15 "$base/casa/node/thumbprint" -w "`n__HTTP__%{http_code}"
  $code = ($out | Select-String '__HTTP__(\d+)').Matches.Groups[1].Value
  $bodyRaw = ($out -replace '__HTTP__\d+\s*$','').Trim()
  if($code -eq '200' -and $bodyRaw -and $bodyRaw -notmatch '503|not available|<html'){
    $thumb = $bodyRaw.Trim('"')
    Write-Host "    CaSA ready. thumbprint=$thumb"
    break
  }
  Write-Host ("    {0} 尚未就緒 (HTTP {1})" -f (Get-Date -Format HH:mm:ss),$code)
  Start-Sleep -Seconds 30
}
if(-not $thumb){ Write-Host "TIMEOUT 等 CaSA 就緒失敗" -ForegroundColor Red; exit 1 }

Write-Host "==> [2/4] POST /casa/cluster（單節點 init）..." -ForegroundColor Cyan
$body = @{
  master=@{name='master';address=$ip;thumbprint=$thumb}
  admin_password=$adminPw
  ntp_servers=@('192.168.110.1')
  init=$true
  'dry-run'=$false
} | ConvertTo-Json -Depth 6
$bodyFile="$env:TEMP\casa-cluster.json"; [IO.File]::WriteAllText($bodyFile,$body,(New-Object Text.UTF8Encoding($false)))
$post = & $curl -sk --max-time 60 -X POST "$base/casa/cluster" -H "Content-Type: application/json" -H "Accept: application/json" -d "@$bodyFile" -w "`n__HTTP__%{http_code}"
Write-Host "    回應: $post"

Write-Host "==> [3/4] 輪詢 cluster status 直到 INITIALIZED（最多 30 分）..." -ForegroundColor Cyan
$deadline=(Get-Date).AddMinutes(30); $state=''
while((Get-Date) -lt $deadline){
  $st = & $curl -sk --max-time 15 -u "admin:$adminPw" "$base/casa/cluster/status"
  if($st -match '"cluster_state"\s*:\s*"([^"]+)"'){ $state=$Matches[1] }
  Write-Host ("    {0} cluster_state={1}" -f (Get-Date -Format HH:mm:ss),$state)
  if($state -eq 'INITIALIZED'){ break }
  Start-Sleep -Seconds 20
}
Write-Host "==> [4/4] FINAL cluster_state=$state"
if($state -eq 'INITIALIZED'){ Write-Host "OPS 初始化完成 (INITIALIZED)" -ForegroundColor Green } else { Write-Host "尚未 INITIALIZED，最後狀態=$state" -ForegroundColor Yellow }
