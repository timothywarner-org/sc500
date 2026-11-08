<#
.SYNOPSIS
    Read-only readiness check for the Lesson 9 lab at CTSO-L09-BASELINE.

.DESCRIPTION
    PASS means the check matches the baseline the demos start from. WARN means something costs
    money or needs attention before the demo but doesn't break the baseline (AKS running, the edge
    part still present, an AKS-managed resource without the CAF tags). FAIL means a demo would
    start from the wrong state; run Reset-L09Lab.ps1 (or Deploy-L09Lab.ps1 -Deploy) and check
    again. Changes nothing.

    The deployment standard's read back (docs/CONTOSO-AZURE-DEPLOYMENT.md, step 5): every resource
    in rg-appplatform-prod-eastus2 carries the CAF tag set, both budgets exist, the Defender plans
    the lesson shows are on, and the lesson's own baseline holds. Resources are listed through ARM,
    and an empty listing is a FAIL, never a pass. Every allow list that names the operator's IP
    (AKS API server, container app, logic app) must match the current public IP;
    Set-L09OperatorIp.ps1 -Apply fixes a stale one.

.PARAMETER TakeReady
    Check the state the demo starts from instead of the idle baseline: the cluster running, the
    bounded edge present, and live probes through Application Gateway (200), Front Door (200), and
    straight to the origin (403).

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Test-L09Lab.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Test-L09Lab.ps1 -TakeReady
#>
[CmdletBinding()]
param([switch]$TakeReady)
. (Join-Path $PSScriptRoot 'L09.Common.ps1')
[void](Assert-L09Context)
$cfg = $script:L09Config
$rg = $cfg.resourceGroup
$n = $cfg.names
$sub = $cfg.subscriptionId
$checks = [Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, $Expected, $Actual, [switch]$WarnOnly) {
    $ok = "$Expected" -eq "$Actual"
    $checks.Add([pscustomobject]@{ Result = if ($ok) { 'PASS' } elseif ($WarnOnly) { 'WARN' } else { 'FAIL' }; Check = $Name; Expected = "$Expected"; Actual = "$Actual" })
}
$cafKeys = @($cfg.tags.PSObject.Properties.Name) + 'workload', 'env'
function Get-MissingTag($Resource) {
    $t = Get-L09Value $Resource 'tags'
    if ($null -eq $t) { return $cafKeys }
    return @($cafKeys | Where-Object { $null -eq $t.PSObject.Properties[$_] })
}

# Subscription prerequisites (Set-L09DefenderWindow.ps1 owns them; this only reads).
$containers = Invoke-L09Rest -Path "/subscriptions/$sub/providers/Microsoft.Security/pricings/Containers?api-version=2024-01-01"
Add-Check 'Defender for Containers (subscription)' 'Standard' $containers.properties.pricingTier
foreach ($e in 'ContainerSensor', 'AgentlessDiscoveryForKubernetes', 'ContainerRegistriesVulnerabilityAssessments') {
    $x = @(@(Get-L09Value $containers 'properties.extensions') | Where-Object { $null -ne $_ -and $_.name -eq $e })
    Add-Check "Defender for Containers extension $e" 'True' $(if ($x.Count) { $x[0].isEnabled } else { 'missing' })
}
$appPlan = Invoke-L09Rest -Path "/subscriptions/$sub/providers/Microsoft.Security/pricings/AppServices?api-version=2024-01-01"
Add-Check 'Defender for App Service (subscription)' 'Standard' $appPlan.properties.pricingTier

$group = Invoke-L09Az @('group', 'show', '--name', $rg)
Add-Check 'Resource group tag managedby' $cfg.managedBy (Get-L09Value $group 'tags.managedby')
Add-Check 'Resource group location' $cfg.location $group.location
$lab = Get-L09Outputs -Lab Retained

# Every resource carries the CAF tags. The ARM list, not az resource list: Azure CLI 2.85.0's list
# returned [] for populated groups (September 27 and November 1, 2026), which would make this pass on nothing.
$all = @(Get-L09GroupResources)
Add-Check 'Resources listed in the group (an empty list proves nothing)' 'more than 0' $(if ($all.Count) { 'more than 0' } else { '0' })
$untagged = @($all | Where-Object { @(Get-MissingTag $_).Count })
Add-Check "Resources missing a CAF tag (of $($all.Count))" 'none' $(if ($untagged.Count) { ($untagged | ForEach-Object { "$($_.name) [$((Get-MissingTag $_) -join ',')]" }) -join '; ' } else { 'none' })
# eastus2, except the web origin and its plan (webLocation: App Service quota) and Front Door (global).
$offRegion = @($all | Where-Object { $_.location -ne 'global' -and -not ($_.location -eq $cfg.location -or ($_.type -like 'Microsoft.Web/*' -and $_.name -in @($n.webPlan, $n.webApp) -and $_.location -eq $cfg.webLocation)) })
Add-Check "Resources outside their config.json region" 'none' $(if ($offRegion.Count) { ($offRegion | ForEach-Object { "$($_.name) in $($_.location)" }) -join '; ' } else { 'none' })

# Budgets: the lab group, and the node group where AKS bills the node.
foreach ($b in @(@{ name = $n.budget; group = $rg; amount = $cfg.budget.monthlyAmountUsd }, @{ name = $n.nodeBudget; group = $n.aksNodeResourceGroup; amount = $cfg.budget.nodeMonthlyAmountUsd })) {
    $r = Invoke-L09Az -AllowFailure @('consumption', 'budget', 'show', '--budget-name', $b.name, '--resource-group', $b.group)
    Add-Check "Budget $($b.name)" "$($b.amount)" $(if ($r.ExitCode -eq 0) { [int]($r.Stdout | ConvertFrom-Json).amount } else { 'missing' })
}

# The AKS node resource group: AKS copies the cluster's tags to the group and the resources it
# creates there, and the node pool's tags to the scale set. AKS-managed tags it adds are left alone.
$nodeGroup = Invoke-L09Az -AllowFailure @('group', 'show', '--name', $n.aksNodeResourceGroup)
Add-Check "Node resource group $($n.aksNodeResourceGroup)" 'present' $(if ($nodeGroup.ExitCode -eq 0) { 'present' } else { 'missing' })
if ($nodeGroup.ExitCode -eq 0) {
    Add-Check 'Node resource group tag managedby' $cfg.managedBy (Get-L09Value ($nodeGroup.Stdout | ConvertFrom-Json) 'tags.managedby')
    $nodeAll = @(Get-L09GroupResources -ResourceGroup $n.aksNodeResourceGroup)
    Add-Check 'Resources listed in the node group (an empty list proves nothing)' 'more than 0' $(if ($nodeAll.Count) { 'more than 0' } else { '0' })
    $nodeUntagged = @($nodeAll | Where-Object { @(Get-MissingTag $_).Count })
    Add-Check "Node group resources missing a CAF tag (of $($nodeAll.Count))" 'none' $(if ($nodeUntagged.Count) { ($nodeUntagged | ForEach-Object { "$($_.name) ($($_.type))" }) -join '; ' } else { 'none' }) -WarnOnly
}

# The lab API registration: an API with one scope, pre-authorized for the Azure CLI, no secrets.
$app = Get-L09ApiApp
Add-Check "App registration $($cfg.apiAppDisplayName)" 'present' $(if ($app) { 'present' } else { 'missing' })
if ($app) {
    Add-Check 'API identifier URI' "api://$($app.appId)" (@($app.identifierUris) -join ',')
    Add-Check 'Azure CLI pre-authorized' 'True' ([bool](@(Get-L09Value $app 'api.preAuthorizedApplications' | Where-Object { $_ -and $_.appId -eq $cfg.azureCliClientId }).Count))
    $creds = Invoke-L09Rest -Path "https://graph.microsoft.com/v1.0/applications/$($app.id)?`$select=passwordCredentials,keyCredentials"
    Add-Check 'App secrets and certificates' 0 (@($creds.passwordCredentials).Count + @($creds.keyCredentials).Count)
}

# 9.1 containers
$acr = Invoke-L09Az @('acr', 'show', '--name', $n.registry)
Add-Check "$($n.registry) SKU" 'Basic' $acr.sku.name
Add-Check "$($n.registry) admin user" 'False' ([bool]$acr.adminUserEnabled)
$repos = @(Invoke-L09Az @('acr', 'repository', 'list', '--name', $n.registry))
Add-Check 'Registry repositories' 'servicehub/status servicehub/web' (($repos | Sort-Object) -join ' ')
$aks = Invoke-L09Az @('aks', 'show', '--resource-group', $rg, '--name', $n.aks)
Add-Check "$($n.aks) location" $cfg.aksLocation $aks.location
Add-Check "$($n.aks) node resource group" $n.aksNodeResourceGroup $aks.nodeResourceGroup
Add-Check "$($n.aks) node size" $cfg.aksNodeSize (@($aks.agentPoolProfiles)[0].vmSize)
Add-Check "$($n.aks) node pool tag managedby" $cfg.managedBy (Get-L09Value @($aks.agentPoolProfiles)[0] 'tags.managedby')
Add-Check "$($n.aks) local accounts disabled" 'True' ([bool](Get-L09Value $aks 'disableLocalAccounts'))
Add-Check "$($n.aks) Azure RBAC" 'True' ([bool](Get-L09Value $aks 'aadProfile.enableAzureRbac'))
Add-Check "$($n.aks) Defender sensor" 'True' ([bool](Get-L09Value $aks 'securityProfile.defender.securityMonitoring.enabled'))
Add-Check "$($n.aks) Azure Policy add-on" 'True' ([bool](Get-L09Value $aks 'addonProfiles.azurepolicy.enabled'))
Add-Check "$($n.aks) workload identity" 'True' ([bool](Get-L09Value $aks 'securityProfile.workloadIdentity.enabled'))
Add-Check "$($n.aks) image cleaner" 'True' ([bool](Get-L09Value $aks 'securityProfile.imageCleaner.enabled'))
$operatorCidr = "$(Get-L09OperatorIp)/32"
$ipWord = { param($list) if (@($list).Count -eq 1 -and @($list)[0] -eq $operatorCidr) { 'Your current IP' } else { "$(@($list).Count) other address(es)" } }
Add-Check "$($n.aks) API server allow list (Set-L09OperatorIp.ps1 -Apply if stale)" 'Your current IP' (& $ipWord @(Get-L09Value $aks 'apiServerAccessProfile.authorizedIpRanges'))
if ($TakeReady) { Add-Check "$($n.aks) power state (running for the demo)" 'Running' $aks.powerState.code }
else { Add-Check "$($n.aks) power state (stopped between runs)" 'Stopped' $aks.powerState.code -WarnOnly }
$pa = Invoke-L09Az -AllowFailure @('policy', 'assignment', 'show', '--name', $n.privilegedPolicy, '--resource-group', $rg)
Add-Check "Policy $($n.privilegedPolicy) effect" 'Deny' $(if ($pa.ExitCode -eq 0) { ($pa.Stdout | ConvertFrom-Json).parameters.effect.value } else { 'missing' })
$ca = Invoke-L09Rest -Path "$(Get-L09ResourceId 'Microsoft.App/containerApps' $n.containerApp)?api-version=2024-03-01" -AllowNotFound
$caRules = @(if ($ca) { Get-L09Value $ca 'properties.configuration.ingress.ipSecurityRestrictions' })
Add-Check "$($n.containerApp) ingress rule" 'Allow operator' $(if ($caRules.Count -eq 1 -and $caRules[0].action -eq 'Allow' -and $caRules[0].name -eq 'allow-operator') { 'Allow operator' } else { "$($caRules.Count) rule(s)" })
Add-Check "$($n.containerApp) allow list address (Set-L09OperatorIp.ps1 -Apply if stale)" 'Your current IP' (& $ipWord @($caRules | ForEach-Object ipAddressRange))
Add-Check "$($n.containerApp) registry password" 'none' $(if ($ca -and (Get-L09Value @($ca.properties.configuration.registries)[0] 'passwordSecretRef')) { 'present' } else { 'none' })

# 9.2 serverless
$funcId = Get-L09ResourceId 'Microsoft.Web/sites' $n.functionApp
$site = Invoke-L09Rest -Path "$funcId`?api-version=2024-04-01"
Add-Check "$($n.functionApp) HTTPS only" 'True' $site.properties.httpsOnly
$auth = Invoke-L09Rest -Path "$funcId/config/authsettingsV2?api-version=2024-04-01"
Add-Check 'Function authentication' 'True Return401' ('{0} {1}' -f $auth.properties.globalValidation.requireAuthentication, $auth.properties.globalValidation.unauthenticatedClientAction)
Add-Check 'Function allowed client application' $lab.apimIdentityClientId (@($auth.properties.identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedApplications) -join ',')
foreach ($k in 'ftp', 'scm') {
    $b = Invoke-L09Rest -Path "$funcId/basicPublishingCredentialsPolicies/$k`?api-version=2024-04-01"
    Add-Check "Function $k basic auth" 'False' $b.properties.allow
}
$code = Invoke-L09Rest -Path "$funcId/functions?api-version=2024-04-01"
Add-Check 'Function code deployed' 'parts' (@($code.value | ForEach-Object { ($_.name -split '/')[-1] }) -join ',')
$stAcct = Invoke-L09Rest -Path "$(Get-L09ResourceId 'Microsoft.Storage/storageAccounts' $n.storage)?api-version=2023-05-01"
Add-Check "$($n.storage) shared key access" 'False' $stAcct.properties.allowSharedKeyAccess
$wf = Invoke-L09Rest -Path "$(Get-L09ResourceId 'Microsoft.Logic/workflows' $n.logicApp)?api-version=2019-05-01"
Add-Check 'Logic app SAS authentication' 'Disabled' (Get-L09Value $wf 'properties.accessControl.triggers.sasAuthenticationPolicy.state')
Add-Check 'Logic app Entra policy aud' $lab.apiAudience (@($wf.properties.accessControl.triggers.openAuthenticationPolicies.policies.servicehub.claims | Where-Object name -eq 'aud').value)
Add-Check 'Logic app secure inputs/outputs' 'inputs,outputs' (@(Get-L09Value $wf.properties.definition.triggers.manual 'runtimeConfiguration.secureData.properties') -join ',')
Add-Check 'Logic app trigger callers (Set-L09OperatorIp.ps1 -Apply if stale)' 'Your current IP' (& $ipWord @(Get-L09Value $wf 'properties.accessControl.triggers.allowedCallerIpAddresses' | ForEach-Object addressRange))
Add-Check 'Logic app run-history callers' 'Your current IP' (& $ipWord @(Get-L09Value $wf 'properties.accessControl.contents.allowedCallerIpAddresses' | ForEach-Object addressRange))

# 9.4 API Management
$apimId = Get-L09ResourceId 'Microsoft.ApiManagement/service' $n.apim
$p = Invoke-L09Rest -Path "$apimId/apis/servicehub-parts/policies/policy?api-version=2024-05-01&format=rawxml"
$xml = if ($p -is [string]) { $p } else { $p.properties.value }
foreach ($tag in 'validate-azure-ad-token', 'rate-limit', 'authentication-managed-identity') {
    Add-Check "API policy has $tag" 'True' ($xml -match "<$tag\b")
}
$apiDef = Invoke-L09Rest -Path "$apimId/apis/servicehub-parts?api-version=2024-05-01"
Add-Check 'API subscription required' 'True' $apiDef.properties.subscriptionRequired

# The bounded edge: gone between runs, present (and answering) for one.
$bounded = @($all | Where-Object { Test-L09Bounded $_ })
if (-not $TakeReady) {
    Add-Check 'Edge part (bounded, about 0.65 USD an hour)' 'absent' $(if ($bounded.Count) { "$($bounded.Count) resource(s) present: $(@($bounded | ForEach-Object name) -join ', ')" } else { 'absent' }) -WarnOnly
}
else {
    $edgeNames = @($n.webPlan, $n.webApp, $n.gatewayIp, $n.gatewayWaf, $n.gateway, $n.frontDoor, $n.frontDoorWaf, $n.containerGroup)
    $missing = @($edgeNames | Where-Object { $_ -notin @($bounded | ForEach-Object name) })
    Add-Check 'Edge part present, tagged bounded' 'all 8' $(if ($missing.Count) { "missing: $($missing -join ', ')" } else { 'all 8' })
    $edge = $null
    try { $edge = Get-L09Outputs -Lab Edge } catch { Add-Check 'Edge deployment record' 'Succeeded' $_.Exception.Message }
    if ($edge) {
        # What a browser sends: a bare scripted request to the gateway's IP scored 5 and was blocked
        # in the September rehearsal (rules 920350 and 920320), with no attack in it.
        $ua = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ServiceHub-readiness'; 'Accept' = 'text/html' }
        Add-Check "Origin $($edge.webHost) direct (default deny)" 403 (Invoke-L09Http -Uri "https://$($edge.webHost)/" -Headers $ua -TimeoutSec 60).Status
        Add-Check 'Through Application Gateway' 200 (Invoke-L09Http -Uri "http://$($edge.gatewayIp)/" -Headers $ua -TimeoutSec 60).Status
        Add-Check "Through Front Door $($edge.frontDoorHost)" 200 (Invoke-L09Http -Uri "https://$($edge.frontDoorHost)/" -Headers $ua -TimeoutSec 60).Status
        $worker = Invoke-L09Rest -Path "$(Get-L09ResourceId 'Microsoft.ContainerInstance/containerGroups' $n.containerGroup)?api-version=2023-05-01" -AllowNotFound
        Add-Check "$($n.containerGroup) state" 'Running' $(if ($worker) { Get-L09Value $worker 'properties.instanceView.state' } else { 'missing' })
    }
}

[void](Write-L09Evidence 'readiness' $checks)
$fails = @($checks | Where-Object Result -eq 'FAIL').Count
$warns = @($checks | Where-Object Result -eq 'WARN').Count
if ($fails -and $TakeReady) { "NOT TAKE-READY: $fails check(s) failed. Deploy-L09Edge.ps1 -Deploy restores the edge, Start-L09Lab.ps1 starts the cluster, and Set-L09OperatorIp.ps1 -Apply fixes a stale allow list." }
elseif ($fails) { "NOT READY: $fails check(s) failed. Reset-L09Lab.ps1 removes the edge and restores the demo settings; Deploy-L09Lab.ps1 -Deploy restores the retained part." }
elseif ($TakeReady) { "TAKE-READY CHECK PASSED at $((Get-Date).ToString('HH:mm')) ($warns warning(s)): cluster running, edge answering. This doesn't prove Defender's findings; run the demos for that." }
else { "BASELINE CHECK PASSED: $($cfg.baseline) ($warns warning(s)). This doesn't prove Defender's findings; run the demos for that." }
$checks | Format-Table -AutoSize -Wrap | Out-String -Width 240
if ($fails) { exit 1 }
