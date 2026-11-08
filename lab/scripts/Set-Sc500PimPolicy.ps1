<#
.SYNOPSIS
Aligns the maintenance VM's custom-role activation policy with Contoso's one-hour limit.
.DESCRIPTION
Changes only Contoso VM Maintenance at vm-maint-01: one hour, MFA, and justification.
Preserves approval, notifications, assignment duration, other roles, and all directory policies.
Saves the prior policy before changing it and verifies the effective rules afterward.
.EXAMPLE
./scripts/Set-Sc500PimPolicy.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param()
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
$null=Assert-Sc500Context
$null=Assert-Sc500OwnedGroup -Name 'rg-sc500-identity-lab'
$scope='/subscriptions/'+$script:Sc500Config.subscriptionId+'/resourceGroups/rg-sc500-identity-lab/providers/Microsoft.Compute/virtualMachines/vm-maint-01'
$roles=@(Invoke-Sc500Az -Arguments @('role','definition','list','--name','Contoso VM Maintenance','--subscription',$script:Sc500Config.subscriptionId))
if ($roles.Count -ne 1) { throw 'Maintenance custom role did not resolve uniquely.' }
$role=$roles[0]
$assignments=Invoke-Sc500Arm -Path ($scope+'/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01')
$assignment=@($assignments.value | Where-Object { $_.properties.roleDefinitionId -eq $role.id -and $_.properties.scope -ieq $scope })
if ($assignment.Count -ne 1) { throw 'Maintenance policy assignment did not resolve uniquely at the VM.' }
$policyId=$assignment[0].properties.policyId
if (-not $policyId.StartsWith($scope+'/providers/Microsoft.Authorization/roleManagementPolicies/',[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to modify a policy outside the maintenance VM.' }
$path=$policyId+'?api-version=2020-10-01'
$before=Invoke-Sc500Arm -Path $path
$expiration=@($before.properties.rules | Where-Object id -eq 'Expiration_EndUser_Assignment')
$enablement=@($before.properties.rules | Where-Object id -eq 'Enablement_EndUser_Assignment')
if ($expiration.Count -ne 1 -or $enablement.Count -ne 1) { throw 'Expected activation policy rules are missing or ambiguous.' }
$needsChange=$expiration[0].maximumDuration -ne 'PT1H' -or -not $expiration[0].isExpirationRequired -or 'MultiFactorAuthentication' -notin $enablement[0].enabledRules -or 'Justification' -notin $enablement[0].enabledRules
if ($needsChange -and $PSCmdlet.ShouldProcess($policyId,'Require one-hour maximum activation, MFA, and justification')) {
    Write-Sc500Evidence -Name 'pim-maintenance-policy-before' -Value $before | Write-Host
    # PATCH accepts individual rules. Preserve existing requirements rather than replacing the whole policy.
    $expiration[0].maximumDuration='PT1H'
    $expiration[0].isExpirationRequired=$true
    $enablement[0].enabledRules=@(@($enablement[0].enabledRules)+@('MultiFactorAuthentication','Justification') | Select-Object -Unique)
    $null=Invoke-Sc500Arm -Path $path -Method PATCH -Body @{properties=@{rules=@($expiration[0],$enablement[0])}}
}
$after=Invoke-Sc500Arm -Path $path
$effectiveExpiration=@($after.properties.effectiveRules | Where-Object id -eq 'Expiration_EndUser_Assignment')[0]
$effectiveEnablement=@($after.properties.effectiveRules | Where-Object id -eq 'Enablement_EndUser_Assignment')[0]
$passed=$effectiveExpiration.maximumDuration -eq 'PT1H' -and $effectiveExpiration.isExpirationRequired -and 'MultiFactorAuthentication' -in $effectiveEnablement.enabledRules -and 'Justification' -in $effectiveEnablement.enabledRules
Write-Sc500Evidence -Name 'pim-maintenance-policy' -Value @{policy=$after;passed=$passed;whatIf=[bool]$WhatIfPreference;checkedAt=(Get-Date -AsUTC -Format o)} | Write-Host
if (-not $WhatIfPreference -and -not $passed) { throw 'The effective maintenance activation policy does not match the lab requirement.' }
Write-Host "Maintenance policy verified: $passed. Operator activation and MFA behavior still require rehearsal."

