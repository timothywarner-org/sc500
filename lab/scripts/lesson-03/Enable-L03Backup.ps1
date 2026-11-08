<#
.SYNOPSIS
Protects the existing Lesson 3 VM with a bounded daily backup policy.
.DESCRIPTION
Reuses the retained LRS recovery vault, preserves its soft delete and unlocked
immutability, and retains the protected data. Does not create a second VM.
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
[void](Assert-L03Group $script:L03Config.resourceGroup)
$lab=Get-L03Outputs
$name='sc500-l03-daily'
$policyPath=$lab.recoveryVaultId+'/backupPolicies/'+$name+'?api-version=2026-05-01'
$properties=@{
    backupManagementType='AzureIaasVM';policyType='V2';timeZone='UTC';instantRpRetentionRangeInDays=1
    schedulePolicy=@{schedulePolicyType='SimpleSchedulePolicyV2';scheduleRunFrequency='Daily';dailySchedule=@{scheduleRunTimes=@('2026-09-26T23:00:00Z')}}
    retentionPolicy=@{retentionPolicyType='LongTermRetentionPolicy';dailySchedule=@{retentionTimes=@('2026-09-26T23:00:00Z');retentionDuration=@{count=7;durationType='Days'}}}
}
# Preserve a protected policy on reruns. Changes to retention require their own Resource Guard authorization.
$existing=@(Invoke-L03Az @('backup','policy','list','--resource-group',$script:L03Config.resourceGroup,'--vault-name',$lab.recoveryVaultName)|Where-Object name -EQ $name)
if($existing.Count){
    $policy=$existing[0]
    if($policy.properties.policyType -ne 'V2' -or $policy.properties.retentionPolicy.dailySchedule.retentionDuration.count -ne 7){throw 'Existing policy differs from the lab baseline. Review the protected change explicitly.'}
} else {
    # Daily snapshots avoid the enhanced default's four-hour cycle for this small teaching workload.
    $policy=Invoke-L03Arm $policyPath -Method PUT -Body @{properties=$properties}
}
[void](Write-L03Evidence 'backup-policy' $policy)
$already=@(Invoke-L03Az @('backup','item','list','--resource-group',$script:L03Config.resourceGroup,'--vault-name',$lab.recoveryVaultName,'--backup-management-type','AzureIaasVM')|Where-Object {$_.properties.sourceResourceId -ieq $lab.runnerId})
if($already.Count){
    if($already.Count -ne 1 -or $already[0].properties.policyId -ine $policy.id){throw 'Existing protection differs from the Lesson 3 policy.'}
} else {
    $result=Invoke-L03Az @('backup','protection','enable-for-vm','--resource-group',$script:L03Config.resourceGroup,'--vault-name',$lab.recoveryVaultName,'--vm',$lab.runnerId,'--policy-name',$name,'--subscription',$script:L03Config.subscriptionId)
    [void](Write-L03Evidence 'backup-protection-enabled' $result)
}
$items=Invoke-L03Az @('backup','item','list','--resource-group',$script:L03Config.resourceGroup,'--vault-name',$lab.recoveryVaultName,'--backup-management-type','AzureIaasVM','--subscription',$script:L03Config.subscriptionId)
[void](Write-L03Evidence 'backup-protected-items' @{items=@($items)})
$items|Select-Object name,@{n='state';e={$_.properties.protectionState}}|Format-Table
