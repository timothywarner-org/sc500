<#
.SYNOPSIS
    Installs the signed Microsoft private network connector on the bounded Lesson 6 host.
.DESCRIPTION
    Registration is deliberately separate: the installer receives no identity credential.
    The download URL is Microsoft's connector token acquisition sample. Verify the
    Authenticode publisher before running it. No inbound port is added by this script.
.EXAMPLE
    ./Install-L06Connector.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$rg=$script:L06Config.connectorResourceGroup
$vm=$script:L06Names.connectorVm
Assert-L06GuestReady -ResourceGroup $rg -VmName $vm
$guest=@'
$ErrorActionPreference='Stop'
$installer=Join-Path $env:TEMP 'MicrosoftEntraPrivateNetworkConnectorInstaller.exe'
$registration='C:\Program Files\Microsoft Entra private network connector\RegisterConnector.ps1'
if(-not(Test-Path -LiteralPath $registration)) {
    Invoke-WebRequest 'https://download.msappproxy.net/Subscription/d3c8b69d-6bf7-42be-a529-3fe9c2e70c90/Connector/DownloadConnectorInstaller' -OutFile $installer -UseBasicParsing
    $signature=Get-AuthenticodeSignature -FilePath $installer
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {throw 'Installer signature is not valid Microsoft software.'}
    $p=Start-Process -FilePath $installer -ArgumentList 'REGISTERCONNECTOR="false"','/q' -Wait -PassThru -WindowStyle Hidden
    if($p.ExitCode -notin 0,3010){throw "Connector installer exited $($p.ExitCode)"}
}
if(-not(Test-Path -LiteralPath $registration)){throw 'Connector registration script missing after install.'}
Get-Service | Where-Object DisplayName -match 'private network connector' | Select-Object Name,Status,DisplayName | ConvertTo-Json
Write-Output 'Connector software installed; registration requires its own authenticated session.'
'@
$result=Invoke-L06Az @('vm','run-command','invoke','--resource-group',$rg,'--name',$vm,'--command-id','RunPowerShellScript','--scripts',$guest)
[void](Write-L06Evidence 'connector-install' $result)
if (@($result.value | Where-Object { $_.code -match 'StdErr' -and $_.message.Trim() }).Count) {throw 'Connector installation reported an error. See the saved evidence; do not treat Run Command transport success as installation success.'}
$result.value | Select-Object code,message | Format-List
