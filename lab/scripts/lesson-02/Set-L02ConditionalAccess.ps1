<#
.SYNOPSIS
Creates report-only Conditional Access policies scoped to Lesson 2 fixtures.
.DESCRIPTION
Requires delegated Policy.Read.All, Policy.ReadWrite.ConditionalAccess and
Policy.Read.AuthenticationMethod permissions and an appropriate Entra administrator role.
Uses interactive device authentication only when -SignIn is supplied. Never enables enforcement.
#>
[CmdletBinding()]
param([switch]$SignIn)
$ErrorActionPreference='Stop'
$courseRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$state=Get-Content (Join-Path $courseRoot '.azure/lesson-02/identity-state.json') -Raw | ConvertFrom-Json
Import-Module Microsoft.Graph.Authentication
if ($SignIn) {
    Connect-MgGraph -TenantId $state.tenantId -Scopes 'Policy.Read.All','Policy.ReadWrite.ConditionalAccess','Policy.Read.AuthenticationMethod','UserAuthenticationMethod.Read.All' -UseDeviceCode -ClientTimeout 900 -ContextScope Process -NoWelcome
}
$context=Get-MgContext
if (-not $context -or $context.TenantId -ne $state.tenantId) {throw 'Run with -SignIn in the SC-500 tenant.'}
$base='https://graph.microsoft.com/v1.0'
$strengths=Invoke-MgGraphRequest GET "$base/identity/conditionalAccess/authenticationStrength/policies"
$strong=@($strengths.value | Where-Object displayName -eq 'Phishing-resistant MFA')
if ($strong.Count -ne 1) {throw 'The built-in phishing-resistant MFA strength could not be resolved uniquely.'}
$methods=Invoke-MgGraphRequest GET "$base/policies/authenticationMethodsPolicy"
$methods | ConvertTo-Json -Depth 40 | Set-Content (Join-Path $courseRoot '.azure/lesson-02/authentication-methods.json')
$policies=@(
    @{displayName='SC500-L02-Garth-PhishingResistant-REPORTONLY';state='enabledForReportingButNotEnforced';conditions=@{clientAppTypes=@('all');users=@{includeUsers=@($state.userId)};applications=@{includeApplications=@($state.apiClientId)}};grantControls=@{operator='OR';authenticationStrength=@{id=$strong[0].id}}},
    @{displayName='SC500-L02-Workload-Risk-REPORTONLY';state='enabledForReportingButNotEnforced';conditions=@{clientAppTypes=@('all');clientApplications=@{includeServicePrincipals=@($state.clientServicePrincipalId)};applications=@{includeApplications=@('All')};servicePrincipalRiskLevels=@('high')};grantControls=@{operator='OR';builtInControls=@('block')}}
)
$existing=@{value=@()}
$next="$base/identity/conditionalAccess/policies"
do {
    # Follow pages so an existing lesson policy is never missed and duplicated.
    $page=Invoke-MgGraphRequest GET $next
    $existing.value+=@($page.value)
    $next=$page.'@odata.nextLink'
} while($next)
$saved=@()
foreach($policy in $policies) {
    $match=@($existing.value | Where-Object displayName -eq $policy.displayName)
    if($match.Count -gt 1){throw 'Duplicate lesson policy names require manual reconciliation.'}
    # Re-runs converge only these named fixtures. Other policies and method settings remain untouched.
    if($match.Count) {
        Invoke-MgGraphRequest PATCH "$base/identity/conditionalAccess/policies/$($match[0].id)" -Body ($policy|ConvertTo-Json -Depth 20) -ContentType application/json
        $saved+=Invoke-MgGraphRequest GET "$base/identity/conditionalAccess/policies/$($match[0].id)"
    } else {
        $saved+=Invoke-MgGraphRequest POST "$base/identity/conditionalAccess/policies" -Body ($policy|ConvertTo-Json -Depth 20) -ContentType application/json
    }
}
$saved|ConvertTo-Json -Depth 40|Set-Content (Join-Path $courseRoot '.azure/lesson-02/conditional-access.json')
$saved|Select-Object displayName,state,id|Format-Table -AutoSize
$registration=Invoke-MgGraphRequest GET "$base/users/$($state.userId)/authentication/methods"
$registration|ConvertTo-Json -Depth 30|Set-Content (Join-Path $courseRoot '.azure/lesson-02/garth-authentication-methods.json')

