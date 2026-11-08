<#
.SYNOPSIS
Compares built-in role assignment commands at every Azure RBAC scope.
.DESCRIPTION
Preview prints grounded scope/role/principal commands without granting parent access.
RehearseResourceGroup creates, reads, and removes one Reader grant on the empty lab group.
Custom-role creation is taught separately with Initialize-Sc500DemoRoles.ps1.
#>
[CmdletBinding()]
param([switch]$RehearseResourceGroup)
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
[void](Assert-Sc500Context)
$sub=$script:Sc500Config.subscriptionId
$oid=(Get-Content (Join-Path $script:Sc500Root '.azure/identity-bindings.json') -Raw|ConvertFrom-Json).operator.objectId
$reader='acdd72a7-3385-48ef-bd42-f606fba81ae7'
$scopes=[ordered]@{
    ManagementGroup="/providers/Microsoft.Management/managementGroups/$($script:Sc500Config.tenantId)"
    Subscription="/subscriptions/$sub"
    ResourceGroup="/subscriptions/$sub/resourceGroups/rg-sc500-lock-lab"
    Resource="/subscriptions/$sub/resourceGroups/rg-sc500-identity-lab/providers/Microsoft.Compute/virtualMachines/vm-maint-01"
}
foreach($entry in $scopes.GetEnumerator()){
    Write-Host "`n$($entry.Key): worked command, not submitted"
    Write-Host "az role assignment create --assignee-object-id $oid --assignee-principal-type User --role $reader --scope $($entry.Value) --subscription $sub"
    Write-Host "az role assignment list --assignee $oid --scope $($entry.Value) --include-inherited --subscription $sub"
    Write-Host 'To revoke only the intended grant: az role assignment delete --ids <the exact returned assignment ID>'
}
if($RehearseResourceGroup){
    [void](Assert-Sc500OwnedGroup 'rg-sc500-lock-lab')
    $scope=$scopes.ResourceGroup
    if(@((Invoke-Sc500Arm -Path "$scope/resources?api-version=2021-04-01").value).Count){throw 'This rehearsal requires an empty group.'}
    $path="$scope/providers/Microsoft.Authorization/roleAssignments/$([guid]::NewGuid())?api-version=2022-04-01"
    $created=$false
    try{
        $result=Invoke-Sc500Arm -Path $path -Method PUT -Body @{properties=@{principalId=$oid;principalType='User';roleDefinitionId="/subscriptions/$sub/providers/Microsoft.Authorization/roleDefinitions/$reader";description='Temporary SC500 Reader assignment management example'}}
        $created=$true
        $read=Invoke-Sc500Arm -Path $path
        if($read.properties.principalId -ne $oid -or $read.properties.scope -ne $scope){throw 'Role assignment readback failed.'}
        [void](Write-Sc500Evidence 'builtin-role-scope-create-read' $read)
    }finally{
        # Exact-ID cleanup preserves every unrelated direct, inherited, and PIM grant.
        if($created){[void](Invoke-Sc500Arm -Path $path -Method DELETE)}
    }
    try{[void](Invoke-Sc500Arm -Path $path);throw 'The temporary Reader grant still exists.'}catch{if($_.Exception.Response.StatusCode.value__ -ne 404){throw}}
    [void](Write-Sc500Evidence 'builtin-role-scope-remove' @{assignmentId=$result.id;result='404 after removal';operatorAccessTested=$false})
    Write-Host 'Reader assignment created, read back and removed at the empty group. No operator access claim follows.'
}
