<#
.SYNOPSIS
Validates, previews, or deploys the isolated Lesson 2 managed-identity laboratory.
.DESCRIPTION
The subscription and tenant are pinned in the Lesson 2 configuration. Default
mode previews only. Apply collects live identity evidence and stops container
compute even after a failed deployment. Existing Lesson 1 resources are untouched.
.EXAMPLE
.\scripts\lesson-02\Deploy-L02Workload.ps1 -Mode WhatIf
.EXAMPLE
.\scripts\lesson-02\Deploy-L02Workload.ps1 -Mode Apply
.EXAMPLE
.\scripts\lesson-02\Deploy-L02Workload.ps1 -Mode Apply -IncludeFederation
#>
[CmdletBinding()]
param([ValidateSet('Validate','WhatIf','Apply')][string]$Mode = 'WhatIf', [switch]$IncludeFederation,
    [ValidateSet('Both','UserAssigned','SystemAssigned')][string]$Identity = 'Both')
. (Join-Path $PSScriptRoot 'L02.Cloud.Common.ps1')
Assert-L02Context
foreach ($groupName in @($script:L02Config.identityGroup,$script:L02Config.targetGroup)) { [void](Assert-L02OwnedGroup -Name $groupName -AllowAbsent) }
foreach ($providerName in @('Microsoft.ContainerInstance','Microsoft.ManagedIdentity')) {
    $provider = Invoke-L02Az @('provider','show','--namespace',$providerName,'--subscription',$script:L02Config.subscriptionId)
    if ($provider.registrationState -ne 'Registered') { throw "Register $providerName before deploying Lesson 2." }
}
$privatePath = Join-Path $script:L02Root '.azure/lesson-02'
[void][IO.Directory]::CreateDirectory($privatePath)
$parameterFile = Join-Path $privatePath 'workload.parameters.json'
$compiledFile = Join-Path $privatePath 'workload.compiled.json'
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'identity-probe.py'))
$parameters = @{ '$schema'='https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion='1.0.0.0'; parameters=@{
    location=@{value=$script:L02Config.location}; probeSourceBase64=@{value=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($source))}; includeFederation=@{value=[bool]$IncludeFederation}; probeIdentity=@{value=$Identity}
} }
$parameters | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $parameterFile -Encoding utf8
[void](Invoke-L02Az @('bicep','build','--file',(Join-Path $script:L02Root 'infra/lesson-02/main.bicep'),'--outfile',$compiledFile))
$common = @('--name',$script:L02Config.deploymentName,'--location',$script:L02Config.location,'--subscription',$script:L02Config.subscriptionId,'--template-file',$compiledFile,'--parameters',('@'+$parameterFile))
$validation = Invoke-L02Az (@('deployment','sub','validate') + $common)
Write-L02Evidence -Name 'arm-validation' -Value $validation
Write-Host 'Bicep compilation and live ARM validation passed.'
if ($Mode -eq 'Validate') { return }
$preview = Invoke-L02Az (@('deployment','sub','what-if') + $common + @('--no-pretty-print'))
Write-L02Evidence -Name 'what-if' -Value $preview
foreach ($change in @($preview.changes)) {
    if ($change.changeType -eq 'Delete') { throw 'The deployment preview proposed a deletion.' }
    if ($change.changeType -in @('NoChange','Ignore')) { continue }
    $prefix = '/subscriptions/' + $script:L02Config.subscriptionId + '/resourceGroups/'
    $allowed = @($script:L02Config.identityGroup,$script:L02Config.targetGroup) | Where-Object { $change.resourceId -eq ($prefix+$_) -or $change.resourceId.StartsWith(($prefix+$_+'/'),[StringComparison]::OrdinalIgnoreCase) }
    if (-not $allowed -and $change.changeType -eq 'Unsupported' -and $change.after.type -eq 'Microsoft.Authorization/roleAssignments') {
        # What-if cannot resolve new identity principal IDs. Admit only these two exact Reader expressions.
        $targetId = $prefix + $script:L02Config.targetGroup
        $identityPrefix = $prefix + $script:L02Config.identityGroup + '/providers/'
        $readerId = '/subscriptions/' + $script:L02Config.subscriptionId + '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
        $principalReferences = @(
            "reference('$($identityPrefix)Microsoft.ContainerInstance/containerGroups/$($script:L02Config.containerName)', '2025-09-01', 'full').identity.principalId",
            "reference('$($identityPrefix)Microsoft.ManagedIdentity/userAssignedIdentities/$($script:L02Config.identityName)', '2024-11-30').principalId"
        )
        foreach ($principalReference in $principalReferences) {
            $expectedId = "[resourceId('$($script:L02Config.subscriptionId)', '$($script:L02Config.targetGroup)', 'Microsoft.Authorization/roleAssignments', guid('$targetId', $principalReference, '$readerId'))]"
            if ($change.resourceId -eq $expectedId -and $change.after.properties.principalId -eq "[$principalReference]" -and $change.after.properties.roleDefinitionId -eq $readerId -and $change.after.properties.principalType -eq 'ServicePrincipal') { $allowed = $true }
        }
    }
    if (-not $allowed) { throw "Deployment preview escaped Lesson 2: $($change.resourceId)" }
}
$preview.changes | Select-Object changeType,resourceId | Format-Table -AutoSize
if ($Mode -ne 'Apply') { return }
try {
    $deployment = Invoke-L02Az (@('deployment','sub','create') + $common)
    Write-L02Evidence -Name 'deployment' -Value $deployment
    $deployment.properties.outputs | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $privatePath 'workload-bindings.json') -Encoding utf8
    & (Join-Path $PSScriptRoot 'Invoke-L02IdentityProbe.ps1') -AlreadyRunning -Identity $Identity
} finally {
    # This also covers a partial deployment failure before the normal probe controller starts.
    & (Join-Path $PSScriptRoot 'Stop-L02Workload.ps1')
}
