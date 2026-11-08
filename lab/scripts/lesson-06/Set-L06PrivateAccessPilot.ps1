<#
.SYNOPSIS
    Configures the isolated ServiceHub Private Access application and report-only policy.
.DESCRIPTION
    Uses Microsoft's documented Private Access Graph tutorial (beta APIs) and the existing
    administrator sign-in. One directly assigned pilot user, one IP/port, one connector group.
    It never enables Conditional Access enforcement or changes unrelated applications.
    Connector registration and the human device sign-in are separate operations.
    Reference: https://learn.microsoft.com/en-us/graph/tutorial-entra-private-access
.EXAMPLE
    ./Set-L06PrivateAccessPilot.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
Import-Module Microsoft.Graph.Authentication
Connect-MgGraph -TenantId $script:L06Config.tenantId -Scopes 'NetworkAccess.ReadWrite.All','Application.ReadWrite.All','Policy.ReadWrite.ConditionalAccess','Group.ReadWrite.All','User.Read.All' -ContextScope CurrentUser -NoWelcome
if ((Get-MgContext).TenantId -ne $script:L06Config.tenantId) { throw 'Wrong tenant.' }
function Graph([string]$Method,[string]$Path,$Body=$null) {
    # Serialize structured bodies rather than interpolating JSON into command strings.
    $args=@{Method=$Method;Uri="https://graph.microsoft.com/$Path";OutputType='PSObject'}
    if ($null -ne $Body) {$args.Body=$Body|ConvertTo-Json -Depth 20;$args.ContentType='application/json'}
    Invoke-MgGraphRequest @args
}
$name='CTSO-L06-ServiceHub-PrivateAccess'
$groupName='CTSO-L06-PrivateAccess-Pilot'
$connectorName='CTSO-L06-Connectors'
$policyName='CTSO-L06-ServiceHub-MFA-Compliant-ReportOnly'
$marker='SC-500 Lesson 6 isolated pilot; managedBy=sc500-l06-iac'
$creationPath=Join-Path $script:L06State 'private-access-created-app.json'
$me=Graph GET 'v1.0/me'
if ($me.userPrincipalName -ne '<your-admin-upn>') {throw 'Use the course operator account.'}
$groups=@((Graph GET "v1.0/groups?`$filter=displayName eq '$groupName'").value)
if ($groups.Count -gt 1) {throw 'Duplicate pilot groups.'}
if ($groups.Count) {$group=$groups[0];if ($group.description -ne $marker){throw 'Unowned pilot group.'}}
else {$group=Graph POST 'v1.0/groups' @{displayName=$groupName;description=$marker;mailEnabled=$false;mailNickname='ctso-l06-privateaccess-pilot';securityEnabled=$true}}
$members=@((Graph GET "v1.0/groups/$($group.id)/members").value)
if (@($members | Where-Object id -ne $me.id).Count) {throw 'Pilot has unexpected members; review before widening scope.'}
if ($me.id -notin @($members | ForEach-Object id)) {Graph POST "v1.0/groups/$($group.id)/members/`$ref" @{'@odata.id'="https://graph.microsoft.com/v1.0/directoryObjects/$($me.id)"}|Out-Null}
$apps=@((Graph GET "beta/applications?`$filter=displayName eq '$name'").value)
if ($apps.Count -gt 1) {throw 'Duplicate lesson apps.'}
if ($apps.Count) {
    $app=$apps[0]
    $receipt=if(Test-Path $creationPath){Get-Content $creationPath -Raw|ConvertFrom-Json}else{$null}
    if ($app.description -ne $marker -and ($null -eq $receipt -or $app.id -ne $receipt.id)){throw 'Unowned lesson app.'}
}
else {
    $created=Graph POST 'v1.0/applicationTemplates/8adf8e6e-67b2-4cf2-a259-e3dc5476c621/instantiate' @{displayName=$name}
    $app=$created.application
    $app | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $creationPath -Encoding utf8
    # Directory replication can briefly return 404 after a successful instantiate.
    Start-Sleep -Seconds 15
}
Graph PATCH "beta/applications/$($app.id)" @{description=$marker}|Out-Null
$sp=@((Graph GET "v1.0/servicePrincipals?`$filter=appId eq '$($app.appId)'").value)[0]
Graph PATCH "beta/applications/$($app.id)" @{onPremisesPublishing=@{applicationType='nonwebapp';isAccessibleViaZTNAClient=$true}}|Out-Null
$cgs=@((Graph GET 'beta/onPremisesPublishingProfiles/applicationProxy/connectorGroups').value | Where-Object name -eq $connectorName)
if ($cgs.Count -gt 1) {throw 'Duplicate connector groups.'}
if ($cgs.Count) {$cg=$cgs[0]} else {$cg=Graph POST 'beta/onPremisesPublishingProfiles/applicationProxy/connectorGroups' @{name=$connectorName}}
Graph PUT "beta/applications/$($app.id)/connectorGroup/`$ref" @{'@odata.id'="https://graph.microsoft.com/beta/onPremisesPublishingProfiles/applicationProxy/connectorGroups/$($cg.id)"}|Out-Null
$segmentPath="beta/applications/$($app.id)/onPremisesPublishing/segmentsConfiguration/microsoft.graph.ipSegmentConfiguration/applicationSegments"
$segments=@((Graph GET $segmentPath).value)
if ($segments.Count -gt 1) {throw 'Unexpected additional application segments.'}
# Current portal/Graph readback uses 'ip', despite the Learn beta page saying 'ipAddress'.
# The documented enum returned InvalidJson_BadRequest on 2026-09-26. Keep this lab beta
# compatibility explicit, and validate the live readback instead of trusting a stale example.
$segment=@{destinationHost='10.60.16.4';destinationType='ip';ports=@('8080-8080');protocol='tcp'}
if ($segments.Count) {
    if ($segments[0].destinationHost -ne '10.60.16.4' -or ($segments[0].ports -join ',') -ne '8080-8080' -or $segments[0].protocol -ne 'tcp') {throw 'Existing segment drift requires review.'}
} else {Graph POST $segmentPath $segment | Out-Null}
Graph PATCH "v1.0/servicePrincipals/$($sp.id)" @{appRoleAssignmentRequired=$true}|Out-Null
$role=@($sp.appRoles | Where-Object { $_.displayName -eq 'User' -and $_.isEnabled })[0]
$assignments=@((Graph GET "v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo").value)
if ($group.id -notin @($assignments | ForEach-Object principalId)) {
    Graph POST "v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo" @{principalId=$group.id;resourceId=$sp.id;appRoleId=$role.id}|Out-Null
}
# AND is essential: OR would allow either grant and teach the wrong requirement.
$body=@{displayName=$policyName;state='enabledForReportingButNotEnforced';conditions=@{users=@{includeGroups=@($group.id)};applications=@{includeApplications=@($app.appId)};clientAppTypes=@('all')};grantControls=@{operator='AND';builtInControls=@('mfa','compliantDevice')}}
$policies=@((Graph GET 'v1.0/identity/conditionalAccess/policies').value | Where-Object displayName -eq $policyName)
if ($policies.Count -gt 1){throw 'Duplicate lesson policies.'}
if ($policies.Count) {
    if ($policies[0].state -ne 'enabledForReportingButNotEnforced') {throw 'Policy enforcement changed; refusing to overwrite.'}
    Graph PATCH "v1.0/identity/conditionalAccess/policies/$($policies[0].id)" $body|Out-Null
    $policyId=$policies[0].id
} else {$policyId=(Graph POST 'v1.0/identity/conditionalAccess/policies' $body).id}
$profile=@((Graph GET 'beta/networkAccess/forwardingProfiles').value | Where-Object trafficForwardingType -eq 'private')[0]
$profileSp=Graph GET "v1.0/servicePrincipals/$($profile.servicePrincipal.id)"
$profileAssignments=@((Graph GET "v1.0/servicePrincipals/$($profileSp.id)/appRoleAssignedTo").value)
if (@($profileAssignments | Where-Object principalId -ne $group.id).Count) {throw 'Profile already has other assignments; manual review required.'}
Graph PATCH "v1.0/servicePrincipals/$($profileSp.id)" @{appRoleAssignmentRequired=$true}|Out-Null
if ($group.id -notin @($profileAssignments | ForEach-Object principalId)) {
    $roles=@($profileSp.appRoles | Where-Object { $_.isEnabled -and 'User' -in $_.allowedMemberTypes })
    $roleId=if ($roles.Count -eq 1){$roles[0].id}elseif($roles.Count -eq 0){'00000000-0000-0000-0000-000000000000'}else{throw 'Ambiguous forwarding profile role.'}
    Graph POST "v1.0/servicePrincipals/$($profileSp.id)/appRoleAssignedTo" @{principalId=$group.id;resourceId=$profileSp.id;appRoleId=$roleId}|Out-Null
}
Graph PATCH "beta/networkAccess/forwardingProfiles/$($profile.id)" @{state='enabled'}|Out-Null
$readback=[ordered]@{app=Graph GET "beta/applications/$($app.id)";segment=Graph GET $segmentPath;policy=Graph GET "v1.0/identity/conditionalAccess/policies/$policyId";group=Graph GET "v1.0/groups/$($group.id)";members=Graph GET "v1.0/groups/$($group.id)/members";profile=Graph GET "beta/networkAccess/forwardingProfiles/$($profile.id)";profileServicePrincipal=Graph GET "v1.0/servicePrincipals/$($profileSp.id)";profileAssignments=Graph GET "v1.0/servicePrincipals/$($profileSp.id)/appRoleAssignedTo";connectorGroup=$cg;connectors=Graph GET "beta/onPremisesPublishingProfiles/applicationProxy/connectorGroups/$($cg.id)/members"}
$path=Write-L06Evidence 'private-access-pilot' $readback
[pscustomobject]@{Application=$name;AppId=$app.appId;Group=$groupName;Policy='Report-only: MFA AND compliant device';Evidence=$path;HumanEndToEnd='Not yet tested'}
