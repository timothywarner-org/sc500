<#
.SYNOPSIS
Creates the dedicated Debra lab user and two secretless application-registration fixtures.
.DESCRIPTION
Never alters an unrelated user or app. Reuses exact SC500-owned fixtures on subsequent runs.
Stores a newly generated bootstrap password as Windows DPAPI-protected PSCredential XML in LOCALAPPDATA.
Assigns only Entra P1/P2 service plans from an existing E5 seat; never buys a license or creates an app secret.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText','',Justification='A cryptographically random bootstrap exists only in memory for the Graph request and is immediately protected using Windows DPAPI; no password literal or plaintext credential file is used.')]
[CmdletBinding()]
param([string]$OperatorUpn='sc500.debra@<your-domain>')
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
$null = Assert-Sc500Context
if (-not $IsWindows) { throw 'Bootstrap credential protection requires Windows DPAPI.' }
$encodedUpn = [uri]::EscapeDataString($OperatorUpn)
$operatorMatches = Invoke-Sc500Graph -Path ('users?$filter='+[uri]::EscapeDataString("userPrincipalName eq '$OperatorUpn'"))
$users = @($operatorMatches.value)
if ($users.Count -gt 1) { throw 'More than one operator matched.' }
$credentialFile = Join-Path $env:LOCALAPPDATA 'SC500/debra-bootstrap.credential.xml'
if ($users.Count -eq 0) {
    # Keep the password out of command arguments, transcripts, project files, and tool output.
    $password = 'Sc5!'+[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
    $secure = ConvertTo-SecureString -String $password -AsPlainText -Force
    New-Item -ItemType Directory -Path (Split-Path $credentialFile -Parent) -Force | Out-Null
    if (Test-Path -LiteralPath $credentialFile) { throw 'A bootstrap credential already exists; inspect its associated user before continuing.' }
    [pscredential]::new($OperatorUpn,$secure) | Export-Clixml -LiteralPath $credentialFile
    $body = @{accountEnabled=$true;displayName='Debra Garcia';givenName='Debra';surname='Garcia';mailNickname='sc500.debra';userPrincipalName=$OperatorUpn;usageLocation='US';department='SC500 Demo';passwordProfile=@{forceChangePasswordNextSignIn=$true;password=$password}}
    $operator = Invoke-Sc500Graph -Path 'users' -Method POST -Body $body
    $password=$null;$body=$null;$secure=$null
} else {
    $operator = Invoke-Sc500Graph -Path ('users/'+$encodedUpn+'?$select=id,displayName,userPrincipalName,department,assignedLicenses')
    if ($operator.department -ne 'SC500 Demo') { throw 'Existing user is not marked as an SC500 demo account.' }
}
$skus = Invoke-Sc500Graph -Path 'subscribedSkus'
$sku = @($skus.value | Where-Object skuPartNumber -eq 'DEVELOPERPACK_E5')
if ($sku.Count -ne 1) { throw 'Expected existing developer E5 entitlement was not found. No license purchase is attempted.' }
$user = Invoke-Sc500Graph -Path ('users/'+$operator.id+'?$select=id,assignedLicenses')
if ($sku[0].skuId -notin @($user.assignedLicenses | ForEach-Object skuId)) {
    if ($sku[0].consumedUnits -ge $sku[0].prepaidUnits.enabled) { throw 'No existing E5 seat is available; no purchase is attempted.' }
    $disabled = @($sku[0].servicePlans | Where-Object servicePlanName -notin @('AAD_PREMIUM','AAD_PREMIUM_P2') | ForEach-Object servicePlanId)
    $null = Invoke-Sc500Graph -Path ('users/'+$operator.id+'/assignLicense') -Method POST -Body @{addLicenses=@(@{skuId=$sku[0].skuId;disabledPlans=$disabled});removeLicenses=@()}
}
$apps = @()
foreach ($name in @('Contoso Maintenance Lab','Contoso Comparison Lab')) {
    $match = Invoke-Sc500Graph -Path ('applications?$filter='+[uri]::EscapeDataString("displayName eq '$name'"))
    if (@($match.value).Count -gt 1) { throw "Ambiguous app name: $name" }
    if (@($match.value).Count -eq 1) {
        $app = $match.value[0]
        if ($app.tags -notcontains 'SC500') { throw "An unrelated application already uses this name: $name" }
    } else {
        $app = Invoke-Sc500Graph -Path 'applications' -Method POST -Body @{displayName=$name;signInAudience='AzureADMyOrg';tags=@('SC500','ContosoServiceHub');description='SC500-owned, secretless directory-role demonstration fixture.'}
    }
    $apps += @{name=$name;objectId=$app.id;appId=$app.appId}
}
$bindings = @{tenantId=$script:Sc500Config.tenantId;operator=@{objectId=$operator.id;upn=$OperatorUpn;displayName='Debra Garcia'};applications=$apps;createdOrVerifiedAt=(Get-Date -AsUTC -Format o);credentialStorage='Windows DPAPI under LOCALAPPDATA/SC500, outside the project';operatorSignInRehearsed=$false}
$bindings | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $script:Sc500Root '.azure/identity-bindings.json')
Write-Sc500Evidence -Name 'identity-fixtures' -Value $bindings | Write-Host
$bindings | ConvertTo-Json -Depth 12
Write-Host 'Debra still needs first sign-in, password change, and any required MFA registration. No tenant authentication policy was weakened.'
