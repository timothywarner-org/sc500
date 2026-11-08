<#
.SYNOPSIS
Reads deployed L3 controls and reports configuration separately from live request evidence.
.DESCRIPTION
This does not claim a completed backup, restore, MUA operation, or Defender detection.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
[void](Assert-L03Group $script:L03Config.resourceGroup)
$lab=Get-L03Outputs
$vault=Invoke-L03Arm ($lab.vaultId+'?api-version=2026-02-01')
$backup=Invoke-L03Arm ($lab.recoveryVaultId+'?api-version=2026-07-01')
$vm=Invoke-L03Az @('vm','show','--resource-group',$script:L03Config.resourceGroup,'--name',$script:L03Config.vmName,'--show-details','--subscription',$script:L03Config.subscriptionId)
$endpoint=Invoke-L03Arm ($lab.endpointId+'?api-version=2025-09-01')
$disk=Invoke-L03Az @('disk','show','--resource-group',$script:L03Config.resourceGroup,'--name','disk-sc500-l03-runner','--subscription',$script:L03Config.subscriptionId)
# Read grants again after the demo instead of inferring cleanup from a successful guest request.
$assignments=@(Invoke-L03Az @('role','assignment','list','--scope',$lab.vaultId,'--subscription',$script:L03Config.subscriptionId))
$checks=[ordered]@{
    vaultRbac=($vault.properties.enableRbacAuthorization -eq $true)
    vaultSoftDelete=($vault.properties.enableSoftDelete -eq $true)
    vaultPurgeProtection=($vault.properties.enablePurgeProtection -eq $true)
    vaultPublicDisabled=($vault.properties.publicNetworkAccess -eq 'Disabled')
    vaultFirewallDeny=($vault.properties.networkAcls.defaultAction -eq 'Deny')
    vaultTrustedBypassNone=($vault.properties.networkAcls.bypass -eq 'None')
    privateEndpointApproved=(@($endpoint.properties.privateLinkServiceConnections|Where-Object {$_.properties.privateLinkServiceConnectionState.status -eq 'Approved'}).Count -eq 1)
    runnerNoPublicIp=([string]::IsNullOrEmpty($vm.publicIps))
    runnerSecureBoot=($vm.securityProfile.uefiSettings.secureBootEnabled -eq $true)
    runnerVtpm=($vm.securityProfile.uefiSettings.vTpmEnabled -eq $true)
    runnerEncryptionAtHost=($vm.securityProfile.encryptionAtHost -eq $true)
    diskExportDenied=($disk.networkAccessPolicy -eq 'DenyAll')
    diskPublicDisabled=($disk.publicNetworkAccess -eq 'Disabled')
    bootstrapGrantRemoved=(@($assignments|Where-Object principalId -EQ $lab.bootstrapPrincipalId).Count -eq 0)
    backupPublicDisabled=($backup.properties.publicNetworkAccess -eq 'Disabled')
    backupImmutabilityUnlocked=($backup.properties.securitySettings.immutabilitySettings.state -eq 'Unlocked')
    backupSoftDeleteProtected=($backup.properties.securitySettings.softDeleteSettings.softDeleteState -in @('Enabled','AlwaysON'))
}
$record=@{checkedAt=[DateTime]::UtcNow.ToString('o');checks=$checks;runnerPowerState=$vm.powerState;backupSecurity=$backup.properties.securitySettings;liveDataRequestsVerified=$false;backupRestoreVerified=$false}
[void](Write-L03Evidence 'configuration-checks' $record)
foreach($name in $checks.Keys){$label=if($checks[$name]){'PASS'}else{'FAIL'};Write-Host ($label+' '+$name)}
if($checks.Values -contains $false){throw 'At least one deployed configuration check failed.'}
Write-Host 'Configuration checks passed. Consult the separate request evidence for actual authorization behavior.'
