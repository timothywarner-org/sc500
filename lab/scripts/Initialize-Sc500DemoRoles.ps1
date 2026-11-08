<#
.SYNOPSIS
Prepares bounded Azure and Entra custom roles for Debra's Lesson 1 demonstrations.
.DESCRIPTION
The Azure definition is prepared for VM-scoped PIM eligibility; no standing Azure grant is created.
The directory role is assigned only to its target app registration. Comparison resources receive no grant.
Existing same-name definitions must match the course definition exactly; the script does not silently broaden them.
Use the separate PIM script for eligibility. This script does not grant subscription Contributor or directory administrator roles.
#>
[CmdletBinding()]
param([ValidateSet('All','Azure','Entra')][string]$RoleSystem='All')
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
$null = Assert-Sc500Context
$bindings = Get-Content -Raw -LiteralPath (Join-Path $script:Sc500Root '.azure/identity-bindings.json') | ConvertFrom-Json
$operatorId = $bindings.operator.objectId
$record = [ordered]@{operatorId=$operatorId;verifiedAt=(Get-Date -AsUTC -Format o)}
if ($RoleSystem -in @('All','Azure')) {
    $null = Assert-Sc500OwnedGroup -Name 'rg-sc500-identity-lab'
    $role = Get-Content -Raw -LiteralPath (Join-Path $script:Sc500Root 'infra/roles/vm-maintenance.json') | ConvertFrom-Json
    $role.AssignableScopes = @('/subscriptions/'+$script:Sc500Config.subscriptionId)
    $rolePath = Join-Path $script:Sc500Root '.azure/vm-maintenance.role.json'
    $role | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $rolePath
    $existing = @(Invoke-Sc500Az -Arguments @('role','definition','list','--name',$role.Name,'--subscription',$script:Sc500Config.subscriptionId))
    if ($existing.Count -gt 1) { throw 'Azure custom role name is ambiguous.' }
    if ($existing.Count -eq 0) {
        $definition = Invoke-Sc500Az -Arguments @('role','definition','create','--role-definition',"@$rolePath",'--subscription',$script:Sc500Config.subscriptionId)
    } else {
        $definition = $existing[0]
        if (@($definition.permissions).Count -ne 1 -or $definition.description -ne $role.Description -or @((Compare-Object @($role.Actions) @($definition.permissions[0].actions))).Count -or @($definition.permissions[0].dataActions).Count -or @($definition.permissions[0].notActions).Count -or @($definition.permissions[0].notDataActions).Count) {
            throw 'Existing Azure role differs from the reviewed definition. Inspect it before updating.'
        }
    }
    $target = '/subscriptions/'+$script:Sc500Config.subscriptionId+'/resourceGroups/rg-sc500-identity-lab/providers/Microsoft.Compute/virtualMachines/vm-maint-01'
    $assignments = @(Invoke-Sc500Az -Arguments @('role','assignment','list','--assignee',$operatorId,'--scope',$target,'--subscription',$script:Sc500Config.subscriptionId))
    $assignment = @($assignments | Where-Object { $_.roleDefinitionId -eq $definition.id -and $_.scope -ieq $target })
    # A permanent assignment would bypass activation and survive PIM expiration.
    $record.azure = @{definitionId=$definition.id;existingAssignmentIds=@($assignment | ForEach-Object id);scope=$target;desiredAssignmentType='Eligible';standingGrantCreated=$false}
    Write-Host 'Azure definition verified. Initialize-Sc500Pim.ps1 -RoleSystem Azure provisions eligibility and removes the legacy standing grant.'
}
if ($RoleSystem -in @('All','Entra')) {
    $role = Get-Content -Raw -LiteralPath (Join-Path $script:Sc500Root 'infra/roles/application-basic-editor.json') | ConvertFrom-Json
    $result = Invoke-Sc500Graph -Path ('roleManagement/directory/roleDefinitions?$filter='+[uri]::EscapeDataString("displayName eq '$($role.displayName)'"))
    $definitions = @($result.value)
    if ($definitions.Count -gt 1) { throw 'Entra custom role name is ambiguous.' }
    if ($definitions.Count -eq 0) {
        $definition = Invoke-Sc500Graph -Path 'roleManagement/directory/roleDefinitions' -Method POST -Body $role
    } else {
        $definition = $definitions[0]
        if (@($definition.rolePermissions).Count -ne 1 -or -not $definition.isEnabled -or $definition.description -ne $role.description -or @((Compare-Object @($role.rolePermissions[0].allowedResourceActions) @($definition.rolePermissions[0].allowedResourceActions))).Count) { throw 'Existing Entra custom role differs from the reviewed definition.' }
    }
    $target = @($bindings.applications | Where-Object name -eq 'Contoso Maintenance Lab')[0]
    $scope = '/'+$target.objectId
    $result = Invoke-Sc500Graph -Path ('roleManagement/directory/roleAssignments?$filter='+[uri]::EscapeDataString("principalId eq '$operatorId'"))
    $assignments = @($result.value | Where-Object { $_.roleDefinitionId -eq $definition.id -and $_.directoryScopeId -eq $scope })
    if ($assignments.Count -eq 0) {
        $assignments = @(Invoke-Sc500Graph -Path 'roleManagement/directory/roleAssignments' -Method POST -Body @{principalId=$operatorId;roleDefinitionId=$definition.id;directoryScopeId=$scope})
    }
    $record.entra = @{definitionId=$definition.id;assignmentId=$assignments[0].id;scope=$scope}
}
Write-Sc500Evidence -Name 'custom-role-bindings' -Value $record | Write-Host
$record | ConvertTo-Json -Depth 10
