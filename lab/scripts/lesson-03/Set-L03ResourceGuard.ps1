<#
.SYNOPSIS
Creates the lesson-owned Resource Guard and enables MUA on the retained recovery vault.
.DESCRIPTION
Validates and previews the single-resource template before applying it to the separate
policy group. No backup operator permission is assigned on the guard by this command.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
[void](Assert-L03Group $script:L03Config.policyGroup)
[void](Assert-L03Group $script:L03Config.resourceGroup)
$base=@('--resource-group',$script:L03Config.policyGroup,'--name','sc500-l03-resource-guard','--template-file',(Join-Path $script:L03Root 'infra/lesson-03/resource-guard.bicep'),'--subscription',$script:L03Config.subscriptionId)
$validation=Invoke-L03Az (@('deployment','group','validate')+$base)
[void](Write-L03Evidence 'resource-guard-validation' $validation)
$preview=Invoke-L03Az (@('deployment','group','what-if')+$base+@('--no-pretty-print'))
[void](Write-L03Evidence 'resource-guard-preview' $preview)
foreach($change in $preview.changes){
    if($change.changeType -notin @('NoChange','Ignore','Create','Modify') -or ($change.changeType -in @('Create','Modify') -and -not $change.resourceId.EndsWith('/Microsoft.DataProtection/resourceGuards/guard-sc500-l03'))){throw 'Resource Guard preview exceeds the expected scope.'}
}
$deployment=Invoke-L03Az (@('deployment','group','create')+$base)
$guardId=$deployment.properties.outputs.guardId.value
$lab=Get-L03Outputs
$mapping=Invoke-L03Az @('backup','vault','resource-guard-mapping','update','--resource-group',$script:L03Config.resourceGroup,'--name',$lab.recoveryVaultName,'--resource-guard-id',$guardId,'--subscription',$script:L03Config.subscriptionId)
[void](Write-L03Evidence 'resource-guard-mapping' $mapping)
$mapping|ConvertTo-Json -Depth 20
