<#
.SYNOPSIS
Adds or removes one temporary subscription Reader assignment for the Lesson 1 review.
.DESCRIPTION
The current subscription review excludes resource-group assignments. Reader supplies
a real removable assignment without Contributor's resource-management permissions.
Removing it with this helper is cleanup, never evidence that a review applied a decision.
#>
[CmdletBinding()]
param([ValidateSet('Add','Remove')][string]$State='Remove')
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
[void](Assert-Sc500Context)
[void](Assert-Sc500OwnedGroup 'rg-sc500-lock-lab')
$scope="/subscriptions/$($script:Sc500Config.subscriptionId)"
$assignment="$scope/providers/Microsoft.Authorization/roleAssignments/bfc7358d-dde6-4455-b257-414907e104a7"
$role="/subscriptions/$($script:Sc500Config.subscriptionId)/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
$oid='<your-lab-user-object-id>'
if($State -eq 'Add'){
    # Exact-ID ownership confines cleanup to this demonstration even if other assignments exist.
    [void](Invoke-Sc500Arm -Method PUT -Path "$assignment`?api-version=2022-04-01" -Body @{properties=@{principalId=$oid;principalType='User';roleDefinitionId=$role;description='SC500 L01 temporary direct access-review fixture'}})
    $read=Invoke-Sc500Arm -Path "$assignment`?api-version=2022-04-01"
    if($read.properties.principalId -ne $oid -or $read.properties.roleDefinitionId -ne $role){throw 'Fixture readback mismatch.'}
    Write-Output 'Temporary subscription Reader fixture created. Remove through the review or cleanup before other demos.'
}else{
    try{$read=Invoke-Sc500Arm -Path "$assignment`?api-version=2022-04-01"}catch{if($_.Exception.Response.StatusCode.value__ -eq 404){Write-Output 'Fixture is absent.';return}else{throw}}
    if($read.properties.principalId -ne $oid -or $read.properties.roleDefinitionId -ne $role){throw 'Fixture ownership mismatch.'}
    [void](Invoke-Sc500Arm -Method DELETE -Path "$assignment`?api-version=2022-04-01")
    try{[void](Invoke-Sc500Arm -Path "$assignment`?api-version=2022-04-01");throw 'Fixture still exists.'}catch{if($_.Exception.Response.StatusCode.value__ -ne 404){throw}}
    Write-Output 'Temporary direct assignment removed. This is cleanup, not a review result.'
}
