<#
.SYNOPSIS
    Demo 9.2 for SC-500 Lesson 9: Azure Functions authentication and access, and Logic Apps
    trigger security.

.DESCRIPTION
    Read-only except for the requests it sends. Tokens come from the operator's existing Azure CLI
    sign-in (the lab API pre-authorizes the Azure CLI) and are never printed.
      Function    The function app's settings: HTTPS only, TLS, basic-auth publishing, and App
                  Service Authentication (required, 401 for no token, allowed audiences, and the
                  one allowed client application).
      Direct      Call the function directly: no token (expect 401), then your own valid token
                  for the ServiceHub API from the Azure CLI (expect 403: wrong client application).
      Logic       The logic app's trigger security: SAS state, the Microsoft Entra authorization
                  policy's claims, allowed caller addresses, secure inputs and outputs, and
                  whether the callback URL carries a signature.
      LogicCall   Call the trigger with no token (expect 401), then with your token (expect 200).
      RunHistory  The latest run: the trigger's inputs and outputs are hidden.
      All         Function, Direct, Logic, LogicCall, RunHistory.

.PARAMETER Mode
    One of the modes above.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Invoke-L09ServerlessDemo.ps1 -Mode Direct
#>
[CmdletBinding()]
param([ValidateSet('Function', 'Direct', 'Logic', 'LogicCall', 'RunHistory', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L09.Common.ps1')
[void](Assert-L09Context)
$cfg = $script:L09Config
$n = $cfg.names
$lab = Get-L09Outputs -Lab Retained
$app = Get-L09ApiApp
$funcId = Get-L09ResourceId 'Microsoft.Web/sites' $lab.functionApp
$logicId = Get-L09ResourceId 'Microsoft.Logic/workflows' $n.logicApp

function Get-IdentityName([string]$ClientId) {
    # Turn a client ID back into a name the viewer recognizes.
    if ($ClientId -eq $cfg.azureCliClientId) { return 'Azure CLI' }
    if ($ClientId -eq $lab.apimIdentityClientId) { return $n.apimIdentity }
    return $ClientId
}

if ($Mode -in 'Function', 'All') {
    Write-Host "== $($lab.functionApp)"
    $site = Invoke-L09Rest -Path "$funcId`?api-version=2024-04-01"
    $web = Invoke-L09Rest -Path "$funcId/config/web?api-version=2024-04-01"
    $auth = Invoke-L09Rest -Path "$funcId/config/authsettingsV2?api-version=2024-04-01"
    $ftp = Invoke-L09Rest -Path "$funcId/basicPublishingCredentialsPolicies/ftp?api-version=2024-04-01"
    $scm = Invoke-L09Rest -Path "$funcId/basicPublishingCredentialsPolicies/scm?api-version=2024-04-01"
    $aad = $auth.properties.identityProviders.azureActiveDirectory
    $row = [ordered]@{
        'HTTPS only' = $site.properties.httpsOnly
        'Minimum TLS' = $web.properties.minTlsVersion
        'FTP / SCM basic auth' = '{0} / {1}' -f $(if ($ftp.properties.allow) { 'allowed' } else { 'off' }), $(if ($scm.properties.allow) { 'allowed' } else { 'off' })
        'Authentication' = $(if ($auth.properties.globalValidation.requireAuthentication) { 'required' } else { 'optional' })
        'Unauthenticated requests' = $auth.properties.globalValidation.unauthenticatedClientAction
        'Identity provider' = "Microsoft Entra ID (client ID $($aad.registration.clientId))"
        'Allowed audiences' = (@($aad.validation.allowedAudiences) -join ', ')
        'Allowed client applications' = (@($aad.validation.defaultAuthorizationPolicy.allowedApplications | ForEach-Object { Get-IdentityName $_ }) -join ', ')
        'Public network access' = $(if (Get-L09Value $site 'properties.publicNetworkAccess') { $site.properties.publicNetworkAccess } else { 'Enabled (default)' })
        'Inbound access restrictions' = "$(@(Get-L09Value $web 'properties.ipSecurityRestrictions' | Where-Object { $_ -and $_.name -ne 'Allow all' }).Count) rule(s), default $(Get-L09Value $web 'properties.ipSecurityRestrictionsDefaultAction')"
    }
    [void](Write-L09Evidence 'serverless-function' $row)
    [pscustomobject]$row | Format-List | Out-String -Width 200 | Out-Host
}

if ($Mode -in 'Direct', 'All') {
    $uri = "https://$($lab.functionHost)/api/parts/PN-1001"
    Write-Host "== GET $($lab.functionHost)/api/parts/PN-1001 directly"
    $none = Invoke-L09Http -Uri $uri -TimeoutSec 90
    '{0} {1} with no token' -f $none.Status, $none.Reason | Out-Host
    $token = Get-L09ApiToken -AppId $app.appId
    $claims = Get-L09TokenClaims -Token $token
    $mine = Invoke-L09Http -Uri $uri -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 90
    '{0} {1} with your token (aud {2}, client {3})' -f $mine.Status, $mine.Reason, $claims.aud, (Get-IdentityName $claims.appid) | Out-Host
    [void](Write-L09Evidence 'serverless-direct' ([ordered]@{ noToken = ($none | Select-Object Status, Reason, Body, AtUtc); yourToken = ($mine | Select-Object Status, Reason, Body, AtUtc); tokenAud = $claims.aud; tokenClient = (Get-IdentityName $claims.appid) }))
}

if ($Mode -in 'Logic', 'All') {
    Write-Host "== $($n.logicApp) trigger security"
    $wf = Invoke-L09Rest -Path "$logicId`?api-version=2019-05-01"
    $ac = $wf.properties.accessControl
    $policies = Get-L09Value $ac 'triggers.openAuthenticationPolicies.policies'
    $claimsText = @($policies.PSObject.Properties | ForEach-Object { $_.Value.claims | ForEach-Object { '{0}={1}' -f $_.name, $_.value } }) -join '; '
    $trigger = $wf.properties.definition.triggers.manual
    $cb = Invoke-L09Rest -Method post -Path "$logicId/triggers/manual/listCallbackUrl?api-version=2019-05-01"
    $cbUri = [Uri]$cb.value
    $row = [ordered]@{
        'SAS authentication' = Get-L09Value $ac 'triggers.sasAuthenticationPolicy.state'
        'Entra authorization policy' = $claimsText
        'Allowed caller addresses' = "$(@(Get-L09Value $ac 'triggers.allowedCallerIpAddresses').Count) (your IP)"
        'Run history content from' = "$(@(Get-L09Value $ac 'contents.allowedCallerIpAddresses').Count) address (your IP)"
        'Secure inputs/outputs' = (@(Get-L09Value $trigger 'runtimeConfiguration.secureData.properties') -join ', ')
        'Callback URL has a signature' = [bool]($cbUri.Query -match '(^|[?&])sig=')
    }
    [void](Write-L09Evidence 'serverless-logic' $row)
    [pscustomobject]$row | Format-List | Out-String -Width 200 | Out-Host
}

if ($Mode -in 'LogicCall', 'All') {
    $cb = Invoke-L09Rest -Method post -Path "$logicId/triggers/manual/listCallbackUrl?api-version=2019-05-01"
    $body = '{"partId":"PN-1001"}'
    Write-Host '== POST to the trigger'
    $none = Invoke-L09Http -Uri $cb.value -Method POST -Body $body -TimeoutSec 60
    '{0} {1} with no token: {2}' -f $none.Status, $none.Reason, $none.Body | Out-Host
    $token = Get-L09ApiToken -AppId $app.appId
    $mine = Invoke-L09Http -Uri $cb.value -Method POST -Body $body -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 60
    '{0} {1} with your token: {2}' -f $mine.Status, $mine.Reason, $mine.Body | Out-Host
    [void](Write-L09Evidence 'serverless-logic-call' ([ordered]@{ noToken = ($none | Select-Object Status, Reason, Body, AtUtc); yourToken = ($mine | Select-Object Status, Reason, Body, AtUtc) }))
}

if ($Mode -in 'RunHistory', 'All') {
    Write-Host '== Latest run'
    $runs = Invoke-L09Rest -Path "$logicId/runs?api-version=2019-05-01&`$top=1"
    $run = @($runs.value)[0]
    if (-not $run) { Write-Host '(no runs yet)' }
    else {
        # A secured input or output keeps its size but loses the link to its content.
        function Show-Link($link) {
            if (-not $link) { return 'none' }
            $secured = @(Get-L09Value $link 'secureData.properties')
            $uri = Get-L09Value $link 'uri'
            if ($secured.Count -and -not $uri) { return "secured: $($link.contentSize) bytes, no content link" }
            if ($uri) { return "readable: $($link.contentSize) bytes" }
            return 'none'
        }
        $t = $run.properties.trigger
        $acts = Invoke-L09Rest -Path "$logicId/runs/$($run.name)/actions?api-version=2019-05-01"
        $resp = @($acts.value | Where-Object name -eq 'Respond')[0]
        $row = [ordered]@{
            Run = $run.name; Status = $run.properties.status; 'Started (UTC)' = ([datetime]$run.properties.startTime).ToUniversalTime().ToString('HH:mm:ss')
            'Trigger inputs' = Show-Link (Get-L09Value $t 'inputsLink')
            'Trigger outputs' = Show-Link (Get-L09Value $t 'outputsLink')
            'Respond action inputs' = Show-Link (Get-L09Value $resp 'properties.inputsLink')
        }
        [void](Write-L09Evidence 'serverless-run-history' $row)
        [pscustomobject]$row | Format-List | Out-String -Width 160 | Out-Host
    }
}
