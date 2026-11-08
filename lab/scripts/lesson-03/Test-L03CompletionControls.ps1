<#
.SYNOPSIS
Reads back the retained Lesson 3 backup, recovery, access and cost controls.
.DESCRIPTION
Configuration and cleanup checks only. Dated service-operation receipts separately
prove restore and authorization behavior; this script never fabricates detection.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
$lab=Get-L03Outputs
$rg=$script:L03Config.resourceGroup
$vault=Invoke-L03Az @('backup','vault','show','--name',$lab.recoveryVaultName,'--resource-group',$rg)
$items=@(Invoke-L03Az @('backup','item','list','--resource-group',$rg,'--vault-name',$lab.recoveryVaultName,'--backup-management-type','AzureIaasVM'))
$item=@($items|Where-Object {$_.properties.sourceResourceId -ieq $lab.runnerId})
$vm=Invoke-L03Az @('vm','show','--resource-group',$rg,'--name',$script:L03Config.vmName,'--show-details')
$canaries=@(Invoke-L03Az @('keyvault','list','--resource-group',$rg)|Where-Object name -Like 'kv-sc500-l03-signal-*')
if($canaries.Count -ne 1){throw 'Expected one synthetic detection vault.'}
$canary=Invoke-L03Az @('keyvault','show','--name',$canaries[0].name,'--resource-group',$rg)
# Read all direct assignments again instead of inferring successful cleanup from DELETE responses.
$bootstrap=@(Invoke-L03Az @('role','assignment','list','--assignee',$lab.bootstrapPrincipalId,'--all'))
$restoreRoles=@(Invoke-L03Az @('role','assignment','list','--assignee',$vault.identity.principalId,'--role','dfce8971-25e3-42e3-ba33-6055438e3080','--all'))
$canaryRoles=@(Invoke-L03Az @('role','assignment','list','--scope',$canary.id)|Where-Object principalId -EQ $lab.runnerPrincipalId)
$restoreFile=Get-ChildItem -LiteralPath $script:L03Evidence -Filter '*-restore-rehearsal.json'|Sort-Object Name -Descending|Select-Object -First 1
if(-not $restoreFile){throw 'Missing completed restore rehearsal.'}
$restore=Get-Content -LiteralPath $restoreFile.FullName -Raw|ConvertFrom-Json
$disk=Invoke-L03Az @('disk','show','--ids',$restore.restoredDiskId)
$nat=@(Invoke-L03Az @('network','nat','gateway','list','--resource-group',$rg))
$ip=@(Invoke-L03Az @('network','public-ip','list','--resource-group',$rg))
$checks=[ordered]@{
    protectedRunner=($item.Count -eq 1 -and $item[0].properties.protectionState -eq 'Protected')
    resourceGuardEnabled=($vault.properties.securitySettings.multiUserAuthorization -eq 'Enabled')
    runnerDeallocated=($vm.powerState -eq 'VM deallocated')
    originalOsDiskPreserved=($vm.storageProfile.osDisk.name -eq 'disk-sc500-l03-runner')
    restoredDiskDetached=($disk.diskState -eq 'Unattached')
    restoredDiskExportDenied=($disk.networkAccessPolicy -eq 'DenyAll' -and $disk.publicNetworkAccess -eq 'Disabled')
    bootstrapTemporaryRolesRemoved=($bootstrap.Count -eq 0)
    vaultRestoreRoleRemoved=($restoreRoles.Count -eq 0)
    canaryReadGrantRemoved=($canaryRoles.Count -eq 0)
    canaryPublicDisabled=($canary.properties.publicNetworkAccess -eq 'Disabled' -and $canary.properties.networkAcls.defaultAction -eq 'Deny')
    temporaryNatRemoved=(@($nat|Where-Object name -EQ 'nat-sc500-l03-egress').Count -eq 0)
    temporaryPublicIpRemoved=(@($ip|Where-Object name -EQ 'pip-sc500-l03-egress').Count -eq 0)
}
$record=@{checkedAt=[DateTime]::UtcNow.ToString('o');checks=$checks;passed=($checks.Values -notcontains $false);detectionClaimMade=$false}
[void](Write-L03Evidence 'final-completion-controls' $record)
$record|ConvertTo-Json -Depth 8
if(-not $record.passed){throw 'One or more Lesson 3 retention or cleanup checks failed.'}
