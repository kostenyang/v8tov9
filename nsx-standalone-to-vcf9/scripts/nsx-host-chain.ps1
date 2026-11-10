# m07 NSX upgrade: after MP SUCCESS -> continue plan (HOST group) -> watch to completion.
# EDGE group has 0 units (no edge) so the plan skips it. Stops before FINALIZE (needs vCenter 9.1 first).
if (-not $env:NSX_PASS) { throw 'set $env:NSX_PASS' }
$c = New-Object PSCredential('admin', (ConvertTo-SecureString $env:NSX_PASS -AsPlainText -Force))
$log = (Join-Path $PSScriptRoot '..\out\host-upgrade.log')
function L($m){ $l = "[{0}] {1}" -f (Get-Date -Format 'MM-dd HH:mm:ss'),$m; $l | Tee-Object -Append $log }
function Cs { (Invoke-RestMethod 'https://<nsx-mgr-ip>/api/v1/upgrade/status-summary' -Credential $c -Authentication Basic -SkipCertificateCheck -TimeoutSec 60).component_status }

# 1. wait MP SUCCESS (manager may restart; tolerate API gaps)
$d=(Get-Date).AddMinutes(75); $mpok=$false
while((Get-Date) -lt $d){
  Start-Sleep 30
  try { $mp = (Cs | ?{$_.component_type -eq 'MP'}) } catch { continue }
  if($mp.status -eq 'SUCCESS'){ $mpok=$true; L 'MP SUCCESS'; break }
  if($mp.status -eq 'FAILED'){ L 'MP FAILED -> stop'; exit 2 }
}
if(-not $mpok){ L 'MP not SUCCESS in time -> stop'; exit 3 }
try { L ("node version: " + (Invoke-RestMethod 'https://<nsx-mgr-ip>/api/v1/node/version' -Credential $c -Authentication Basic -SkipCertificateCheck).product_version) } catch {}

# 2. continue plan -> HOST
Start-Sleep 30
try { Invoke-RestMethod 'https://<nsx-mgr-ip>/api/v1/upgrade/plan?action=continue' -Method POST -Credential $c -Authentication Basic -SkipCertificateCheck -TimeoutSec 60 | Out-Null; L 'plan continue -> HOST' }
catch { L "continue: $($_.ErrorDetails.Message)"; exit 4 }

# 3. watch HOST
$d=(Get-Date).AddMinutes(90); $last=''
while((Get-Date) -lt $d){
  Start-Sleep 45
  try { $h = (Cs | ?{$_.component_type -eq 'HOST'}) } catch { continue }
  $line = "HOST status=$($h.status) pct=$($h.percentage)"
  if($line -ne $last){ L $line; $last=$line }
  if($h.status -in 'SUCCESS','PAUSED','FAILED'){ L "HOST done: $($h.status)"; break }
}
# per-host state
try { $tn = (Invoke-RestMethod 'https://<nsx-mgr-ip>/policy/api/v1/infra/sites/default/enforcement-points/default/host-transport-nodes' -Credential $c -Authentication Basic -SkipCertificateCheck).results
  foreach($t in $tn){ L "  $($t.display_name)" } } catch {}
L 'host chain done'
