<#
.SYNOPSIS
Enables device-bound passkeys for the isolated Garth pilot group.
.DESCRIPTION
Preserves existing passkey profiles and restrictions. Refuses to replace an enabled
tenant policy with a narrower scope. Registration and sign-in still require you.
#>
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module Microsoft.Graph.Authentication
Connect-MgGraph -TenantId '<your-tenant-id>' -Scopes 'Policy.ReadWrite.AuthenticationMethod','Group.ReadWrite.All','User.Read.All' -ContextScope CurrentUser -NoWelcome
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$state=Get-Content (Join-Path $root '.azure/lesson-02/identity-state.json') -Raw | ConvertFrom-Json
$uri='https://graph.microsoft.com/v1.0'
$name='SC500-L02-Passkey-Pilot'
$group=@((Invoke-MgGraphRequest GET "$uri/groups?`$filter=displayName eq '$name'").value)
if($group.Count -gt 1){throw 'Ambiguous pilot group.'}
if(-not $group.Count){
    $body=@{displayName=$name;description='Isolated SC-500 Lesson 2 Garth passkey pilot';mailEnabled=$false;mailNickname='sc500-l02-passkey-pilot';securityEnabled=$true}
    $group=@(Invoke-MgGraphRequest POST "$uri/groups" -Body ($body|ConvertTo-Json) -ContentType 'application/json')
}
$id=$group[0].id
$members=@((Invoke-MgGraphRequest GET "$uri/groups/$id/members?`$select=id").value)
if(@($members|Where-Object id -ne $state.userId).Count){throw 'Unexpected pilot member. Refusing to expand authentication access.'}
if(-not $members.Count){
    Invoke-MgGraphRequest POST "$uri/groups/$id/members/`$ref" -Body (@{'@odata.id'="$uri/directoryObjects/$($state.userId)"}|ConvertTo-Json) -ContentType 'application/json'|Out-Null
}
$path="$uri/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/Fido2"
$before=Invoke-MgGraphRequest GET $path
if($before.state -eq 'enabled' -and @($before.includeTargets|Where-Object id -ne $id).Count){throw 'An enabled policy targets other groups. Preserve it and review before changing scope.'}
$target=@{'@odata.type'='#microsoft.graph.passkeyAuthenticationMethodTarget';id=$id;targetType='group';isRegistrationRequired=$false;allowedPasskeyProfiles=@($before.defaultPasskeyProfile)}
# The old all_users target belonged to a disabled method. Activating that target would enable the entire tenant.
$body=@{'@odata.type'='#microsoft.graph.fido2AuthenticationMethodConfiguration';state='enabled';includeTargets=@($target);passkeyProfiles=@($before.passkeyProfiles)}
Invoke-MgGraphRequest PATCH $path -Body ($body|ConvertTo-Json -Depth 12) -ContentType 'application/json'|Out-Null
$after=Invoke-MgGraphRequest GET $path
if($after.state -ne 'enabled' -or @($after.includeTargets).Count -ne 1 -or $after.includeTargets[0].id -ne $id){throw 'Pilot policy readback failed.'}
$evidence=@{checkedAt=[datetime]::UtcNow.ToString('o');pilotGroupId=$id;memberId=$state.userId;before=$before;after=$after;registrationVerified=$false}
$folder=Join-Path $root '.azure/lesson-02/evidence'
New-Item -ItemType Directory -Force $folder|Out-Null
$evidence|ConvertTo-Json -Depth 20|Set-Content (Join-Path $folder ((Get-Date -AsUTC -Format yyyyMMddTHHmmssfffZ)+'-passkey-pilot.json'))
[pscustomobject]@{method=$after.state;pilot=$name;member=$state.userPrincipalName;groupId=$id;registration='Human action pending'}|Format-List
