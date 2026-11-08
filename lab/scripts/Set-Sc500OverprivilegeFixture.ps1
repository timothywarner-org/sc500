<#
.SYNOPSIS
Adds, inspects, or removes an isolated group-based overprivilege fixture for Lesson 1.4.
.DESCRIPTION
Contributor is limited to the two SC500 VM groups. No subscription-wide grant is created.
The group exists for reuse; Remove revokes its lab assignments and Debra's membership, not the resources.
A completed access review is separate evidence and is not simulated by this script.
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Status','Add','Remove')][string]$State='Status')
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
$null=Assert-Sc500Context
$bindings=Get-Content -Raw -LiteralPath (Join-Path $script:Sc500Root '.azure/identity-bindings.json') | ConvertFrom-Json
$fixtureGroups=@('rg-sc500-identity-lab','rg-sc500-comparison-lab')
# Check every scope before creating membership or grants, so a mismatch leaves no partial fault fixture.
foreach ($rg in $fixtureGroups) { $null=Assert-Sc500OwnedGroup -Name $rg }
$name='SC500 Contoso Legacy Operators'
$found=Invoke-Sc500Graph -Path ('groups?$filter='+[uri]::EscapeDataString("displayName eq '$name'"))
if (@($found.value).Count -gt 1) { throw 'Ambiguous lab group name.' }
$group=$null
if (@($found.value).Count -eq 1) {
    $group=$found.value[0]
    if ($group.description -ne 'SC500-owned overprivilege fixture; lab resource groups only.') { throw 'Group is not the SC500-owned fixture.' }
} elseif ($State -eq 'Add' -and $PSCmdlet.ShouldProcess($name,'Create lab security group')) {
    $group=Invoke-Sc500Graph -Path 'groups' -Method POST -Body @{displayName=$name;description='SC500-owned overprivilege fixture; lab resource groups only.';mailEnabled=$false;mailNickname='sc500-legacy-operators';securityEnabled=$true}
}
if ($null -eq $group) { Write-Host 'No overprivilege group exists; no changes made.'; return }
$membership=Invoke-Sc500Graph -Path ('groups/'+$group.id+'/members?$select=id')
$memberIds=@($membership.value | ForEach-Object id)
if ($State -eq 'Add' -and $bindings.operator.objectId -notin $memberIds -and $PSCmdlet.ShouldProcess($name,'Add Debra to lab group')) {
    $null=Invoke-Sc500Graph -Path ('groups/'+$group.id+'/members/$ref') -Method POST -Body @{'@odata.id'=('https://graph.microsoft.com/v1.0/directoryObjects/'+$bindings.operator.objectId)}
}
$evidence=@()
foreach ($rg in $fixtureGroups) {
    $null=Assert-Sc500OwnedGroup -Name $rg
    $scope='/subscriptions/'+$script:Sc500Config.subscriptionId+'/resourceGroups/'+$rg
    $assignments=@(Invoke-Sc500Az -Arguments @('role','assignment','list','--assignee',$group.id,'--scope',$scope,'--subscription',$script:Sc500Config.subscriptionId))
    $owned=@($assignments | Where-Object { $_.scope -ieq $scope -and $_.roleDefinitionName -eq 'Contributor' })
    if ($State -eq 'Add' -and $owned.Count -eq 0 -and $PSCmdlet.ShouldProcess($scope,'Assign Contributor to SC500 legacy group')) {
        $owned=@(Invoke-Sc500Az -Arguments @('role','assignment','create','--assignee-object-id',$group.id,'--assignee-principal-type','Group','--role','Contributor','--scope',$scope,'--subscription',$script:Sc500Config.subscriptionId))
    }
    if ($State -eq 'Remove') {
        foreach ($assignment in $owned) {
            if ($PSCmdlet.ShouldProcess($assignment.id,'Remove lab Contributor assignment')) { $null=Invoke-Sc500Az -Arguments @('role','assignment','delete','--ids',$assignment.id,'--subscription',$script:Sc500Config.subscriptionId) }
        }
    }
    $current=@(Invoke-Sc500Az -Arguments @('role','assignment','list','--assignee',$group.id,'--scope',$scope,'--subscription',$script:Sc500Config.subscriptionId))
    $evidence+=@{scope=$scope;assignmentIds=@($current | Where-Object { $_.scope -ieq $scope -and $_.roleDefinitionName -eq 'Contributor' } | ForEach-Object id)}
}
if ($State -eq 'Remove' -and $bindings.operator.objectId -in $memberIds -and $PSCmdlet.ShouldProcess($name,'Remove Debra membership')) {
    # $ref is mandatory: delete the membership reference, never the directory user.
    $null=Invoke-Sc500Graph -Path ('groups/'+$group.id+'/members/'+$bindings.operator.objectId+'/$ref') -Method DELETE
}
$currentMembership=Invoke-Sc500Graph -Path ('groups/'+$group.id+'/members?$select=id')
Write-Sc500Evidence -Name 'overprivilege-fixture' -Value @{state=$State;groupId=$group.id;scopeRecords=$evidence;operatorIsMember=($bindings.operator.objectId -in @($currentMembership.value | ForEach-Object id));accessReviewCompleted=$false;whatIf=[bool]$WhatIfPreference} | Write-Host
Write-Host "Fixture operation: $State. No subscription-wide grant or resource deletion was performed."
