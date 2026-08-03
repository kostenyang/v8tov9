$ErrorActionPreference='Stop'
add-type @"
using System.Net;using System.Security.Cryptography.X509Certificates;
public class TAans:ICertificatePolicy{public bool CheckValidationResult(ServicePoint s,X509Certificate c,WebRequest r,int p){return true;}}
"@
[System.Net.ServicePointManager]::CertificatePolicy=New-Object TAans
[System.Net.ServicePointManager]::SecurityProtocol='Tls12'
$vc='192.168.110.142'; $u='administrator@vsphere.local'; $p='<VC_ESXI_PASSWORD>'
# REST for VM list
$pair=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$u`:$p"))
$rsid=Invoke-RestMethod -Method Post -Uri "https://$vc/api/session" -Headers @{Authorization="Basic $pair"}
$RH=@{'vmware-api-session-id'=$rsid}
# SOAP session
$sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$hdr = @{ 'Content-Type'='text/xml; charset=utf-8'; 'SOAPAction'='urn:vim25/8.0.2.0' }
$login = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:Login><urn:_this type="SessionManager">SessionManager</urn:_this><urn:userName>$u</urn:userName><urn:password>$([System.Security.SecurityElement]::Escape($p))</urn:password></urn:Login>
</soapenv:Body></soapenv:Envelope>
"@
$null = Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $login -Headers $hdr -WebSession $sess -UseBasicParsing

function Get-Question($vm){
  $q=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:RetrievePropertiesEx><urn:_this type="PropertyCollector">propertyCollector</urn:_this>
<urn:specSet><urn:propSet><urn:type>VirtualMachine</urn:type><urn:pathSet>runtime.question</urn:pathSet><urn:pathSet>name</urn:pathSet></urn:propSet>
<urn:objectSet><urn:obj type="VirtualMachine">$vm</urn:obj></urn:objectSet></urn:specSet><urn:options/></urn:RetrievePropertiesEx>
</soapenv:Body></soapenv:Envelope>
"@
  $r=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $q -Headers $hdr -WebSession $sess -UseBasicParsing
  return [xml]$r.Content
}
function Answer($vm,$qid,$choice){
  $a=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:vim25"><soapenv:Body>
<urn:AnswerVM><urn:_this type="VirtualMachine">$vm</urn:_this><urn:questionId>$qid</urn:questionId><urn:answerChoice>$choice</urn:answerChoice></urn:AnswerVM>
</soapenv:Body></soapenv:Envelope>
"@
  try{ $null=Invoke-WebRequest -Uri "https://$vc/sdk" -Method Post -Body $a -Headers $hdr -WebSession $sess -UseBasicParsing; return "ANSWERED q=$qid choice=$choice" }
  catch{ $b=''; if($_.Exception.Response){$sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $b=$sr.ReadToEnd()}; return "ANSWER ERR: $b" }
}

for($pass=0; $pass -lt 12; $pass++){
  $vms=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm?clusters=domain-c9" -Headers $RH
  $vcls=$vms | Where-Object { $_.name -like 'vCLS*' }
  $answered=0
  foreach($v in $vcls){
    $x=Get-Question $v.vm
    $qnode=$x.SelectSingleNode("//*[local-name()='question']")
    if($qnode){
      $qid=$qnode.SelectSingleNode("./*[local-name()='id']").InnerText
      $qtext=$qnode.SelectSingleNode("./*[local-name()='text']").InnerText
      # choices
      $choices=$qnode.SelectNodes("./*[local-name()='choice']/*[local-name()='choiceInfo']")
      $pick=$null
      foreach($c in $choices){
        $ck=$c.SelectSingleNode("./*[local-name()='key']").InnerText
        $cl=$c.SelectSingleNode("./*[local-name()='label']").InnerText
        if($cl -match 'Yes' -or $cl -match 'Continue' -or $cl -match 'OK' -or $ck -eq '0'){ if(-not $pick){$pick=$ck} }
      }
      if(-not $pick -and $choices.Count -gt 0){ $pick=$choices[0].SelectSingleNode("./*[local-name()='key']").InnerText }
      Write-Host "[$($v.name)] QUESTION id=$qid pick=$pick :: $($qtext.Substring(0,[math]::Min(70,$qtext.Length)))"
      Write-Host "   -> $(Answer $v.vm $qid $pick)"
      $answered++
    }
  }
  if($answered -eq 0){ Write-Host "pass $pass : no pending questions" }
  # report power states
  $vms2=Invoke-RestMethod -Uri "https://$vc/api/vcenter/vm?clusters=domain-c9" -Headers $RH
  ($vms2 | Where-Object {$_.name -like 'vCLS*'}) | ForEach-Object { Write-Host "     $($_.name) = $($_.power_state)" }
  Start-Sleep 10
}