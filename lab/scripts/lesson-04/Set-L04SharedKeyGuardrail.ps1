<#
.SYNOPSIS
Demonstrates Audit and Deny on the Lesson 4 records account only.
.DESCRIPTION
The assignment stays at one course-owned storage account. Audit is the recording
baseline; Deny protects the repaired state. Probe requires an actual Policy error.
.EXAMPLE
./scripts/lesson-04/Set-L04SharedKeyGuardrail.ps1 -Mode Audit
#>
[CmdletBinding()]
param([ValidateSet('Audit','Deny','Probe','Inspect')][string]$Mode='Inspect')
. (Join-Path $PSScriptRoot 'L04.Common.ps1')
[void](Assert-L04Context)
$lab=Get-L04Outputs
$definition='/providers/Microsoft.Authorization/policyDefinitions/8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54'
$path="$($lab.recordsId)/providers/Microsoft.Authorization/policyAssignments/sc500-l04-no-sharedkey?api-version=2022-06-01"
$resourcePath="$($lab.recordsId)?api-version=2023-05-01"
if($Mode -in 'Audit','Deny') {
    $account=Invoke-L04Arm -Path $resourcePath
    if($Mode -eq 'Deny' -and $account.properties.allowSharedKeyAccess -ne $false){throw 'Disable Shared Key before applying Deny; this policy does not remediate the account.'}
    $body=@{properties=@{displayName='SC500 L04 records Shared Key guardrail';policyDefinitionId=$definition;enforcementMode='Default';parameters=@{effect=@{value=$Mode}};metadata=@{managedBy='sc500-l04-iac';course='SC500';lesson='04'}}}
    [void](Invoke-L04Arm -Path $path -Method PUT -Body $body)
}
$assignment=Invoke-L04Arm -Path $path
if($assignment.properties.policyDefinitionId -ne $definition){throw 'Unexpected definition at the lesson assignment.'}
if($Mode -eq 'Probe') {
    if($assignment.properties.parameters.effect.value -ne 'Deny'){throw 'Probe requires the lesson Deny assignment.'}
    $account=Invoke-L04Arm -Path $resourcePath
    if($account.properties.allowSharedKeyAccess -ne $false){throw 'The probe must start with Shared Key disabled.'}
    $denied=$false
    try { [void](Invoke-L04Arm -Path $resourcePath -Method PATCH -Body @{properties=@{allowSharedKeyAccess=$true}}) }
    catch {
        # A generic 403 could be an RBAC failure; require the policy and its exact assignment.
        $failure=$_.ErrorDetails.Message
        if($failure -match 'RequestDisallowedByPolicy' -and $failure -match 'sc500-l04-no-sharedkey'){$denied=$true}else{throw}
    }
    if(-not $denied){
        # Policy propagation can lag. Immediately close the deliberately attempted key path.
        [void](Invoke-L04Arm -Path $resourcePath -Method PATCH -Body @{properties=@{allowSharedKeyAccess=$false}})
        throw 'Policy has not rejected the request yet. Shared Key was restored to false; wait for propagation before retrying.'
    }
    $after=Invoke-L04Arm -Path $resourcePath
    if($after.properties.allowSharedKeyAccess -ne $false){throw 'Shared Key unexpectedly became enabled.'}
    $result=@{checkedAt=[DateTime]::UtcNow.ToString('o');scope=$lab.recordsId;code='RequestDisallowedByPolicy';sharedKeyAllowed=$false;assignment=$assignment.id}
    [void](Write-L04Evidence 'shared-key-policy-denial' $result)
    $result|ConvertTo-Json
}else{
    $result=@{checkedAt=[DateTime]::UtcNow.ToString('o');scope=$lab.recordsId;effect=$assignment.properties.parameters.effect.value;assignment=$assignment.id}
    [void](Write-L04Evidence 'shared-key-policy-configuration' $result)
    $result|ConvertTo-Json
}
