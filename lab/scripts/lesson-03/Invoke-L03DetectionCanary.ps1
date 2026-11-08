<#
.SYNOPSIS
Validates Defender for Key Vault with a separate synthetic-only canary vault.
.DESCRIPTION
The retained ServiceHub vault stays private. Temporarily exposes an authenticated
canary endpoint for Microsoft's documented Tor validation, then disables public
access and removes the exact read grant in finally. A sent request is not an alert.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
[void](Assert-L03Group $script:L03Config.resourceGroup)
$lab=Get-L03Outputs
$template=Join-Path $script:L03Root 'infra/lesson-03/detection-canary.bicep'
$base=@('--resource-group',$script:L03Config.resourceGroup,'--name','sc500-l03-detection-canary','--template-file',$template,'--parameters',('runnerPrincipalId='+$lab.runnerPrincipalId),'--subscription',$script:L03Config.subscriptionId)
[void](Write-L03Evidence 'detection-canary-validation' (Invoke-L03Az (@('deployment','group','validate')+$base)))
$preview=Invoke-L03Az (@('deployment','group','what-if')+$base+@('--no-pretty-print'))
[void](Write-L03Evidence 'detection-canary-preview' $preview)
foreach($change in $preview.changes){
    if($change.changeType -notin @('NoChange','Ignore','Create','Modify') -or ($change.changeType -in @('Create','Modify') -and $change.resourceId -notmatch '/Microsoft.KeyVault/vaults/kv-sc500-l03-signal-[a-z0-9]{4}(/|$)')){throw 'Canary preview is outside the synthetic fixture.'}
}
$canaryIds=@($preview.changes|Where-Object {$_.resourceId -match '/Microsoft.KeyVault/vaults/kv-sc500-l03-signal-[a-z0-9]{4}$'}|ForEach-Object resourceId)
if($canaryIds.Count -ne 1){throw 'Exactly one canary vault must be present in the preview.'}
$canaryName=$canaryIds[0].Split('/')[-1]
try {
    $deployment=Invoke-L03Az (@('deployment','group','create')+$base)
    $output=$deployment.properties.outputs
    [void](Write-L03Evidence 'detection-canary-deployed' $deployment)
    & (Join-Path $PSScriptRoot 'Invoke-L03Guest.ps1') -SourcePath (Join-Path $PSScriptRoot 'validate_vault_detection.py') -Arguments @('--vault',$output.vaultName.value,'--principal',$lab.runnerPrincipalId)
} finally {
    # Close the validation route regardless of whether Defender has produced an alert yet.
    [void](Invoke-L03Az @('keyvault','update','--name',$canaryName,'--resource-group',$script:L03Config.resourceGroup,'--public-network-access','Disabled','--default-action','Deny'))
    $grants=@(Invoke-L03Az @('role','assignment','list','--assignee',$lab.runnerPrincipalId,'--scope',$canaryIds[0],'--role','4633458b-17de-408a-b874-0445c86b69e6'))
    foreach($grant in $grants){if($grant.scope -ieq $canaryIds[0]){[void](Invoke-L03Az @('role','assignment','delete','--ids',$grant.id))}}
    $closed=Invoke-L03Az @('keyvault','show','--name',$canaryName,'--resource-group',$script:L03Config.resourceGroup)
    if($closed.properties.publicNetworkAccess -ne 'Disabled'){throw 'Canary network cleanup did not complete.'}
    [void](Write-L03Evidence 'detection-canary-closed' @{vaultId=$closed.id;publicNetworkAccess=$closed.properties.publicNetworkAccess;readGrantRemoved=$true})
}
