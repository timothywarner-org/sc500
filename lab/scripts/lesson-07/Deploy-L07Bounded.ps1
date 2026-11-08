<#
.SYNOPSIS
    Previews, or deploys, the bounded Lesson 7 resource: Azure Firewall Premium.

.DESCRIPTION
    The firewall bills about 1.75 USD an hour from the moment it exists, so it exists only for a
    rehearsal or a take. Creation takes roughly 10 minutes; deploy it before you set up the
    camera. Remove-L07Bounded.ps1 deletes it afterward.

    It attaches to the retained policy and public IP (so the DNAT address never changes) and
    sends every log category to the lesson workspace (names.workspace in config.json) as
    resource-specific AZFW* tables. The retained lab (Deploy-L07Lab.ps1 -Deploy) must exist first.

    Before deploying, this refreshes the policy's DNAT source to your current public IP by
    re-applying the policy in its current state, so the status page is reachable.

.PARAMETER Deploy
    Create the firewall after the preview passes.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Deploy-L07Bounded.ps1 -Deploy
#>
[CmdletBinding()]
param([switch]$Deploy)
. (Join-Path $PSScriptRoot 'L07.Common.ps1')
[void](Assert-L07Context)
$cfg = $script:L07Config
$lab = Get-L07DeploymentOutput
$policy = Invoke-L07Az @('resource', 'show', '--resource-group', $cfg.resourceGroup, '--resource-type', 'Microsoft.Network/firewallPolicies', '--name', $cfg.names.firewallPolicy)
if ("$(Get-L07Value $policy 'tags.managedby')" -ne $cfg.managedBy) { throw "The firewall policy isn't tagged managedby=$($cfg.managedBy). Stopping." }

$values = [ordered]@{
    location           = $cfg.location
    tags               = $cfg.tags
    names              = $cfg.names
    firewallSubnetId   = $lab.firewallSubnetId
    firewallPublicIpId = $lab.firewallPublicIpId
    firewallPolicyId   = $policy.id
    workspaceId        = $lab.workspaceId
}
$parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
$paramsPath = Join-Path $script:L07State 'deployment-firewall.parameters.json'
[ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $paramsPath -Encoding utf8

$base = @('--resource-group', $cfg.resourceGroup, '--name', $cfg.firewallDeploymentName,
    '--template-file', (Join-Path $script:L07Lab 'infra/lesson-07/firewall.bicep'), '--parameters', ('@' + $paramsPath))
$validation = Invoke-L07Az (@('deployment', 'group', 'validate') + $base)
[void](Write-L07Evidence 'firewall-arm-validation' ($validation | Select-Object -ExcludeProperty properties))
$preview = Invoke-L07Az (@('deployment', 'group', 'what-if') + $base + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
[void](Write-L07Evidence 'firewall-what-if' $preview)
$deletes = @($preview.changes | Where-Object changeType -eq 'Delete')
if ($deletes.Count) { throw "What-if contains $($deletes.Count) deletion(s). Nothing was deployed." }
$preview.changes | ForEach-Object { '{0,-10} {1}' -f $_.changeType, ($_.resourceId -replace '^/subscriptions/[^/]+', '') } | Out-Host
if (-not $Deploy) { Write-Host 'Preview only. Re-run with -Deploy to create the firewall (about 1.75 USD an hour).'; return }

# Keep the policy's current state (baseline or enforced) but refresh the operator IP.
$state = if ("$(Get-L07Value $policy 'tags.policystate')" -eq 'Enforced') { 'Enforced' } else { 'Baseline' }
& (Join-Path $PSScriptRoot 'Set-L07Policy.ps1') -State $state

$started = Get-Date
$result = Invoke-L07Az (@('deployment', 'group', 'create') + $base)
[void](Write-L07Evidence 'firewall-deployment' ([ordered]@{ state = $result.properties.provisioningState; duration = $result.properties.duration; outputs = $result.properties.outputs }))
if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success.' }
$ip = $result.properties.outputs.privateIp.value
if ($ip -ne $cfg.addressPlan.hosts.firewall) { Write-Warning "The firewall took $ip, not $($cfg.addressPlan.hosts.firewall). The spoke routes point at the latter; fix config.json and redeploy the retained lab." }
Write-Host ("Firewall deployed in {0:N0} minutes at {1}. It bills until Remove-L07Bounded.ps1 deletes it." -f ((Get-Date) - $started).TotalMinutes, $ip)
