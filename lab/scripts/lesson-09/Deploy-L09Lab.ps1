<#
.SYNOPSIS
    Previews, or deploys, the retained SC-500 Lesson 9 application platform lab.

.DESCRIPTION
    Default run: the read-only preflight (group owners, node size and quota, providers, Defender
    plans, global names, budget API, app registration, same names elsewhere), then the operator's
    public IP and object ID, then ARM validation and what-if, saved as private evidence. Nothing is
    created. docs/CONTOSO-AZURE-DEPLOYMENT.md, steps 2 to 4.

    With -Deploy:
      1. Registers the resource providers the retained part needs if the subscription hasn't
         (Microsoft.ContainerService and Microsoft.Logic were unregistered in the lab subscription on
         November 1, 2026). One time, subscription level, no cost; each one is printed.
      2. Creates or repairs the Microsoft Entra app registration sc500-l09-servicehub-api: an API
         (api://<appId>) with one delegated scope, access_as_user, that pre-authorizes the Azure
         CLI so the operator's existing sign-in can get a token without a consent prompt. No
         secret, no certificate, no API permissions. An Entra object, so it keeps its name.
      3. Deploys rg-appplatform-prod-eastus2 and budget-rg-appplatform-prod-eastus2 (see
         infra/lesson-09/README.md). First pass, before the images exist: the workspace, the three
         identities, the VNet, registry crservicehubprod<your-name-suffix>, the Container Apps environment, the
         Flex Consumption function func-partsapi-prod-<your-name-suffix> with Easy Auth, the Consumption logic app,
         Consumption API Management apim-servicehub-prod-<your-name-suffix>, and the privileged-container Deny
         policy.
      4. Imports the two lab images from mcr.microsoft.com into the registry (no credentials),
         then a second pass adds aks-servicehub-prod-eastus2-001 (one D4s_v3 node, node resource
         group rg-servicehubnodes-prod-eastus2) and the container app ca-status-prod-001.
      5. Publishes the function code with az functionapp deployment source config-zip, which
         authenticates with the operator's Microsoft Entra identity (basic auth is off).
      6. Puts budget-rg-servicehubnodes-prod-eastus2 on the cluster's node resource group, where
         AKS bills the node, its load balancer and its public IP.

    The cluster is left running; Start-L09Lab.ps1 -Stop stops it. Idempotent. It changes nothing
    outside the two resource groups except the provider registrations and the one app
    registration: Defender plans are read, not written (Set-L09DefenderWindow.ps1 owns them).

.PARAMETER Deploy
    Create or update everything after the preview passes.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Deploy-L09Lab.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Deploy-L09Lab.ps1 -Deploy

.NOTES
    Cost: see infra/lesson-09/config.json. Retained baseline is about 0.17 USD a day for the
    registry plus the node group's load balancer and public IP, with AKS stopped.
#>
[CmdletBinding()]
param([switch]$Deploy)
. (Join-Path $PSScriptRoot 'L09.Common.ps1')

[void](Assert-L09Context)
$cfg = $script:L09Config
[void](Test-L09Preflight)

if ($Deploy) { Register-L09Provider -Namespace 'Microsoft.ContainerService', 'Microsoft.Logic', 'Microsoft.App', 'Microsoft.ContainerRegistry', 'Microsoft.Web', 'Microsoft.ApiManagement', 'Microsoft.OperationalInsights', 'Microsoft.ManagedIdentity' }

$operatorIp = Get-L09OperatorIp
$operatorId = Invoke-L09Az -NoSubscription @('ad', 'signed-in-user', 'show', '--query', 'id')

function Set-L09ApiApp {
    # Creates or repairs the lab API registration. Graph replaces the whole api object on PATCH,
    # so the scope and the pre-authorization always go together.
    $app = Get-L09ApiApp
    if (-not $app) {
        $app = Invoke-L09Rest -Method post -Path 'https://graph.microsoft.com/v1.0/applications' -Body @{
            displayName = $cfg.apiAppDisplayName; signInAudience = 'AzureADMyOrg'; tags = @($cfg.managedBy)
            notes = "SC-500 Lesson 9 lab API (managedby=$($cfg.managedBy)). No secrets. Remove-L09Lab.ps1 deletes it."
        }
        Write-Host "Created app registration $($cfg.apiAppDisplayName)."
    }
    $scopes = @(Get-L09Value $app 'api.oauth2PermissionScopes' | Where-Object { $_ -and $_.value -eq $cfg.apiScope })
    $scopeId = if ($scopes.Count) { $scopes[0].id } else { [guid]::NewGuid().ToString() }
    $pre = @(Get-L09Value $app 'api.preAuthorizedApplications' | Where-Object { $_ -and $_.appId -eq $cfg.azureCliClientId })
    $uri = "api://$($app.appId)"
    if (-not $scopes.Count -or -not $pre.Count -or @($app.identifierUris) -notcontains $uri) {
        $scope = @{
            id = $scopeId; value = $cfg.apiScope; type = 'User'; isEnabled = $true
            adminConsentDisplayName = 'Call the ServiceHub lab API'; adminConsentDescription = 'Lets the signed-in user call the SC-500 Lesson 9 ServiceHub lab API.'
            userConsentDisplayName = 'Call the ServiceHub lab API'; userConsentDescription = 'Lets you call the SC-500 Lesson 9 ServiceHub lab API.'
        }
        # Graph validates a pre-authorization against scopes already saved, so the scope goes
        # first and the pre-authorization second (with the scope repeated, since PATCH replaces api).
        Invoke-L09Rest -Method patch -Path "https://graph.microsoft.com/v1.0/applications/$($app.id)" -Body @{ identifierUris = @($uri); api = @{ oauth2PermissionScopes = @($scope) } } | Out-Null
        Invoke-L09Rest -Method patch -Path "https://graph.microsoft.com/v1.0/applications/$($app.id)" -Body @{
            api = @{ oauth2PermissionScopes = @($scope); preAuthorizedApplications = @(@{ appId = $cfg.azureCliClientId; delegatedPermissionIds = @($scopeId) }) }
        } | Out-Null
        Write-Host "Set $uri with the $($cfg.apiScope) scope, pre-authorized for the Azure CLI."
    }
    else { Write-Host "App registration $($cfg.apiAppDisplayName) is already set: $uri, scope $($cfg.apiScope), Azure CLI pre-authorized." }
    $sp = Invoke-L09Rest -Path "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$($app.appId)'&`$select=id"
    if (-not @($sp.value).Count) { Invoke-L09Rest -Method post -Path 'https://graph.microsoft.com/v1.0/servicePrincipals' -Body @{ appId = $app.appId; tags = @($cfg.managedBy) } | Out-Null; Write-Host 'Created its service principal.' }
    return $app.appId
}

$app = Get-L09ApiApp
$apiAppId = if ($Deploy) { Set-L09ApiApp } elseif ($app) { $app.appId } else { '00000000-0000-0000-0000-000000000000' }

function Test-L09Images {
    # True when the registry exists and holds both lab images.
    if (-not (Invoke-L09Az @('group', 'exists', '--name', $cfg.resourceGroup))) { return $false }
    if ((Invoke-L09Az -AllowFailure @('acr', 'show', '--resource-group', $cfg.resourceGroup, '--name', $cfg.names.registry, '--query', 'id')).ExitCode -ne 0) { return $false }
    foreach ($img in $cfg.images.PSObject.Properties.Value) {
        $repo, $tag = $img.target -split ':'
        $t = Invoke-L09Az -AllowFailure @('acr', 'repository', 'show-tags', '--name', $cfg.names.registry, '--repository', $repo)
        if ($t.ExitCode -ne 0 -or (($t.Stdout | ConvertFrom-Json) -notcontains $tag)) { return $false }
    }
    return $true
}

function New-L09Parameters([bool]$DeployApps) {
    $values = [ordered]@{
        location = $cfg.location; aksLocation = $cfg.aksLocation; resourceGroupName = $cfg.resourceGroup
        names = $cfg.names; addressPlan = $cfg.addressPlan; aksNodeSize = $cfg.aksNodeSize
        operatorIp = $operatorIp; operatorObjectId = $operatorId; tenantId = $cfg.tenantId
        apiAppId = $apiAppId; apiScope = $cfg.apiScope; policyDefinitions = $cfg.policyDefinitions
        rateLimitCalls = $cfg.apim.rateLimitCalls; rateLimitPeriodSeconds = $cfg.apim.rateLimitPeriodSeconds
        deployApps = $DeployApps; tags = $cfg.tags; budget = $cfg.budget
    }
    $parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
    [void][IO.Directory]::CreateDirectory($script:L09State)
    $path = Join-Path $script:L09State 'deployment.parameters.json'
    [ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
    return $path
}

function Invoke-L09Preview([string]$ParamsPath) {
    # ARM validation and what-if, saved as evidence. A what-if that deletes anything stops the run.
    $script:base = @('--location', $cfg.location, '--name', $cfg.deploymentName, '--template-file', $template, '--parameters', ('@' + $ParamsPath))
    $validation = Invoke-L09Az (@('deployment', 'sub', 'validate') + $script:base)
    [void](Write-L09Evidence 'arm-validation' ($validation | Select-Object -ExcludeProperty properties))
    $preview = Invoke-L09Az (@('deployment', 'sub', 'what-if') + $script:base + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
    [void](Write-L09Evidence 'what-if' $preview)
    $deletes = @($preview.changes | Where-Object changeType -eq 'Delete')
    if ($deletes.Count) { throw "What-if contains $($deletes.Count) deletion(s): $(@($deletes | ForEach-Object resourceId) -join ', '). Nothing was deployed." }
    $preview.changes | ForEach-Object { '{0,-10} {1}' -f $_.changeType, ($_.resourceId -replace '^/subscriptions/[^/]+', '') } | Out-Host
}

$template = Join-Path $script:L09Lab 'infra/lesson-09/main.bicep'
$imagesReady = Test-L09Images
Invoke-L09Preview (New-L09Parameters $imagesReady)
if (-not $Deploy) {
    $pass = if ($imagesReady) { 'the full lab (images present)' } else { 'the first pass (no registry images yet, so no cluster or container app)' }
    Write-Host "Preview only, of $pass. Re-run with -Deploy to create the Lesson 9 lab."
    return
}

$started = Get-Date
$result = Invoke-L09Az (@('deployment', 'sub', 'create') + $script:base)
if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success.' }
$lab = $result.properties.outputs.lab.value

if (-not $imagesReady) {
    # az acr import copies a public image registry-to-registry: no Docker, no credentials.
    foreach ($img in $cfg.images.PSObject.Properties.Value) {
        Write-Host "Importing $($img.source) as $($img.target)."
        Invoke-L09Az -Raw @('acr', 'import', '--name', $lab.registry, '--source', $img.source, '--image', $img.target, '--force') | Out-Null
    }
    Write-Host 'Second pass: the AKS cluster and the container app.'
    Invoke-L09Preview (New-L09Parameters $true)
    $result = Invoke-L09Az (@('deployment', 'sub', 'create') + $script:base)
    if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success on the second pass.' }
    $lab = $result.properties.outputs.lab.value
}

# Publish the function code. Flex Consumption takes a package; basic auth is off, so the CLI uses
# the operator's Entra token.
$zip = Join-Path $script:L09State 'function.zip'
Compress-Archive -Path (Join-Path $script:L09Lab 'infra/lesson-09/function/*') -DestinationPath $zip -Force
Invoke-L09Az -Raw @('functionapp', 'deployment', 'source', 'config-zip', '--resource-group', $cfg.resourceGroup, '--name', $lab.functionApp, '--src', $zip) | Out-Null
Write-Host "Published the parts function to $($lab.functionApp)."

# The node resource group exists only once the cluster does, and AKS bills the node there.
if ($cfg.budget.enabled) {
    $nodeParams = Join-Path $script:L09State 'node-budget.parameters.json'
    [ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = [ordered]@{
            name = @{ value = $cfg.names.nodeBudget }; amount = @{ value = $cfg.budget.nodeMonthlyAmountUsd }; startDate = @{ value = (Get-Date -Format 'yyyy-MM-01') }
            actualThresholds = @{ value = $cfg.budget.actualThresholds }; forecastThreshold = @{ value = $cfg.budget.forecastThreshold }; contactRoles = @{ value = $cfg.budget.contactRoles } } } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $nodeParams -Encoding utf8
    $nb = Invoke-L09Az @('deployment', 'group', 'create', '--resource-group', $cfg.names.aksNodeResourceGroup, '--name', 'contoso-appplatform-node-budget', '--template-file', (Join-Path $script:L09Lab 'infra/lesson-09/budget.bicep'), '--parameters', ('@' + $nodeParams))
    if ($nb.properties.provisioningState -ne 'Succeeded') { throw 'The node resource group budget did not deploy.' }
    Write-Host "Budget $($cfg.names.nodeBudget) is on $($cfg.names.aksNodeResourceGroup)."
}

[void](Write-L09Evidence 'deployment' ([ordered]@{ state = $result.properties.provisioningState; duration = $result.properties.duration; apiAppId = $apiAppId; outputs = $lab }))
Write-Host ("Retained lab deployed in {0:N0} minutes. AKS is running; Start-L09Lab.ps1 -Stop stops it." -f ((Get-Date) - $started).TotalMinutes)
