<#
.SYNOPSIS
Checks deployed Lesson 2 configuration independently from application authorization.
.DESCRIPTION
This read-only inspection records identity attachments, narrowly scoped Reader
grants, ingress exposure, immutable image and optional exact federation claims.
It does not replace the live token/access probe or execute a GitHub workflow.
.EXAMPLE
.\scripts\lesson-02\Test-L02Workload.ps1 -RequireFederation
#>
[CmdletBinding()]
param([switch]$RequireFederation)
. (Join-Path $PSScriptRoot 'L02.Cloud.Common.ps1')
Assert-L02Context
[void](Assert-L02OwnedGroup -Name $script:L02Config.identityGroup)
[void](Assert-L02OwnedGroup -Name $script:L02Config.targetGroup)
$container = Invoke-L02Az @('container','show','--name',$script:L02Config.containerName,'--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId)
$identity = Invoke-L02Az @('identity','show','--name',$script:L02Config.identityName,'--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId)
$map = $container | ConvertTo-Json -Depth 50 | ConvertFrom-Json -AsHashtable
$targetId = '/subscriptions/' + $script:L02Config.subscriptionId + '/resourceGroups/' + $script:L02Config.targetGroup
$assignments = @(Invoke-L02Az @('role','assignment','list','--scope',$targetId,'--include-inherited','--subscription',$script:L02Config.subscriptionId))
$readerId = '/subscriptions/' + $script:L02Config.subscriptionId + '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
$checks = [ordered]@{
    provisioned = $container.provisioningState -eq 'Succeeded'
    tenantMatches = $container.identity.tenantId -eq $script:L02Config.tenantId
    bothIdentityTypes = $container.identity.type -eq 'SystemAssigned, UserAssigned'
    expectedUserIdentity = @($map.identity.userAssignedIdentities.Keys | Where-Object { $_ -eq $identity.id }).Count -eq 1
    noIngressAddress = $null -eq $map.ipAddress
    noExposedPorts = @($map.containers[0].ports).Where({$null -ne $_}).Count -eq 0
    immutableImage = $container.containers[0].image -eq 'mcr.microsoft.com/azure-cli@sha256:7f9ca8e6bf1c72e5fafefb6925546272776d635fb428538455c5c79bb77e2aa7'
    unprivilegedContainer = $container.containers[0].securityContext.privileged -eq $false
    boundedRestartPolicy = $container.restartPolicy -eq 'Never'
}
foreach ($principalId in @($container.identity.principalId,$identity.principalId)) {
    $principalGrants = @($assignments | Where-Object principalId -EQ $principalId)
    # Compare scope as well as role so inherited broad access cannot masquerade as this lab boundary.
    $checks["readerOnlyOnTarget_$principalId"] = $principalGrants.Count -eq 1 -and $principalGrants[0].scope -eq $targetId -and $principalGrants[0].roleDefinitionId -eq $readerId
}
$federation = $null
if ($RequireFederation) {
    $federation = Invoke-L02Az @('identity','federated-credential','show','--name','github-sc500-lesson02','--identity-name',$script:L02Config.identityName,'--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId)
    $checks['exactFederationClaims'] = $federation.issuer -ceq 'https://token.actions.githubusercontent.com' -and $federation.subject -ceq 'repo:<your-github-owner>/sc500:environment:sc500-lesson02' -and @($federation.audiences).Count -eq 1 -and $federation.audiences[0] -ceq 'api://AzureADTokenExchange'
}
$passed = @($checks.Values | Where-Object { -not $_ }).Count -eq 0
$report = @{capturedAt=[DateTime]::UtcNow.ToString('o');passed=$passed;checks=$checks;containerPowerState=$container.instanceView.state;federation=$federation;roleAssignments=$assignments;operatorAuthorizationVerified=$false;githubWorkflowExecuted=$false}
Write-L02Evidence -Name 'configuration-verification' -Value $report
$checks.GetEnumerator() | ForEach-Object { [pscustomobject]@{Check=$_.Key;Passed=$_.Value} } | Format-Table -AutoSize
if (-not $passed) { throw 'Deployed Lesson 2 configuration did not pass every explicit boundary check.' }
