<#
.SYNOPSIS
Creates the small LRS staging account required by the Lesson 3 managed-disk restore.
.DESCRIPTION
Validates the exact additive change. Public anonymous blobs are disabled, HTTPS/TLS 1.2
required, and the firewall denies ordinary networks while allowing trusted Azure services.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
[void](Assert-L03Group $script:L03Config.resourceGroup)
$base=@('--resource-group',$script:L03Config.resourceGroup,'--name','sc500-l03-restore-staging','--template-file',(Join-Path $script:L03Root 'infra/lesson-03/restore-staging.bicep'),'--subscription',$script:L03Config.subscriptionId)
[void](Write-L03Evidence 'restore-staging-validation' (Invoke-L03Az (@('deployment','group','validate')+$base)))
$preview=Invoke-L03Az (@('deployment','group','what-if')+$base+@('--no-pretty-print'))
[void](Write-L03Evidence 'restore-staging-preview' $preview)
foreach($change in $preview.changes){
    if($change.changeType -notin @('NoChange','Ignore','Create','Modify') -or ($change.changeType -in @('Create','Modify') -and $change.resourceId -notmatch '/Microsoft.Storage/storageAccounts/stsc500l03restore[a-z0-9]+$')){throw 'Restore staging preview exceeds the expected scope.'}
}
$deployment=Invoke-L03Az (@('deployment','group','create')+$base)
[void](Write-L03Evidence 'restore-staging-deployment' $deployment)
$deployment.properties.outputs|ConvertTo-Json -Depth 5
