<#
.SYNOPSIS
    Demo 9.4 for SC-500 Lesson 9: back-end API protection with Azure API Management policies.

.DESCRIPTION
    Read-only except for the requests it sends. The subscription key comes from ARM (listSecrets)
    and the token from the operator's existing Azure CLI sign-in; neither is ever printed.
      Policy     The API's inbound policy as API Management stores it.
      NoKey      Call the gateway with no subscription key (expect 401).
      NoToken    Call with the key but no token (expect 401 from validate-azure-ad-token).
      Call       Call with the key and your token (expect 200). The back end reports which
                 identity called it: API Management's managed identity, not you.
      Burst      Call repeatedly until the rate limit answers 429, and show Retry-After.
                 Wait a minute after this before calling again.
      Backend    Call the function directly with your token (expect 403): only API Management's
                 identity gets through Easy Auth.
      All        Policy, NoKey, NoToken, Call, Backend (Burst is left out so the counter is clean).

.PARAMETER Mode
    One of the modes above.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Invoke-L09ApiDemo.ps1 -Mode Call
#>
[CmdletBinding()]
param([ValidateSet('Policy', 'NoKey', 'NoToken', 'Call', 'Burst', 'Backend', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L09.Common.ps1')
[void](Assert-L09Context)
$cfg = $script:L09Config
$lab = Get-L09Outputs -Lab Retained
$app = Get-L09ApiApp
$apimId = Get-L09ResourceId 'Microsoft.ApiManagement/service' $lab.apim
$uri = "$($lab.apimGateway)/servicehub/parts/PN-1001"

function Get-Key { (Invoke-L09Rest -Method post -Path "$apimId/subscriptions/servicehub-lab/listSecrets?api-version=2024-05-01").primaryKey }
function Get-Caller([string]$Body) {
    # The back end echoes the calling client ID; name it.
    try { $j = $Body | ConvertFrom-Json } catch { return '' }
    $id = Get-L09Value $j 'calledBy'
    if ($id -eq $lab.apimIdentityClientId) { return $cfg.names.apimIdentity }
    return $id
}
$show = @('Retry-After', 'x-ratelimit-remaining', 'WWW-Authenticate')

if ($Mode -in 'Policy', 'All') {
    Write-Host '== Inbound policy on the ServiceHub parts API'
    $p = Invoke-L09Rest -Path "$apimId/apis/servicehub-parts/policies/policy?api-version=2024-05-01&format=rawxml"
    $xml = if ($p -is [string]) { $p } else { $p.properties.value }
    [void](Write-L09Evidence 'api-policy' ([pscustomobject]@{ xml = $xml }))
    $xml | Out-Host
}

if ($Mode -in 'NoKey', 'All') {
    $r = Invoke-L09Http -Uri $uri -ShowHeaders $show -TimeoutSec 60
    '{0} {1} with no subscription key: {2}' -f $r.Status, $r.Reason, $r.Body | Out-Host
    [void](Write-L09Evidence 'api-nokey' ($r | Select-Object Status, Reason, Body, AtUtc))
}

if ($Mode -in 'NoToken', 'All') {
    $r = Invoke-L09Http -Uri $uri -Headers @{ 'Ocp-Apim-Subscription-Key' = (Get-Key) } -ShowHeaders $show -TimeoutSec 60
    '{0} {1} with the key and no token: {2}' -f $r.Status, $r.Reason, $r.Body | Out-Host
    [void](Write-L09Evidence 'api-notoken' ($r | Select-Object Status, Reason, Body, AtUtc))
}

if ($Mode -in 'Call', 'All') {
    $token = Get-L09ApiToken -AppId $app.appId
    $r = Invoke-L09Http -Uri $uri -Headers @{ 'Ocp-Apim-Subscription-Key' = (Get-Key); Authorization = "Bearer $token" } -ShowHeaders $show -TimeoutSec 90
    '{0} {1} with the key and your token: {2}' -f $r.Status, $r.Reason, $r.Body | Out-Host
    "Back end saw the caller as: $(Get-Caller $r.Body)" | Out-Host
    [void](Write-L09Evidence 'api-call' ([ordered]@{ response = ($r | Select-Object Status, Reason, Body, Headers, AtUtc); backendCaller = (Get-Caller $r.Body) }))
}

if ($Mode -eq 'Burst') {
    $token = Get-L09ApiToken -AppId $app.appId
    $key = Get-Key
    $results = [Collections.Generic.List[object]]::new()
    for ($i = 1; $i -le $cfg.apim.rateLimitCalls + 3; $i++) {
        $r = Invoke-L09Http -Uri $uri -Headers @{ 'Ocp-Apim-Subscription-Key' = $key; Authorization = "Bearer $token" } -ShowHeaders $show -TimeoutSec 60
        $results.Add([pscustomobject]@{ Call = $i; Status = $r.Status; Remaining = (Get-L09Value $r.Headers 'x-ratelimit-remaining'); RetryAfter = (Get-L09Value $r.Headers 'Retry-After'); AtUtc = $r.AtUtc })
        if ($r.Status -eq 429) { break }
    }
    [void](Write-L09Evidence 'api-burst' ([pscustomobject]@{ calls = $results }))
    $results | Format-Table -AutoSize | Out-String -Width 120 | Out-Host
}

if ($Mode -in 'Backend', 'All') {
    $token = Get-L09ApiToken -AppId $app.appId
    $r = Invoke-L09Http -Uri "https://$($lab.functionHost)/api/parts/PN-1001" -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 90
    '{0} {1} calling the function directly with your token' -f $r.Status, $r.Reason | Out-Host
    [void](Write-L09Evidence 'api-backend-direct' ($r | Select-Object Status, Reason, Body, AtUtc))
}
