# cdp.ps1 — 自啟 headless Chrome + DevTools Protocol 操作 Ops UI（--ignore-certificate-errors 繞憑證）
param(
  [string]$Url = 'https://192.168.110.150/ui/login',
  [string]$Shot = 'C:\Users\mjalan\Documents\vspher8to9\shots\ops-dashboard.png',
  [switch]$DoLogin,
  [string]$NavAfter = '',
  [string]$EvalFile = ''
)
$ErrorActionPreference='Stop'
$chrome="C:\Program Files\Google\Chrome\Application\chrome.exe"
$prof="$env:TEMP\cdp-prof"; $port=9222
$argline="--headless=new --disable-gpu --no-sandbox --ignore-certificate-errors --hide-scrollbars --window-size=1600,900 --remote-debugging-port=$port --user-data-dir=`"$prof`" about:blank"
$p = Start-Process -FilePath $chrome -ArgumentList $argline -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3

function Get-WsUrl {
  for($i=0;$i -lt 10;$i++){
    try { $j = Invoke-RestMethod "http://127.0.0.1:$port/json" -TimeoutSec 5; $pg = $j | Where-Object { $_.type -eq 'page' } | Select-Object -First 1; if($pg){ return $pg.webSocketDebuggerUrl } } catch {}
    Start-Sleep -Seconds 1
  }
  throw "no ws url"
}
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri](Get-WsUrl),[Threading.CancellationToken]::None).Wait()
$script:cmdId = 0
function Send-Cdp($method,$params){
  $script:cmdId++; $id=$script:cmdId
  $msg = @{ id=$id; method=$method }
  if($params){ $msg.params=$params }
  $json = $msg | ConvertTo-Json -Depth 10 -Compress
  $buf = [Text.Encoding]::UTF8.GetBytes($json)
  $ws.SendAsync([ArraySegment[byte]]::new($buf),'Text',$true,[Threading.CancellationToken]::None).Wait()
  while($true){
    $sb=New-Object Text.StringBuilder
    do {
      $seg=[ArraySegment[byte]]::new((New-Object byte[] 131072))
      $r=$ws.ReceiveAsync($seg,[Threading.CancellationToken]::None); $r.Wait()
      [void]$sb.Append([Text.Encoding]::UTF8.GetString($seg.Array,0,$r.Result.Count))
    } while(-not $r.Result.EndOfMessage)
    $obj=$sb.ToString()|ConvertFrom-Json
    if($obj.id -eq $id){ return $obj }
  }
}
function Eval($expr){ (Send-Cdp 'Runtime.evaluate' @{ expression=$expr; returnByValue=$true; awaitPromise=$true }).result.result.value }
function WaitLoad{ for($i=0;$i -lt 30;$i++){ if((Eval 'document.readyState') -eq 'complete'){ break }; Start-Sleep -Seconds 1 } }

Send-Cdp 'Page.enable' $null | Out-Null
Send-Cdp 'Runtime.enable' $null | Out-Null
Send-Cdp 'Page.navigate' @{ url=$Url } | Out-Null
WaitLoad; Start-Sleep -Seconds 4

if($DoLogin){
  "fill: " + (Eval ([IO.File]::ReadAllText('C:\Users\mjalan\Documents\vspher8to9\js\login-fill.js')))
  Start-Sleep -Seconds 1
  "click: " + (Eval ([IO.File]::ReadAllText('C:\Users\mjalan\Documents\vspher8to9\js\login-click.js')))
  Start-Sleep -Seconds 10; WaitLoad; Start-Sleep -Seconds 6
  "URL after login: " + (Eval 'location.href')
  "waiting 70s for dashboard SPA to render..."
  Start-Sleep -Seconds 70
}
if($NavAfter){ Send-Cdp 'Page.navigate' @{ url=$NavAfter } | Out-Null; WaitLoad; Start-Sleep -Seconds 6; "URL: " + (Eval 'location.href') }
if($EvalFile){ "EVAL: " + (Eval ([IO.File]::ReadAllText($EvalFile))) }

$cap = Send-Cdp 'Page.captureScreenshot' @{ format='png' }
[IO.File]::WriteAllBytes($Shot,[Convert]::FromBase64String($cap.result.data))
"SAVED $Shot ($((Get-Item $Shot).Length) bytes)"
$ws.Dispose()
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
