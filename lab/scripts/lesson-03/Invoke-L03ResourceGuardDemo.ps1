<#
.SYNOPSIS
Proves Resource Guard denial, separately authorized success, and restored MUA protection.
.DESCRIPTION
Uses the existing bootstrap managed identity as the temporary backup operator. The
human owner supplies and then removes the separate guard authorization. This is a
two-identity RBAC demonstration, not a claim that PIM approval was exercised.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
[void](Assert-L03Group $script:L03Config.resourceGroup)
[void](Assert-L03Group $script:L03Config.policyGroup)
$lab=Get-L03Outputs
$mapping=Invoke-L03Az @('backup','vault','resource-guard-mapping','show','--resource-group',$script:L03Config.resourceGroup,'--name',$lab.recoveryVaultName,'--subscription',$script:L03Config.subscriptionId)
$guard=$mapping.properties.resourceGuardResourceId
$request=@($mapping.properties.resourceGuardOperationDetails|Where-Object vaultCriticalOperation -eq 'Microsoft.RecoveryServices/vaults/backupResourceGuardProxies/delete')
if($request.Count -ne 1 -or -not $guard.EndsWith('/resourceGuards/guard-sc500-l03')){throw 'Expected lesson-owned MUA mapping was not found.'}
$existing=@(Invoke-L03Az @('role','assignment','list','--all','--subscription',$script:L03Config.subscriptionId)|Where-Object principalId -eq $lab.bootstrapPrincipalId)
if($existing.Count){throw 'Bootstrap identity already has roles. Inspect them before demonstrating independent authorization.'}
$grants=[Collections.Generic.List[string]]::new()
function Add-TemporaryRole([string]$Role,[string]$Scope){
    $grant=Invoke-L03Az @('role','assignment','create','--assignee-object-id',$lab.bootstrapPrincipalId,'--assignee-principal-type','ServicePrincipal','--role',$Role,'--scope',$Scope,'--subscription',$script:L03Config.subscriptionId)
    $grants.Add($grant.id)
}
$denied=$null;$allowed=$null;$restored=$false
try{
    Add-TemporaryRole 'Backup Contributor' $lab.recoveryVaultId
    Add-TemporaryRole 'Reader' $guard
    $arguments=@('--client',$lab.bootstrapClientId,'--principal',$lab.bootstrapPrincipalId,'--vault',$lab.recoveryVaultId,'--proxy',$mapping.id,'--guard-request',$request[0].defaultResourceRequest)
    & (Join-Path $PSScriptRoot 'Invoke-L03Guest.ps1') -SourcePath (Join-Path $PSScriptRoot 'resource_guard_probe.py') -Arguments ($arguments+@('--phase','Denied'))
    $file=Get-ChildItem $script:L03Evidence -Filter '*-completion-resource-guard-denied.json'|Sort-Object Name|Select-Object -Last 1
    $denied=Get-Content $file.FullName -Raw|ConvertFrom-Json
    if($denied.unlockStatus -ne 403 -or $denied.unlockReply.error.code -ne 'LinkedAuthorizationFailed' -or $denied.unlockReply.error.message -notmatch 'resourceGuards/deleteResourceGuardProxyRequests/approve/action'){throw 'The denial was not proven to be the independent Resource Guard boundary.'}
    Add-TemporaryRole 'Backup MUA Operator' $guard
    & (Join-Path $PSScriptRoot 'Invoke-L03Guest.ps1') -SourcePath (Join-Path $PSScriptRoot 'resource_guard_probe.py') -Arguments ($arguments+@('--phase','Allowed'))
    $file=Get-ChildItem $script:L03Evidence -Filter '*-completion-resource-guard-allowed.json'|Sort-Object Name|Select-Object -Last 1
    $allowed=Get-Content $file.FullName -Raw|ConvertFrom-Json
    if($allowed.unlockStatus -ne 200 -or -not $allowed.protectionRemoved){throw 'The separately authorized critical operation has not succeeded.'}
} finally {
    try{
        # Re-enable the guard even after a failed probe; a teaching operation must not leave protection reduced.
        $after=Invoke-L03Az @('backup','vault','resource-guard-mapping','update','--resource-group',$script:L03Config.resourceGroup,'--name',$lab.recoveryVaultName,'--resource-guard-id',$guard,'--subscription',$script:L03Config.subscriptionId)
        $restored=$after.properties.resourceGuardResourceId -ieq $guard
    } finally {
        foreach($grant in $grants){[void](Invoke-L03Az @('role','assignment','delete','--ids',$grant,'--subscription',$script:L03Config.subscriptionId))}
        $remaining=@(Invoke-L03Az @('role','assignment','list','--all','--subscription',$script:L03Config.subscriptionId)|Where-Object principalId -eq $lab.bootstrapPrincipalId)
        [void](Write-L03Evidence 'resource-guard-rehearsal' @{checkedAt=[DateTime]::UtcNow.ToString('o');denied=$denied;allowed=$allowed;muaRestored=$restored;temporaryGrantsRemoved=$remaining.Count -eq 0;pimApprovalExercised=$false})
        if(-not $restored -or $remaining.Count){throw 'MUA restoration or temporary permission cleanup failed.'}
    }
}
Write-Host 'Resource Guard denied the vault-only operator, accepted separate guard authorization, and was restored. Temporary grants removed.'
