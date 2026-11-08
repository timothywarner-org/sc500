<#
.SYNOPSIS
    Deploys the Lesson 7 firewall policy in its baseline or enforced state.

.DESCRIPTION
    Baseline (CTSO-L07-BASELINE, the default): threat intelligence Alert, IDPS Alert, no
    signature override. Enforced (demo 7.1): threat intelligence Alert and deny, IDPS Alert and
    deny, and signature 2032081 (the HaxerMen test) explicitly set to Deny, the same override
    Microsoft's own test procedure adds.

    Also refreshes the operator's public IP in the DNAT rule's source. If a firewall is attached,
    it picks up the change within a few minutes; the script doesn't wait for that.

.PARAMETER State
    Baseline or Enforced.
.PARAMETER SecretId
    Versioned Key Vault secret ID of the inspection CA. Read from Key Vault when omitted.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Set-L07Policy.ps1 -State Enforced
#>
[CmdletBinding()]
param(
    [ValidateSet('Baseline', 'Enforced')][string]$State = 'Baseline',
    [string]$SecretId
)
. (Join-Path $PSScriptRoot 'L07.Common.ps1')
[void](Assert-L07Context)
$cfg = $script:L07Config
$lab = Get-L07DeploymentOutput

if (-not $SecretId) {
    $cert = Get-L07InspectionCaCertificate -VaultUri $lab.keyVaultUri
    if (-not $cert) { throw 'Key Vault has no inspection CA. Run Deploy-L07Lab.ps1 -Deploy first.' }
    $SecretId = $cert.sid
}
$enforced = $State -eq 'Enforced'
$values = [ordered]@{
    location                = $cfg.location
    tags                    = Get-L07TagSet -Workload 'hub' -Env 'shared' -Extra @{ policystate = $State }
    names                   = $cfg.names
    addressPlan             = $cfg.addressPlan
    ports                   = $cfg.ports
    tests                   = $cfg.tests
    firewallIdentityId      = $lab.firewallIdentityId
    inspectionCaSecretId    = $SecretId
    operatorPublicIp        = Get-L07OperatorIp
    firewallPublicIpAddress = $lab.firewallPublicIpAddress
    threatIntelMode         = if ($enforced) { 'Deny' } else { 'Alert' }
    idpsMode                = if ($enforced) { 'Deny' } else { 'Alert' }
    idpsTestSignatureMode   = if ($enforced) { 'Deny' } else { '' }
}
$parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
$paramsPath = Join-Path $script:L07State 'deployment-policy.parameters.json'
[ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $paramsPath -Encoding utf8

$base = @('--resource-group', $cfg.resourceGroup, '--name', $cfg.policyDeploymentName,
    '--template-file', (Join-Path $script:L07Lab 'infra/lesson-07/policy.bicep'), '--parameters', ('@' + $paramsPath))
$started = Get-Date
for ($i = 1; $i -le 4; $i++) {
    $r = Invoke-L07Az -AllowFailure (@('deployment', 'group', 'create') + $base)
    if ($r.ExitCode -eq 0) { break }
    # A new role assignment on the vault can take minutes to reach the network service that
    # validates the CA secret. Anything else is a real failure.
    if ($i -eq 4 -or $r.Stderr -notmatch '(?i)key ?vault|secret|forbidden|access') { throw "Policy deployment failed: $($r.Stderr.Trim())" }
    Write-Host "Policy can't read the CA secret yet; retrying in 60 seconds ($i of 4)."
    Start-Sleep -Seconds 60
}
$result = $r.Stdout | ConvertFrom-Json -Depth 100
[void](Write-L07Evidence "policy-$($State.ToLowerInvariant())" ([ordered]@{ state = $result.properties.provisioningState; duration = $result.properties.duration; outputs = $result.properties.outputs }))
Write-Host ("Firewall policy is {0}: threat intelligence {1}, IDPS {2} ({3:N0} minutes)." -f $State, $values.threatIntelMode, $values.idpsMode, ((Get-Date) - $started).TotalMinutes)
