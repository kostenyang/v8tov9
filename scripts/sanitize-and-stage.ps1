# sanitize-and-stage.ps1 - sanitize passwords then stage rebuild deliverables into v8tov9 git repo
$src="C:\Users\mjalan\Documents\vspher8to9"
$dst="$src\v8tov9"
New-Item -ItemType Directory -Force -Path "$dst\scripts","$dst\doc","$dst\shots","$dst\js" | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function ReadUtf8($p){ [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function WriteUtf8($p,$c){ [System.IO.File]::WriteAllText($p, $c, $utf8) }
$map = [ordered]@{
  '<NSX_SDDC_OPS_PASSWORD>'  = '<NSX_SDDC_OPS_PASSWORD>'
  '<CLOUDBUILDER_PASSWORD>'  = '<CLOUDBUILDER_PASSWORD>'
  '<PHYSICAL_VC_PASSWORD>'     = '<PHYSICAL_VC_PASSWORD>'
  '<VC_ESXI_PASSWORD>'       = '<VC_ESXI_PASSWORD>'
}
function Sanitize($c){ foreach($k in $map.Keys){ $c=$c -replace [regex]::Escape($k), $map[$k] }; return $c }

Get-ChildItem "$src\*.ps1" | ForEach-Object {
  WriteUtf8 "$dst\scripts\$($_.Name)" (Sanitize (ReadUtf8 $_.FullName)); Write-Host "staged script: $($_.Name)"
}
Get-ChildItem "$src\*.json" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'vcf-config*' } | ForEach-Object {
  WriteUtf8 "$dst\scripts\$($_.Name)" (Sanitize (ReadUtf8 $_.FullName)); Write-Host "staged json: $($_.Name)"
}
Get-ChildItem "$src\js\*.js" -ErrorAction SilentlyContinue | ForEach-Object {
  WriteUtf8 "$dst\js\$($_.Name)" (Sanitize (ReadUtf8 $_.FullName)); Write-Host "staged js: $($_.Name)"
}
foreach($f in @('rebuild.md','deploy-ops-license.md','plan.md','context.md','tasks.md')){
  if(Test-Path "$src\$f"){ WriteUtf8 "$dst\$f" (Sanitize (ReadUtf8 "$src\$f")); Write-Host "staged md: $f" }
}
foreach($f in @('VCF-5.2.1-to-9.1-Rebuild-Report.docx','VCF-5.2.1-to-9.1-Manual-Upgrade.docx')){
  if(Test-Path "$src\doc\$f"){ Copy-Item "$src\doc\$f" "$dst\doc\" -Force; Write-Host "staged doc: $f" }
}
Get-ChildItem "$src\doc\build_doc*.py" | ForEach-Object { Copy-Item $_.FullName "$dst\doc\" -Force; Write-Host "staged py: $($_.Name)" }
Get-ChildItem "$src\shots\*.png" | Where-Object { $_.Name -match '^p[4-6]-' } | ForEach-Object {
  Copy-Item $_.FullName "$dst\shots\" -Force; Write-Host "staged shot: $($_.Name)"
}
Write-Host "=== leak scan ==="
$leak=0
Get-ChildItem "$dst" -Recurse -Include *.ps1,*.json,*.js,*.md -ErrorAction SilentlyContinue | ForEach-Object {
  $c=ReadUtf8 $_.FullName
  foreach($k in $map.Keys){ if($c -match [regex]::Escape($k)){ Write-Host "  LEAK $k in $($_.Name)"; $leak++ } }
}
Write-Host "leaked passwords: $leak (should be 0)"
