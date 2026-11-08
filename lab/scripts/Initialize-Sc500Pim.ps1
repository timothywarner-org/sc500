<#
.SYNOPSIS
Creates or verifies VM-scoped maintenance eligibility and separate Directory Readers eligibility.
.DESCRIPTION
Creates eligibility only, never an activated role. After read-back proves maintenance eligibility,
removes the former permanent VM grant and obsolete lab Reader eligibility for this operator only.
Directory Readers remains a separate directory role. Run Set-Sc500PimPolicy.ps1 first.
#>
[CmdletBinding()]
param([ValidateSet('All','Azure','Entra')][string]$RoleSystem='All', [switch]$UseGraphPowerShellForEligibility)
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
$null = Assert-Sc500Context
$bindings=Get-Content -Raw -LiteralPath (Join-Path $script:Sc500Root '.azure/identity-bindings.json') | ConvertFrom-Json
$principal=$bindings.operator.objectId
$start=(Get-Date -AsUTC -Format o)
$end=(Get-Date -AsUTC).AddDays(30).ToString('o')
$record=[ordered]@{operatorId=$principal;checkedAt=$start;activationPerformed=$false;policyChanged=$false}
if ($RoleSystem -in @('All','Azure')) {
    $null=Assert-Sc500OwnedGroup -Name 'rg-sc500-identity-lab'
    $groupScope='/subscriptions/'+$script:Sc500Config.subscriptionId+'/resourceGroups/rg-sc500-identity-lab'
    $scope=$groupScope+'/providers/Microsoft.Compute/virtualMachines/vm-maint-01'
    $roles=@(Invoke-Sc500Az -Arguments @('role','definition','list','--name','Contoso VM Maintenance','--subscription',$script:Sc500Config.subscriptionId))
    if ($roles.Count -ne 1) { throw 'Maintenance role did not resolve uniquely. Prepare the reviewed definition first.' }
    $role=$roles[0]
    $expected=Get-Content (Join-Path $script:Sc500Root 'infra/roles/vm-maintenance.json') -Raw | ConvertFrom-Json
    if (@($role.permissions).Count -ne 1 -or @(Compare-Object $expected.Actions $role.permissions[0].actions).Count -or @($role.permissions[0].dataActions).Count -or @($role.permissions[0].notActions).Count) { throw 'Maintenance definition differs from the reviewed operation list.' }
    $query='?api-version=2020-10-01&$filter='+[uri]::EscapeDataString("principalId eq '$principal'")
    $policyAssignments=Invoke-Sc500Arm -Path ($scope+'/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01')
    $policy=@($policyAssignments.value | Where-Object { $_.properties.roleDefinitionId -eq $role.id -and $_.properties.scope -ieq $scope })
    if ($policy.Count -ne 1) { throw 'VM-scoped maintenance policy was not found.' }
    $rules=$policy[0].properties.effectiveRules
    $expiration=@($rules | Where-Object id -eq 'Expiration_EndUser_Assignment')[0]
    $enablement=@($rules | Where-Object id -eq 'Enablement_EndUser_Assignment')[0]
    if ($expiration.maximumDuration -ne 'PT1H' -or -not $expiration.isExpirationRequired -or 'MultiFactorAuthentication' -notin $enablement.enabledRules -or 'Justification' -notin $enablement.enabledRules) { throw 'Apply the reviewed one-hour maintenance policy before migration.' }
    $running=Invoke-Sc500Arm -Path ($scope+'/providers/Microsoft.Authorization/roleAssignmentScheduleInstances'+$query)
    $live=@($running.value | Where-Object { $_.properties.roleDefinitionId -eq $role.id -and $_.properties.scope -ieq $scope -and $_.properties.assignmentType -eq 'Activated' -and [datetime]$_.properties.endDateTime -gt (Get-Date) })
    if ($live.Count) { throw 'A maintenance activation is running. End it before migrating the standing assignment.' }
    $existing=Invoke-Sc500Arm -Path ($scope+'/providers/Microsoft.Authorization/roleEligibilitySchedules'+$query)
    $active=@($existing.value | Where-Object { $_.properties.roleDefinitionId -eq $role.id -and $_.properties.scope -ieq $scope -and $_.properties.status -eq 'Provisioned' -and [datetime]$_.properties.endDateTime -gt (Get-Date) })
    if ($active.Count -eq 0) {
        $body=@{properties=@{principalId=$principal;roleDefinitionId=$role.id;requestType='AdminAssign';justification='SC500-CHG-001: eligible VM maintenance, replacing standing access';scheduleInfo=@{startDateTime=$start;expiration=@{type='AfterDateTime';endDateTime=$end}}}}
        $request=Invoke-Sc500Arm -Path ($scope+'/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/'+[guid]::NewGuid().ToString()+'?api-version=2020-10-01') -Method PUT -Body $body
        Write-Sc500Evidence -Name 'maintenance-eligibility-request' -Value $request | Write-Host
    }
    # Read the provisioned schedule before withdrawing the old access path.
    for ($attempt=0; $attempt -lt 12; $attempt++) {
        $confirmed=Invoke-Sc500Arm -Path ($scope+'/providers/Microsoft.Authorization/roleEligibilitySchedules'+$query)
        $active=@($confirmed.value | Where-Object { $_.properties.roleDefinitionId -eq $role.id -and $_.properties.scope -ieq $scope -and $_.properties.status -eq 'Provisioned' -and [datetime]$_.properties.endDateTime -gt (Get-Date) })
        if ($active.Count -eq 1) { break }
        Start-Sleep -Seconds 5
    }
    if ($active.Count -ne 1) { throw 'Eligibility was not uniquely provisioned. The old standing grant has not been removed.' }
    $record.azure=$active
    $record.azurePolicies=$policy
    $assignments=@(Invoke-Sc500Az @('role','assignment','list','--assignee',$principal,'--scope',$scope,'--subscription',$script:Sc500Config.subscriptionId))
    $legacy=@($assignments | Where-Object { $_.principalId -eq $principal -and $_.roleDefinitionId -eq $role.id -and $_.scope -ieq $scope })
    Write-Sc500Evidence -Name 'maintenance-standing-grant-before-removal' -Value @{assignments=$legacy;eligibility=$active} | Write-Host
    foreach ($assignment in $legacy) { $null=Invoke-Sc500Az @('role','assignment','delete','--ids',$assignment.id,'--subscription',$script:Sc500Config.subscriptionId) }
    $record.removedStandingAssignmentIds=@($legacy | ForEach-Object id)
    # Retire the old read-only exercise so it cannot mask the inactive maintenance boundary.
    $reader=@(Invoke-Sc500Az @('role','definition','list','--name','Reader','--subscription',$script:Sc500Config.subscriptionId))[0]
    $old=Invoke-Sc500Arm -Path ($groupScope+'/providers/Microsoft.Authorization/roleEligibilitySchedules'+$query)
    $oldReader=@($old.value | Where-Object { $_.properties.roleDefinitionId -eq $reader.id -and $_.properties.scope -ieq $groupScope -and $_.properties.status -eq 'Provisioned' -and [datetime]$_.properties.endDateTime -gt (Get-Date) })
    Write-Sc500Evidence -Name 'legacy-reader-eligibility-before-removal' -Value @{schedules=$oldReader} | Write-Host
    foreach ($schedule in $oldReader) {
        $body=@{properties=@{principalId=$principal;roleDefinitionId=$reader.id;requestType='AdminRemove';targetRoleEligibilityScheduleId=$schedule.name;justification='SC500 Lesson 1 now activates the actual maintenance role'}}
        $null=Invoke-Sc500Arm -Path ($groupScope+'/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/'+[guid]::NewGuid().ToString()+'?api-version=2020-10-01') -Method PUT -Body $body
    }
    $record.retiredReaderScheduleIds=@($oldReader | ForEach-Object id)
}
if ($RoleSystem -in @('All','Entra')) {
    $roles=Invoke-Sc500Graph -Path ('roleManagement/directory/roleDefinitions?$filter='+[uri]::EscapeDataString("displayName eq 'Directory Readers'"))
    if (@($roles.value).Count -ne 1) { throw 'Directory Readers role definition was not uniquely resolved.' }
    $roleId=$roles.value[0].id
    $eligibilityPath='roleManagement/directory/roleEligibilitySchedules?$filter='+[uri]::EscapeDataString("principalId eq '$principal'")
    if ($UseGraphPowerShellForEligibility) {
        $context=Get-MgContext
        if ($context.TenantId -ne $script:Sc500Config.tenantId -or $context.Scopes -notcontains 'RoleEligibilitySchedule.ReadWrite.Directory') { throw 'Connect Graph PowerShell to the expected tenant with the delegated PIM scope first.' }
        $existing=Invoke-MgGraphRequest -Method GET -Uri ('https://graph.microsoft.com/v1.0/'+$eligibilityPath) -OutputType PSObject
    } else { $existing=Invoke-Sc500Graph -Path $eligibilityPath }
    $active=@($existing.value | Where-Object { $_.roleDefinitionId -eq $roleId -and $_.directoryScopeId -eq '/' -and ((-not $_.scheduleInfo.expiration.endDateTime) -or [datetime]$_.scheduleInfo.expiration.endDateTime -gt (Get-Date)) })
    if ($active.Count -eq 0) {
        $requestBody=@{action='adminAssign';principalId=$principal;roleDefinitionId=$roleId;directoryScopeId='/';justification='SC500 Lesson 1 separate directory-role activation';scheduleInfo=@{startDateTime=$start;expiration=@{type='afterDateTime';endDateTime=$end}}}
        if ($UseGraphPowerShellForEligibility) {
            $request=Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilityScheduleRequests' -Body ($requestBody | ConvertTo-Json -Depth 15) -ContentType 'application/json' -OutputType PSObject
        } else { $request=Invoke-Sc500Graph -Path 'roleManagement/directory/roleEligibilityScheduleRequests' -Method POST -Body $requestBody }
        $record.entra=$request
    } else { $record.entra=$active }
}
Write-Sc500Evidence -Name 'pim-eligibility' -Value $record | Write-Host
if ($record.Contains('azure')) { Write-Host 'Contoso VM Maintenance eligibility exists at vm-maint-01. The legacy standing grant is removed; verify effective access separately.' }
if ($record.Contains('entra')) { Write-Host 'Directory Readers eligibility exists. See the evidence file for status and dates.' }
Write-Host 'Eligibility is not activation. Rehearse actual policy, approval/MFA, expiration, and fresh-session access before the demo.'
