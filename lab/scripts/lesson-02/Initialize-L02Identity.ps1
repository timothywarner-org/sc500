<#
.SYNOPSIS
Creates isolated Contoso application and consent fixtures for SC-500 Lesson 2.
.DESCRIPTION
Uses the existing Azure CLI Graph sign-in. Grants only this lesson's custom API permissions.
The temporary account password is protected with Windows DPAPI outside the synced folder.
Re-running preserves existing account credentials and never changes tenant consent defaults.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$courseRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$tenant = '<your-tenant-id>'
$cli = 'C:/Program Files/Microsoft SDKs/Azure/CLI2/python.exe'
$context = & $cli -Im azure.cli account show -o json | ConvertFrom-Json
# Read the pinned subscription from the lesson config so a subscription move is a one-line config change.
$l02Config = Get-Content -Raw -LiteralPath (Join-Path $courseRoot 'infra/lesson-02/config.json') | ConvertFrom-Json
if ($context.tenantId -ne $tenant -or $context.id -ne $l02Config.subscriptionId) { throw 'Select the SC-500 lab tenant and subscription before continuing.' }
$token = & $cli -Im azure.cli account get-access-token --tenant $tenant --resource https://graph.microsoft.com --query accessToken -o tsv
if ($LASTEXITCODE) { throw 'Graph sign-in is required.' }
$headers = @{ Authorization = "Bearer $token" }
function Invoke-L02Graph {
    param([string]$Path, [string]$Method = 'GET', $Body)
    $request = @{ Uri = "https://graph.microsoft.com/v1.0$Path"; Headers = $headers; Method = $Method }
    if ($null -ne $Body) { $request.Body = $Body | ConvertTo-Json -Depth 30; $request.ContentType = 'application/json' }
    Invoke-RestMethod @request
}
function Find-L02Object {
    param([string]$Collection, [string]$Property, [string]$Value)
    $filter = [Uri]::EscapeDataString("$Property eq '$($Value.Replace("'","''"))'")
    $items = @( (Invoke-L02Graph "/${Collection}?`$filter=$filter").value )
    if ($items.Count -gt 1) { throw "Ambiguous $Collection match for $Value. Resolve before writing." }
    if ($items.Count) { $items[0] }
}
$upn = 'sc500.garth@<your-domain>'
$user = Find-L02Object users userPrincipalName $upn
if (-not $user) {
    $secret = 'L02!' + [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)) + 'a7'
    $privateDir = Join-Path $env:LOCALAPPDATA 'SC500/Lesson02'
    New-Item -ItemType Directory -Force $privateDir | Out-Null
    $credential = [pscredential]::new($upn, (ConvertTo-SecureString $secret -AsPlainText -Force))
    $credential | Export-Clixml (Join-Path $privateDir 'garth.credential.xml')
    $user = Invoke-L02Graph '/users' POST @{ accountEnabled=$true; displayName='SC-500 L02 Garth Fort'; givenName='Garth'; surname='Fort'; mailNickname='sc500.garth'; userPrincipalName=$upn; usageLocation='US'; passwordProfile=@{password=$secret; forceChangePasswordNextSignIn=$true} }
    $secret = $null
}
$scopeId = 'e380a75e-9b39-42f3-9d2e-71c5c85735e5'
$roleId = '393c7e17-76b1-447d-a58b-e90c0b1cdbe4'
$api = Find-L02Object applications displayName 'SC500-L02-Contoso-ServiceHub-API'
if (-not $api) {
    $api = Invoke-L02Graph '/applications' POST @{
        displayName='SC500-L02-Contoso-ServiceHub-API'; signInAudience='AzureADMyOrg'
        api=@{requestedAccessTokenVersion=2; oauth2PermissionScopes=@(@{ id=$scopeId; value='Maintenance.Read'; type='Admin'; isEnabled=$true; adminConsentDisplayName='Read fictional maintenance items'; adminConsentDescription='Read only the isolated SC-500 Lesson 2 sample API.' })}
        appRoles=@(@{ id=$roleId; value='Maintenance.Read.All'; displayName='Read fictional maintenance items as an application'; description='Application access to the isolated SC-500 Lesson 2 sample API.'; allowedMemberTypes=@('Application'); isEnabled=$true })
    }
    Invoke-L02Graph "/applications/$($api.id)" PATCH @{identifierUris=@("api://$($api.appId)")} | Out-Null
}
$apiSp = Find-L02Object servicePrincipals appId $api.appId
if (-not $apiSp) { $apiSp=Invoke-L02Graph '/servicePrincipals' POST @{appId=$api.appId} }
$client = Find-L02Object applications displayName 'SC500-L02-Contoso-ServiceHub-Client'
if (-not $client) {
    $client=Invoke-L02Graph '/applications' POST @{
        displayName='SC500-L02-Contoso-ServiceHub-Client'; signInAudience='AzureADMyOrg'
        publicClient=@{redirectUris=@('http://localhost')}; isFallbackPublicClient=$true
        requiredResourceAccess=@(@{resourceAppId=$api.appId; resourceAccess=@(@{id=$scopeId;type='Scope'},@{id=$roleId;type='Role'})})
    }
}
$clientSp=Find-L02Object servicePrincipals appId $client.appId
if (-not $clientSp) { $clientSp=Invoke-L02Graph '/servicePrincipals' POST @{appId=$client.appId} }
# Object IDs belong in grant records; application/client IDs identify token audiences.
$filter=[Uri]::EscapeDataString("clientId eq '$($clientSp.id)' and principalId eq '$($user.id)'")
$grants=@((Invoke-L02Graph "/oauth2PermissionGrants?`$filter=$filter").value | Where-Object resourceId -eq $apiSp.id)
if ($grants.Count -gt 1) { throw 'Ambiguous lab delegated grants.' }
if (-not $grants.Count) {
    $grant=Invoke-L02Graph '/oauth2PermissionGrants' POST @{clientId=$clientSp.id;resourceId=$apiSp.id;principalId=$user.id;consentType='Principal';scope='Maintenance.Read'}
} else { $grant=$grants[0] }
$assignments=@((Invoke-L02Graph "/servicePrincipals/$($clientSp.id)/appRoleAssignments").value | Where-Object { $_.resourceId -eq $apiSp.id -and $_.appRoleId -eq $roleId })
if (-not $assignments.Count) {
    $assignment=Invoke-L02Graph "/servicePrincipals/$($apiSp.id)/appRoleAssignedTo" POST @{principalId=$clientSp.id;resourceId=$apiSp.id;appRoleId=$roleId}
} else { $assignment=$assignments[0] }
$licensed=Invoke-L02Graph "/users/$($user.id)?`$select=assignedLicenses"
if (-not @($licensed.assignedLicenses).Count) {
    $sku=@((Invoke-L02Graph '/subscribedSkus').value | Where-Object { $_.skuPartNumber -eq 'DEVELOPERPACK_E5' -and $_.prepaidUnits.enabled -gt $_.consumedUnits })
    if ($sku.Count -eq 1) {
        # Retain only Entra plans to avoid provisioning unrelated mailboxes and collaboration services.
        $disabled=@($sku[0].servicePlans | Where-Object servicePlanName -notmatch '^AAD_' | ForEach-Object servicePlanId)
        Invoke-L02Graph "/users/$($user.id)/assignLicense" POST @{addLicenses=@(@{skuId=$sku[0].skuId;disabledPlans=$disabled});removeLicenses=@()} | Out-Null
    } else { Write-Warning 'No available existing E5 seat. Assign an existing Entra P1/P2 license before the user CA demo.' }
}
$state=[ordered]@{capturedAt=[DateTime]::UtcNow.ToString('o');tenantId=$tenant;userId=$user.id;userPrincipalName=$upn;apiApplicationId=$api.id;apiClientId=$api.appId;apiServicePrincipalId=$apiSp.id;clientApplicationId=$client.id;clientId=$client.appId;clientServicePrincipalId=$clientSp.id;scopeId=$scopeId;appRoleId=$roleId;delegatedGrantId=$grant.id;applicationGrantId=$assignment.id;scope='Maintenance.Read';role='Maintenance.Read.All';credentialLocation='%LOCALAPPDATA%/SC500/Lesson02/garth.credential.xml'}
$state | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $courseRoot '.azure/lesson-02/identity-state.json')
[pscustomobject]$state | Select-Object userPrincipalName,clientId,apiClientId,scope,role | Format-List
Write-Output 'Isolated Lesson 2 application registrations, service principals, and grants are staged. No application credential was created.'

