<#
    ServiceHub parts API, the back end behind API Management in SC-500 Lesson 9.

    authLevel is anonymous on purpose: App Service Authentication (Easy Auth) sits in front of
    this code and rejects any request without a valid Microsoft Entra token for the ServiceHub
    API (401), or with one from a client other than API Management's managed identity (403).
    Only a request that passed both checks reaches this script, so the script can read the
    caller's identity from the headers Easy Auth adds and return it, which is the evidence the
    demo prints.
#>
using namespace System.Net
param($Request, $TriggerMetadata)

$claims = @{}
$principal = $Request.Headers['x-ms-client-principal']
if ($principal) {
    # Easy Auth's claims header: base64-encoded JSON with a claims array of {typ, val}.
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($principal)) | ConvertFrom-Json
    foreach ($c in $json.claims) { $claims[$c.typ] = $c.val }
}

$body = [ordered]@{
    service  = 'servicehub-parts'
    partId   = $Request.Params.partId
    status   = 'in stock'
    # appid is the calling client application; for API Management's call it's the client ID of
    # id-apigateway-prod-eastus2-001, the only client Easy Auth lets through.
    calledBy = $claims['appid']
    audience = $claims['aud']
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Headers    = @{ 'Content-Type' = 'application/json' }
    Body       = ($body | ConvertTo-Json -Compress)
})
