<#
.SYNOPSIS
Bootstraps Debra and Garth with short-lived passes instead of password resets.
.DESCRIPTION
Prepare enables TAP only for the two course identities. Issue retains an existing
usable pass, protects its secret with Windows DPAPI outside the repo, and returns
metadata. ShowPass is an explicit, private operator handoff. Status reads live
methods; it does not mistake registration for a successful lesson sign-in.
The September 27 browser attempt rejected TAP with AADSTS130502 even though
Graph reported EnabledByPolicy. Usable is therefore not a browser readiness claim.
.EXAMPLE
./Set-Sc500Enrollment.ps1 -Mode Prepare
./Set-Sc500Enrollment.ps1 -Mode Issue -Persona Debra -ShowPass
.EXAMPLE
./Set-Sc500Enrollment.ps1 -Mode Status
./Set-Sc500Enrollment.ps1 -Mode Revoke -Persona Debra
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare','Issue','Status','Revoke')][string]$Mode,
    [ValidateSet('Debra','Garth')][string]$Persona,
    [switch]$ShowPass,
    [switch]$SingleUse
)
$ErrorActionPreference='Stop'
if (-not $IsWindows) { throw 'Windows DPAPI is required for the private enrollment credential.' }
if ($Mode -in @('Issue','Revoke') -and -not $Persona) { throw 'Specify one course persona.' }
if ($ShowPass -and $Mode -ne 'Issue') { throw 'ShowPass is supported only for Issue.' }
$root=Split-Path $PSScriptRoot -Parent
$tenant='<your-tenant-id>'
$bindings=Get-Content -LiteralPath (Join-Path $root '.azure/identity-bindings.json') -Raw|ConvertFrom-Json
$l02=Get-Content -LiteralPath (Join-Path $root '.azure/lesson-02/identity-state.json') -Raw|ConvertFrom-Json
$users=@{
    Debra=@{id=$bindings.operator.objectId;upn='sc500.debra@<your-domain>'}
    Garth=@{id=$l02.userId;upn='sc500.garth@<your-domain>'}
}
$evidence=Join-Path $root '.azure/enrollment'
$private=Join-Path $env:LOCALAPPDATA 'SC500/Enrollment'
[void][IO.Directory]::CreateDirectory($evidence)
[void][IO.Directory]::CreateDirectory($private)
Import-Module Microsoft.Graph.Authentication
Connect-MgGraph -TenantId $tenant -Scopes 'Policy.ReadWrite.AuthenticationMethod','UserAuthenticationMethod.ReadWrite.All','Group.ReadWrite.All','User.Read.All','Policy.Read.All','AuditLog.Read.All' -ContextScope CurrentUser -NoWelcome
if ((Get-MgContext).TenantId -ne $tenant -or (Get-MgContext).Account -ne '<your-admin-upn>') { throw 'Use the expected course administrator.' }
function Graph([string]$Path,[string]$Method='GET',$Body=$null) {
    # Never emit request bodies or authentication headers to the rehearsal log.
    $p=@{Method=$Method;Uri="https://graph.microsoft.com/v1.0/$Path";OutputType='Hashtable'}
    if ($null -ne $Body) {$p.Body=$Body|ConvertTo-Json -Depth 25;$p.ContentType='application/json'}
    Invoke-MgGraphRequest @p
}
function Receipt([string]$Name,$Value) {
    $Value|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $evidence ((Get-Date -AsUTC -Format yyyyMMddTHHmmssfffZ)+"-$Name.json"))
}
foreach($name in $users.Keys) {
    $u=Graph ("users/$($users[$name].id)"+'?$select=id,userPrincipalName,accountEnabled,userType')
    if ($u.userPrincipalName -ne $users[$name].upn -or -not $u.accountEnabled -or $u.userType -ne 'Member') {throw "Unexpected binding for $name."}
}
$policyPath='policies/authenticationMethodsPolicy/authenticationMethodConfigurations/TemporaryAccessPass'
if ($Mode -eq 'Prepare') {
    $current=Graph $policyPath
    $allowed=@($users.Values|ForEach-Object {$_.id})
    # Preserve the equivalent direct-user scope if an operator has already selected it.
    if ($current.state -eq 'enabled' -and @($current.includeTargets).Count -eq 2 -and
        -not @($current.includeTargets|Where-Object { $_.targetType -ne 'user' -or $_.id -notin $allowed }).Count -and
        @($current.includeTargets.id|Select-Object -Unique).Count -eq 2) {
        [pscustomobject]@{State=$current.state;Scope='Two direct course users';PasswordsChanged=$false;BrowserEnrollmentVerified=$false}
        return
    }
    $groupName='SC500-L01-L02-Enrollment'
    $marker='SC-500 passwordless enrollment for Debra and Garth only.'
    $groups=@((Graph ("groups?`$filter="+[uri]::EscapeDataString("displayName eq '$groupName'"))).value)
    if ($groups.Count -gt 1) {throw 'Ambiguous enrollment group.'}
    if (-not $groups.Count) {$groups=@(Graph 'groups' POST @{displayName=$groupName;description=$marker;mailEnabled=$false;securityEnabled=$true;mailNickname='sc500-l01-l02-enrollment'})}
    $group=$groups[0]
    if ($group.description -ne $marker -or -not $group.securityEnabled -or $group.isAssignableToRole) {throw 'Enrollment group ownership or type mismatch.'}
    $members=@((Graph "groups/$($group.id)/members").value)
    $allowed=@($users.Values|ForEach-Object {$_.id})
    if (@($members|Where-Object id -notin $allowed).Count) {throw 'Enrollment group contains an unexpected member.'}
    foreach($id in $allowed) {if ($id -notin $members.id) {Graph "groups/$($group.id)/members/`$ref" POST @{'@odata.id'="https://graph.microsoft.com/v1.0/directoryObjects/$id"}|Out-Null}}
    $before=Graph $policyPath
    Receipt 'tap-policy-before' $before
    # The disabled all-users default is not authorization to enable TAP tenant-wide.
    if ($before.state -eq 'disabled') {
        if (@($before.includeTargets|Where-Object id -ne 'all_users').Count) {throw 'Disabled policy has custom targets; inspect before enabling.'}
        $targets=@(@{id=$group.id;targetType='group';isRegistrationRequired=$false})
    } else {
        $targets=@($before.includeTargets)
        if ($group.id -notin $targets.id -and 'all_users' -notin $targets.id) {$targets+=@{id=$group.id;targetType='group';isRegistrationRequired=$false}}
    }
    Graph $policyPath PATCH @{'@odata.type'='#microsoft.graph.temporaryAccessPassAuthenticationMethodConfiguration';state='enabled';includeTargets=$targets}|Out-Null
    $after=Graph $policyPath
    $members=@((Graph "groups/$($group.id)/members").value)
    if ($after.state -ne 'enabled' -or ($group.id -notin $after.includeTargets.id -and 'all_users' -notin $after.includeTargets.id) -or $members.Count -ne 2 -or @($members|Where-Object id -notin $allowed).Count) {throw 'Enrollment scope readback failed.'}
    Receipt 'tap-policy-after' @{policy=$after;groupId=$group.id;members=$members.id}
    [pscustomobject]@{State=$after.state;Group=$groupName;Members=$members.Count;PasswordsChanged=$false}
    return
}
if ($Mode -eq 'Status') {
    $result=foreach($name in @('Debra','Garth')) {
        $methods=@((Graph "users/$($users[$name].id)/authentication/methods").value)
        $registration=Graph "reports/authenticationMethods/userRegistrationDetails/$($users[$name].id)"
        [pscustomobject]@{Persona=$name;Upn=$users[$name].upn;Methods=@($methods|ForEach-Object {$_['@odata.type']});RegistrationReport=$registration}
    }
    Receipt 'registration-status' $result
    $result
    return
}
$user=$users[$Persona]
$path="users/$($user.id)/authentication/temporaryAccessPassMethods"
$existing=@((Graph $path).value)
$credentialPath=Join-Path $private "$Persona.tap.credential.xml"
$metadataPath=Join-Path $private "$Persona.tap.metadata.json"
if ($Mode -eq 'Revoke') {
    if (-not (Test-Path -LiteralPath $metadataPath)) {throw 'No locally issued pass receipt; refusing to revoke an unrelated pass.'}
    $metadata=Get-Content -LiteralPath $metadataPath -Raw|ConvertFrom-Json
    if ($existing.Count -and $existing[0].id -ne $metadata.Id) {throw 'The live pass differs from the locally issued pass.'}
    if ($existing.Count) {Graph "$path/$($metadata.Id)" DELETE|Out-Null}
    if (@((Graph $path).value).Count) {throw 'Pass revocation readback failed.'}
    Remove-Item -LiteralPath $credentialPath,$metadataPath -ErrorAction SilentlyContinue
    Receipt 'tap-revoked' @{persona=$Persona;id=$metadata.Id}
    [pscustomobject]@{Persona=$Persona;PassRevoked=$true}
    return
}
if ($existing.Count -and $existing[0].isUsable) {
    if (-not (Test-Path -LiteralPath $credentialPath) -or -not (Test-Path -LiteralPath $metadataPath)) {throw 'Usable pass already exists; do not silently replace it.'}
    $metadata=Get-Content -LiteralPath $metadataPath -Raw|ConvertFrom-Json
    if ($metadata.Id -ne $existing[0].id) {throw 'The stored pass does not match the live pass.'}
} else {
    $policy=Graph $policyPath
    if ($policy.state -ne 'enabled' -or $policy.minimumLifetimeInMinutes -gt 60 -or $policy.maximumLifetimeInMinutes -lt 60) {throw 'Prepare a policy permitting a 60-minute pass first.'}
    # Multi-use avoids the single-use 10-minute enrollment race; the pass still expires in one hour.
    $pass=Graph $path POST @{lifetimeInMinutes=60;isUsableOnce=([bool]$policy.isUsableOnce -or [bool]$SingleUse)}
    if (-not $pass.temporaryAccessPass) {throw 'Graph did not return the enrollment secret.'}
    [pscredential]::new($user.upn,($pass.temporaryAccessPass|ConvertTo-SecureString -AsPlainText -Force))|Export-Clixml -LiteralPath $credentialPath
    $metadata=@{Persona=$Persona;Upn=$user.upn;Id=$pass.id;ExpiresUtc=([datetime]$pass.startDateTime).AddMinutes($pass.lifetimeInMinutes).ToUniversalTime().ToString('o')}
    $metadata|ConvertTo-Json|Set-Content -LiteralPath $metadataPath
    $pass=$null
    Receipt 'tap-issued' $metadata
}
$live=@((Graph $path).value)
if ($live.Count -ne 1 -or -not $live[0].isUsable) {throw 'Issued pass is not usable in readback.'}
$output=[ordered]@{Persona=$Persona;Upn=$user.upn;ExpiresUtc=$metadata.ExpiresUtc;Usable=$live[0].isUsable;BrowserEnrollmentVerified=$false}
if ($ShowPass) {$output.TemporaryAccessPass=(Import-Clixml -LiteralPath $credentialPath).GetNetworkCredential().Password}
[pscustomobject]$output
