# cdp-wizard.ps1 — 登入 Ops 後逐步走完 setup wizard，每步截圖
$ErrorActionPreference='Stop'
$chrome="C:\Program Files\Google\Chrome\Application\chrome.exe"
$prof="$env:TEMP\cdp-prof2"; $port=9223
$shotsDir="C:\Users\mjalan\Documents\vspher8to9\shots"
$jsDir="C:\Users\mjalan\Documents\vspher8to9\js"
taskkill /F /IM chrome.exe /FI "COMMANDLINE eq *$port*" 2>$null | Out-Null
$argline="--headless=new --disable-gpu --no-sandbox --ignore-certificate-errors --hide-scrollbars --window-size=1600,900 --remote-debugging-port=$port --user-data-dir=`"$prof`" about:blank"
$p=Start-Process -FilePath $chrome -ArgumentList $argline -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
function Get-WsUrl { for($i=0;$i -lt 10;$i++){ try{ $j=Invoke-RestMethod "http://127.0.0.1:$port/json" -TimeoutSec 5; $pg=$j|Where-Object{$_.type -eq 'page'}|Select-Object -First 1; if($pg){return $pg.webSocketDebuggerUrl} }catch{}; Start-Sleep 1 }; throw "no ws" }
$ws=New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri](Get-WsUrl),[Threading.CancellationToken]::None).Wait()
$script:cmdId=0
function Send-Cdp($m,$pr){ $script:cmdId++; $id=$script:cmdId; $o=@{id=$id;method=$m}; if($pr){$o.params=$pr}; $buf=[Text.Encoding]::UTF8.GetBytes(($o|ConvertTo-Json -Depth 10 -Compress)); $ws.SendAsync([ArraySegment[byte]]::new($buf),'Text',$true,[Threading.CancellationToken]::None).Wait(); while($true){ $sb=New-Object Text.StringBuilder; do{ $seg=[ArraySegment[byte]]::new((New-Object byte[] 131072)); $r=$ws.ReceiveAsync($seg,[Threading.CancellationToken]::None); $r.Wait(); [void]$sb.Append([Text.Encoding]::UTF8.GetString($seg.Array,0,$r.Result.Count)) }while(-not $r.Result.EndOfMessage); $obj=$sb.ToString()|ConvertFrom-Json; if($obj.id -eq $id){return $obj} } }
function Eval($e){ (Send-Cdp 'Runtime.evaluate' @{expression=$e;returnByValue=$true;awaitPromise=$true}).result.result.value }
function Shot($name){ $c=Send-Cdp 'Page.captureScreenshot' @{format='png'}; $f=Join-Path $shotsDir $name; [IO.File]::WriteAllBytes($f,[Convert]::FromBase64String($c.result.data)); "  shot $name ($((Get-Item $f).Length)B)" }
function WaitLoad{ for($i=0;$i -lt 30;$i++){ if((Eval 'document.readyState') -eq 'complete'){break}; Start-Sleep 1 } }

Send-Cdp 'Page.enable' $null|Out-Null
Send-Cdp 'Runtime.enable' $null|Out-Null
Send-Cdp 'Page.navigate' @{url='https://192.168.110.150/ui/login'}|Out-Null
WaitLoad; Start-Sleep 4
# login
"fill: " + (Eval ([IO.File]::ReadAllText("$jsDir\login-fill.js")))
Start-Sleep 1
"click: " + (Eval ([IO.File]::ReadAllText("$jsDir\login-click.js")))
Start-Sleep 12; WaitLoad; Start-Sleep 8
"url: " + (Eval 'location.href')

$adv=[IO.File]::ReadAllText("$jsDir\wizard-advance.js")
for($step=1; $step -le 6; $step++){
  Shot ("ops-wiz-$step.png")
  $r = Eval $adv
  "step $step advance => $r"
  Start-Sleep 8; WaitLoad; Start-Sleep 4
  if($r -like 'no-advance-btn*'){ break }
}
Shot ("ops-wiz-final.png")
"final url: " + (Eval 'location.href')
$ws.Dispose()
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
