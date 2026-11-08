<#
.SYNOPSIS
Reads, revokes, or restores only Garth's delegated grant to the Lesson 2 API.
.DESCRIPTION
The application role assignment remains visible and unchanged. Revocation changes the
directory grant, not the validity of access tokens already issued. No tokens are printed.
.EXAMPLE
./scripts/lesson-02/Show-L02Consent.ps1 -Action Inspect
.EXAMPLE
./scripts/lesson-02/Show-L02Consent.ps1 -Action Revoke
#>
[CmdletBinding()]
param([ValidateSet('Inspect','Revoke','Restore')][string]$Action='Inspect')
$ErrorActionPreference='Stop'
$courseRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$statePath=Join-Path $courseRoot '.azure/lesson-02/identity-state.json'
$state=Get-Content $statePath -Raw|ConvertFrom-Json
$token=& 'C:/Program Files/Microsoft SDKs/Azure/CLI2/python.exe' -Im azure.cli account get-access-token --tenant $state.tenantId --resource https://graph.microsoft.com --query accessToken -o tsv
if($LASTEXITCODE){throw 'Graph sign-in is required.'}
$headers=@{Authorization="Bearer $token"}
function Read-L02Grant {
    $filter=[Uri]::EscapeDataString("clientId eq '$($state.clientServicePrincipalId)' and principalId eq '$($state.userId)'")
    @((Invoke-RestMethod "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=$filter" -Headers $headers).value | Where-Object { $_.resourceId -eq $state.apiServicePrincipalId -and $_.consentType -eq 'Principal' })
}
$before=@(Read-L02Grant)
if($before.Count -gt 1){throw 'More than one scoped grant exists. Reconcile before mutation.'}
if($Action -eq 'Revoke' -and $before.Count){
    # Guard the exact lab permission as well as all three object IDs before deletion.
    if($before[0].scope -ne 'Maintenance.Read'){throw 'Grant scope changed outside this fixture. Review it before revoking.'}
    Invoke-RestMethod "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($before[0].id)" -Headers $headers -Method Delete
}
if($Action -eq 'Restore' -and -not $before.Count){
    $body=@{clientId=$state.clientServicePrincipalId;resourceId=$state.apiServicePrincipalId;principalId=$state.userId;consentType='Principal';scope='Maintenance.Read'}|ConvertTo-Json
    $restored=Invoke-RestMethod 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -Headers $headers -Method Post -ContentType application/json -Body $body
    $state.delegatedGrantId=$restored.id
    $state|ConvertTo-Json -Depth 20|Set-Content $statePath
}
$after=@(Read-L02Grant)
$roles=@((Invoke-RestMethod "https://graph.microsoft.com/v1.0/servicePrincipals/$($state.clientServicePrincipalId)/appRoleAssignments" -Headers $headers).value | Where-Object resourceId -eq $state.apiServicePrincipalId)
if(($Action -eq 'Revoke' -and $after.Count -ne 0) -or ($Action -eq 'Restore' -and $after.Count -ne 1)){throw 'Grant readback does not match requested state.'}
$evidence=[pscustomobject]@{capturedAt=[DateTime]::UtcNow.ToString('o');action=$Action;delegatedGrants=$after;applicationRoles=$roles;tokenOutput='omitted';scope='Lesson 2 custom API only'}
$evidence|ConvertTo-Json -Depth 30|Set-Content (Join-Path $courseRoot ".azure/lesson-02/evidence/consent-$($Action.ToLowerInvariant()).json")
Write-Output "Delegated grants for Garth: $($after.Count)"
$after|Select-Object consentType,scope,principalId,resourceId|Format-List
Write-Output "Application role assignments to the lab API: $($roles.Count)"
$roles|Select-Object appRoleId,principalId,resourceId|Format-List
