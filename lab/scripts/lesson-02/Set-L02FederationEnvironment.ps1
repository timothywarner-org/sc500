<#
.SYNOPSIS
Configures the exact GitHub environment trusted by the Lesson 2 managed identity.
.DESCRIPTION
Reuses the existing federation and Reader grant. Creates only the named environment,
restricts it to main, and sets three nonsecret variables. It never creates a secret,
broadens Azure access, or removes an existing GitHub protection rule.
.EXAMPLE
./scripts/lesson-02/Set-L02FederationEnvironment.ps1
.EXAMPLE
./scripts/lesson-02/Set-L02FederationEnvironment.ps1 -Apply
#>
[CmdletBinding()]
param([switch]$Apply)
. (Join-Path $PSScriptRoot 'L02.Cloud.Common.ps1')
Assert-L02Context
[void](Assert-L02OwnedGroup -Name $script:L02Config.identityGroup)
$repo='<your-github-owner>/sc500'
$environment='sc500-lesson02'
$base="repos/$repo/environments/$environment"

function Invoke-L02GitHub {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $response = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub request failed: $($Arguments[0])" }
    if ($response) { ($response -join "`n") | ConvertFrom-Json -Depth 50 }
}

$identity=Invoke-L02Az @('identity','show','--name',$script:L02Config.identityName,'--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId)
$federation=Invoke-L02Az @('identity','federated-credential','show','--name','github-sc500-lesson02','--identity-name',$script:L02Config.identityName,'--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId)
if($federation.issuer -cne 'https://token.actions.githubusercontent.com' -or $federation.subject -cne "repo:$($repo):environment:$environment" -or @($federation.audiences).Count -ne 1 -or $federation.audiences[0] -cne 'api://AzureADTokenExchange') {throw 'The existing federation does not match the bounded GitHub proof.'}
$settings=Invoke-L02GitHub @('api',"repos/$repo/actions/permissions")
if(-not $settings.enabled){throw 'GitHub Actions is disabled for the intended repository.'}
$list=Invoke-L02GitHub @('api',"repos/$repo/environments")
$existing=@($list.environments | Where-Object name -ceq $environment)
if($existing.Count -gt 1){throw 'Ambiguous environment match.'}
# Preserve existing review rules. An unexpected branch policy requires inspection, never silent relaxation.
if($existing.Count -and (-not $existing[0].deployment_branch_policy.custom_branch_policies -or $existing[0].deployment_branch_policy.protected_branches)){throw 'Existing environment branch protection differs from the intended main-only rule.'}
$values=@{AZURE_CLIENT_ID=$identity.clientId;AZURE_TENANT_ID=$script:L02Config.tenantId;AZURE_SUBSCRIPTION_ID=$script:L02Config.subscriptionId}
if(-not $Apply){[pscustomobject]@{Repository=$repo;Environment=$environment;Branch='main';Variables=$values;ChangesApplied=$false}|ConvertTo-Json -Depth 5;return}
$privatePath=Join-Path $script:L02Root '.azure/lesson-02'
if(-not $existing.Count){
    $bodyPath=Join-Path $privatePath 'github-environment-request.json'
    @{deployment_branch_policy=@{protected_branches=$false;custom_branch_policies=$true}}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $bodyPath
    [void](Invoke-L02GitHub @('api','--method','PUT',$base,'--input',$bodyPath))
}
$branches=Invoke-L02GitHub @('api',"$base/deployment-branch-policies")
if(@($branches.branch_policies | Where-Object { $_.name -cne 'main' -or $_.type -ne 'branch' }).Count){throw 'Unexpected branch/tag rule exists; no rule was removed.'}
if(@($branches.branch_policies).Count -eq 0){
    $bodyPath=Join-Path $privatePath 'github-branch-request.json'
    @{name='main';type='branch'}|ConvertTo-Json|Set-Content -LiteralPath $bodyPath
    [void](Invoke-L02GitHub @('api','--method','POST',"$base/deployment-branch-policies",'--input',$bodyPath))
}
foreach($pair in $values.GetEnumerator()){
    & gh variable set $pair.Key --repo $repo --env $environment --body $pair.Value
    if($LASTEXITCODE -ne 0){throw "Environment variable update failed: $($pair.Key)"}
}
$actual=Invoke-L02GitHub @('api',$base)
$branches=Invoke-L02GitHub @('api',"$base/deployment-branch-policies")
$variables=Invoke-L02GitHub @('api',"$base/variables")
foreach($pair in $values.GetEnumerator()){
    $found=@($variables.variables | Where-Object name -ceq $pair.Key)
    if($found.Count -ne 1 -or $found[0].value -cne $pair.Value){throw "Readback mismatch: $($pair.Key)"}
}
if(@($branches.branch_policies).Count -ne 1 -or $branches.branch_policies[0].name -cne 'main' -or $branches.branch_policies[0].type -ne 'branch'){throw 'Environment is not restricted to the main branch.'}
Write-L02Evidence -Name 'verified-github-environment' -Value @{capturedAt=[DateTime]::UtcNow.ToString('o');repository=$repo;environment=$actual;branchPolicies=$branches;variables=$variables;federation=$federation;workflowExecutedByThisCommand=$false}
Write-Output 'GitHub environment verified: sc500-lesson02, main branch only, three nonsecret Azure variables. This command does not execute a workflow.'
