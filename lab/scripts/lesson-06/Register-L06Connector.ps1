<#
.SYNOPSIS
    Registers the isolated Lesson 6 connector using a protected, short-lived token.
.DESCRIPTION
    Run Connect-L06ConnectorRegistration.ps1 first. The token stays in memory and in
    Azure Run Command protected parameters, never in command-line arguments or evidence.
    The registration result is checked separately from ARM provisioning success.
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$rg=$script:L06Config.connectorResourceGroup
$vm=$script:L06Names.connectorVm
Assert-L06GuestReady -ResourceGroup $rg -VmName $vm
$folder=Join-Path $env:LOCALAPPDATA 'SC500/Lesson06'
$tokenPath=Join-Path $folder 'connector-registration.token.xml'
$expiryPath=Join-Path $folder 'connector-registration-expiry.json'
$expiry=Get-Content -LiteralPath $expiryPath -Raw|ConvertFrom-Json
if([DateTime]::Parse($expiry.ExpiresUtc).ToUniversalTime() -lt [DateTime]::UtcNow.AddMinutes(5)){throw 'Registration token expired or too close to expiry. Sign in again.'}
$secure=Import-Clixml -LiteralPath $tokenPath
$credential=[PSCredential]::new('registration',$secure)
$token=$credential.GetNetworkCredential().Password
$guest=@'
param([string]$RegistrationToken)
$ErrorActionPreference='Stop'
try {
    if([string]::IsNullOrWhiteSpace($RegistrationToken)){throw 'Protected registration parameter was empty.'}
    $registration='C:\Program Files\Microsoft Entra private network connector\RegisterConnector.ps1'
    # The installed 2026 script declares Token as String; older Learn examples use SecureString.
    # Inspect the installed contract so conversion cannot silently send 'System.Security.SecureString'.
    $type=(Get-Command $registration).Parameters['Token'].ParameterType
    $registrationValue=if($type -eq [securestring]){$RegistrationToken|ConvertTo-SecureString -AsPlainText -Force}elseif($type -eq [string]){$RegistrationToken}else{throw 'Unsupported connector token parameter type.'}
    & $registration -modulePath 'C:\Program Files\Microsoft Entra private network connector\Modules\' -moduleName MicrosoftEntraPrivateNetworkConnectorPSModule -Authenticationmode Token -Token $registrationValue -TenantId '<your-tenant-id>' -Feature ApplicationProxy
    $registrationValue=$null;$RegistrationToken=$null
    $svc=Get-Service WAPCSvc
    if($svc.Status -ne 'Running'){throw 'Connector service did not start.'}
    Write-Output 'L06_CONNECTOR_REGISTERED'
    Get-Service WAPCSvc,WAPCUpdaterSvc|Select-Object Name,Status|ConvertTo-Json
} catch {
    # Registration libraries can include sensitive context in exceptions. Keep output bounded.
    $message=$_.Exception.Message -replace 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+','[TOKEN REDACTED]'
    if($RegistrationToken){$message=$message.Replace($RegistrationToken,'[TOKEN REDACTED]')}
    Write-Error ('Connector registration failed: '+$message)
    exit 1
}
'@
$resource="/subscriptions/$($script:L06Config.subscriptionId)/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$vm/runCommands/l06-register-connector"
$uri="https://management.azure.com${resource}?api-version=2025-04-01"
$arm=Invoke-L06Az @('account','get-access-token','--resource','https://management.azure.com/')
$headers=@{Authorization="Bearer $($arm.accessToken)"}
$body=@{location=$script:L06Config.location;properties=@{source=@{script=$guest};protectedParameters=@(@{name='RegistrationToken';value=$token});timeoutInSeconds=600;treatFailureAsDeploymentFailure=$true;asyncExecution=$false}}|ConvertTo-Json -Depth 8
try {
    # The HTTPS request avoids exposing the token to process listings or a temporary JSON file.
    try {$null=Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -Body $body -ContentType 'application/json'}
    catch {throw 'The protected registration request failed. No request body was logged.'}
    $body=$null;$token=$null;$credential=$null;$secure=$null
    $deadline=[DateTime]::UtcNow.AddMinutes(12)
    do {
        Start-Sleep -Seconds 10
        $result=Invoke-RestMethod -Method Get -Uri ($uri+'&$expand=instanceView') -Headers $headers
        $view=$result.properties.instanceView
        $state=Get-L06Value $view 'executionState'
        if($state -in 'Succeeded','Failed','TimedOut','Canceled'){break}
    } while([DateTime]::UtcNow -lt $deadline)
    # Save only result fields; never serialize the submitted protected parameters.
    $evidence=[pscustomobject]@{Utc=[DateTime]::UtcNow.ToString('o');Vm=$vm;State=$state;ExitCode=Get-L06Value $view 'exitCode';Output=Get-L06Value $view 'output';Error=Get-L06Value $view 'error'}
    [void](Write-L06Evidence 'connector-registration' $evidence)
    if($state -ne 'Succeeded' -or $evidence.ExitCode -ne 0 -or $evidence.Output -notmatch 'L06_CONNECTOR_REGISTERED'){throw 'Connector registration has not passed. See the redacted result evidence.'}
    # Remove only the consumed credential at its fixed operator-local path.
    Remove-Item -LiteralPath $tokenPath,$expiryPath
    $null=Invoke-RestMethod -Method Delete -Uri $uri -Headers $headers
    $evidence
} finally {$body=$null;$token=$null;$credential=$null;$secure=$null;$headers=$null;$arm=$null}
