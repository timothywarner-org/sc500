<#
.SYNOPSIS
Reads the real restored Contoso file from a temporary read-only disk attachment.
.DESCRIPTION
Selects the disk by Azure Backup's exact restore-job tag, preserves the original OS
disk, detaches the restored copy afterward, and removes the restore identity grant.
Retains the recovered disk as inexpensive recording evidence. Never restores over the VM.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
[void](Assert-L03Group $script:L03Config.resourceGroup)
$lab=Get-L03Outputs
$receipt=Get-ChildItem -LiteralPath $script:L03Evidence -Filter '*-restore-started.json'|Sort-Object Name -Descending|Select-Object -First 1
if(-not $receipt){throw 'A recorded restore job is required.'}
$restore=Get-Content -LiteralPath $receipt.FullName -Raw|ConvertFrom-Json -Depth 50
$job=Invoke-L03Az @('backup','job','show','--resource-group',$script:L03Config.resourceGroup,'--vault-name',$lab.recoveryVaultName,'--name',$restore.job.name)
if($job.properties.status -ne 'Completed'){throw ('Restore job is '+$job.properties.status+'. No successful restore claim is possible yet.')}
[void](Write-L03Evidence 'restore-completed' $job)
$disks=@(Invoke-L03Az @('disk','list','--resource-group',$script:L03Config.resourceGroup))
$matches=@($disks|Where-Object {$_.tags -and $_.tags.PSObject.Properties['RSVaultBackup'] -and $_.tags.RSVaultBackup -eq $job.name})
if($matches.Count -ne 1){throw 'Expected exactly one disk tagged by the completed restore job.'}
$disk=$matches[0]
if($disk.tags.managedBy -ne 'sc500-l03-iac' -or $disk.creationData.createOption -ne 'Restore' -or $disk.diskState -ne 'Unattached'){throw 'Recovery disk provenance or attachment state does not match.'}
$vm=Invoke-L03Az @('vm','show','--ids',$lab.runnerId)
$original=$vm.storageProfile.osDisk.managedDisk.id
if($original -ieq $disk.id -or @($vm.storageProfile.dataDisks|Where-Object lun -EQ 10).Count){throw 'LUN 10 must be free and the original OS disk must be distinct.'}
$attached=$false
$passed=$false
try {
    # Restore should inherit restrictions. Enforce the lab boundary before attachment if it did not.
    if($disk.networkAccessPolicy -ne 'DenyAll' -or $disk.publicNetworkAccess -ne 'Disabled'){
        $disk=Invoke-L03Az @('disk','update','--ids',$disk.id,'--network-access-policy','DenyAll','--public-network-access','Disabled')
    }
    [void](Invoke-L03Az @('vm','disk','attach','--resource-group',$script:L03Config.resourceGroup,'--vm-name',$lab.runnerName,'--name',$disk.id,'--lun','10','--caching','None'))
    $attached=$true
    & (Join-Path $PSScriptRoot 'Invoke-L03Guest.ps1') -SourcePath (Join-Path $PSScriptRoot 'verify_restored_record.py')
    $passed=$true
} finally {
    try {
        if($attached){[void](Invoke-L03Az @('vm','disk','detach','--resource-group',$script:L03Config.resourceGroup,'--vm-name',$lab.runnerName,'--name',$disk.name))}
    } finally {
        if($restore.createdGrantId){[void](Invoke-L03Az @('role','assignment','delete','--ids',$restore.createdGrantId))}
    }
    $after=Invoke-L03Az @('vm','show','--ids',$lab.runnerId)
    $restored=Invoke-L03Az @('disk','show','--ids',$disk.id)
    $baseline=($after.storageProfile.osDisk.managedDisk.id -ieq $original -and $restored.diskState -eq 'Unattached')
    [void](Write-L03Evidence 'restore-rehearsal' @{passed=$passed;originalOsDiskUnchanged=($after.storageProfile.osDisk.managedDisk.id -ieq $original);restoredDiskId=$disk.id;restoredDiskDetached=($restored.diskState -eq 'Unattached');restoreGrantRemoved=$true;jobId=$job.name})
    if(-not $baseline){throw 'The restore attachment did not return to the retained baseline.'}
}
Write-Host 'Restored Contoso record read and hash matched. Original OS disk preserved. Recovery disk detached; restore grant removed.'
