<#
.SYNOPSIS
Restores the newest Lesson 3 VM recovery point to a separate managed disk.
.DESCRIPTION
Uses the vault system identity and firewall-restricted staging storage. The original
VM and disk are never replaced. A private receipt preserves the asynchronous job and
the temporary role assignment for cleanup after the service completes.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
[void](Assert-L03Group $script:L03Config.resourceGroup)
$lab=Get-L03Outputs
$base=@('--resource-group',$script:L03Config.resourceGroup,'--vault-name',$lab.recoveryVaultName,'--subscription',$script:L03Config.subscriptionId)
$jobs=@(Invoke-L03Az (@('backup','job','list')+$base))
if(@($jobs|Where-Object {$_.properties.operation -eq 'Restore' -and $_.properties.status -eq 'InProgress'}).Count){throw 'A restore is already running. Inspect its receipt before submitting another.'}
$items=@(Invoke-L03Az (@('backup','item','list')+$base+@('--backup-management-type','AzureIaasVM')))
$item=@($items|Where-Object {$_.properties.sourceResourceId -ieq $lab.runnerId})
if($item.Count -ne 1){throw 'Exactly one protected Lesson 3 runner is required.'}
$container=($item[0].id -split '/protectionContainers/')[1].Split('/')[0]
$points=@(Invoke-L03Az (@('backup','recoverypoint','list')+$base+@('--container-name',$container,'--item-name',$item[0].name)))
if(-not $points.Count){throw 'No recovery point exists yet. A submitted backup is not recovery evidence.'}
$point=$points|Sort-Object {$_.properties.recoveryPointTime} -Descending|Select-Object -First 1
$storageDeployment=Invoke-L03Az @('deployment','group','show','--resource-group',$script:L03Config.resourceGroup,'--name','sc500-l03-restore-staging')
if($storageDeployment.properties.provisioningState -ne 'Succeeded'){throw 'Restore staging deployment must succeed first.'}
$storageId=$storageDeployment.properties.outputs.storageId.value
$storage=Invoke-L03Az @('storage','account','show','--ids',$storageId)
if($storage.tags.managedBy -ne 'sc500-l03-iac' -or $storage.networkRuleSet.defaultAction -ne 'Deny' -or $storage.allowBlobPublicAccess){throw 'Unexpected staging ownership or network configuration.'}
$vault=Invoke-L03Az (@('backup','vault','show','--name',$lab.recoveryVaultName,'--resource-group',$script:L03Config.resourceGroup))
$rgScope='/subscriptions/'+$script:L03Config.subscriptionId+'/resourceGroups/'+$script:L03Config.resourceGroup
$role='dfce8971-25e3-42e3-ba33-6055438e3080' # The documented VM Restore Operator role supports firewall-protected staging through the vault identity.
$existing=@(Invoke-L03Az @('role','assignment','list','--assignee',$vault.identity.principalId,'--scope',$rgScope,'--role',$role))
$grant=$null
$accepted=$false
try {
    if(-not $existing.Count){$grant=Invoke-L03Az @('role','assignment','create','--assignee-object-id',$vault.identity.principalId,'--assignee-principal-type','ServicePrincipal','--role',$role,'--scope',$rgScope)}
    # Record before submission so an interrupted client still has an exact cleanup identifier.
    [void](Write-L03Evidence 'restore-authorization' @{principalId=$vault.identity.principalId;createdGrantId=if($grant){$grant.id}else{$null};scope=$rgScope})
    # The CLI permits disk-access-option only when the recovery point actually contains private disk access.
    $diskAccessArgs=if($point.properties.isPrivateAccessEnabledOnAnyDisk){@('--disk-access-option','SameAsOnSourceDisks')}else{@()}
    $job=Invoke-L03Az (@('backup','restore','restore-disks')+$base+@('--container-name',$container,'--item-name',$item[0].name,'--rp-name',$point.name,'--storage-account',$storageId,'--target-resource-group',$script:L03Config.resourceGroup,'--restore-only-osdisk','true','--mi-system-assigned')+$diskAccessArgs)
    $accepted=$true
    [void](Write-L03Evidence 'restore-started' @{job=$job;recoveryPoint=$point;createdGrantId=if($grant){$grant.id}else{$null};originalDiskPreserved=$true})
    $job|Select-Object name,properties|ConvertTo-Json -Depth 15
} finally {
    # Azure needs this identity until the asynchronous job ends. The completion script removes it.
    if($grant -and -not $accepted){[void](Invoke-L03Az @('role','assignment','delete','--ids',$grant.id))}
}
