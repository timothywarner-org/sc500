<#
.SYNOPSIS
    Deploys the SC-500 Lesson 11 lab: ServiceHub's Foundry implementation (retained) and, on
    request, the AI gateway (bounded, billed by the hour).
.DESCRIPTION
    Retained half (main.bicep, subscription scope), with model, scanning and log meters:
      rg-servicehubai-prod-eastus2 with a Log Analytics workspace, a Foundry resource with key auth
      disabled, the proj-servicehubai-prod-eastus2-001 project, the ctso-customer-ids blocklist, the
      ctso-servicehub-guardrail guardrail, the servicehub-chat gpt-4.1-mini deployment carrying
      that guardrail, resource logs to the workspace, and your Foundry User role on the project.
    Bounded half (gateway.bicep, resource group scope), with -Gateway:
      API Management Basic v2 (0.21 USD an hour), its managed identity's Cognitive Services OpenAI
      User role on the Foundry resource, the servicehub-ai model API with a token budget, the
      servicehub-assistant subscription, the synthetic servicehub-parts API for the agent's tool,
      and gateway and LLM logs to the workspace. Basic v2 usually provisions in 5 to 10 minutes.
    Without -Deploy or -Gateway it runs an ARM what-if for the retained half and changes nothing.
    Reset-L11Lab.ps1 removes the gateway after a take.
.PARAMETER Deploy Create or update the retained half.
.PARAMETER Gateway Create or update the bounded gateway (the retained half must exist).
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Deploy-L11Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Deploy-L11Lab.ps1 -Deploy -Gateway
#>
[CmdletBinding()]
param([switch]$Deploy, [switch]$Gateway)
. (Join-Path $PSScriptRoot 'L11.Common.ps1')
$cfg = $script:L11Config
$started = Get-Date
[void](Assert-L11Context)
$me = Invoke-L11Az -NoSubscription @('ad', 'signed-in-user', 'show', '--query', '{id:id,upn:userPrincipalName}')
[void][IO.Directory]::CreateDirectory($script:L11State)

# ---- Retained half --------------------------------------------------------------------------
$params = @{
    location = @{ value = $cfg.location }; resourceGroupName = @{ value = $cfg.resourceGroup }
    names = @{ value = $cfg.names }; model = @{ value = $cfg.model }; blocklistItems = @{ value = @($cfg.blocklistItems) }
    operatorObjectId = @{ value = $me.id }; roles = @{ value = $cfg.roles }
    managedBy = @{ value = $cfg.managedBy }; baseline = @{ value = $cfg.baseline }
}
$paramFile = Join-Path $script:L11State 'main.parameters.json'
@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $params } |
    ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $paramFile -Encoding utf8
$common = @('--name', $cfg.deploymentName, '--location', $cfg.location, '--template-file', (Join-Path $script:L11Infra 'main.bicep'), '--parameters', "@$paramFile")

if (-not $Deploy -and -not $Gateway) {
    Write-Host '== ARM what-if, retained half (nothing changes)'
    Invoke-L11Az -Raw (@('deployment', 'sub', 'what-if') + $common + @('--result-format', 'ResourceIdOnly', '--no-pretty-print')) | Out-Host
    return
}

if ($Deploy) {
    Write-Host 'Deploying the retained half (Foundry resource, project, guardrail, model deployment). A few minutes.'
    $d = Invoke-L11Az (@('deployment', 'sub', 'create') + $common)
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "Retained deployment ended $($d.properties.provisioningState)." }
    $lab = $d.properties.outputs.lab.value
    Write-Host "Foundry resource $($lab.foundry), project $($lab.project), deployment $($lab.deployment) with guardrail $($lab.guardrail)."
    [void](Write-L11Evidence 'deploy-retained' ([ordered]@{ deployedUtc = [DateTime]::UtcNow.ToString('o'); minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1); lab = $lab }))
}

# ---- Bounded gateway ------------------------------------------------------------------------------
if ($Gateway) {
    $lab = Get-L11Outputs
    $gParams = @{
        location = @{ value = $cfg.location }; names = @{ value = $cfg.names }; gateway = @{ value = $cfg.gateway }
        foundryName = @{ value = $lab.foundry }; workspaceId = @{ value = $lab.workspaceId }
        publisherEmail = @{ value = $cfg.operatorUpn }; roles = @{ value = $cfg.roles }; managedBy = @{ value = $cfg.managedBy }
    }
    $gFile = Join-Path $script:L11State 'gateway.parameters.json'
    @{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $gParams } |
        ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $gFile -Encoding utf8
    $gStart = Get-Date
    Write-Host 'Deploying the AI gateway (API Management Basic v2). Billing starts now: 0.21 USD an hour until Reset-L11Lab.ps1 removes it.'
    $g = Invoke-L11Az @('deployment', 'group', 'create', '--resource-group', $cfg.resourceGroup, '--name', $cfg.gatewayDeploymentName,
                        '--template-file', (Join-Path $script:L11Infra 'gateway.bicep'), '--parameters', "@$gFile")
    if ($g.properties.provisioningState -ne 'Succeeded') { throw "Gateway deployment ended $($g.properties.provisioningState)." }
    $gw = $g.properties.outputs.gateway.value
    Write-Host ("Gateway {0} is up at {1} after {2:N1} minutes." -f $gw.apim, $gw.gatewayUrl, ((Get-Date) - $gStart).TotalMinutes)
    [void](Write-L11Evidence 'deploy-gateway' ([ordered]@{ deployedUtc = [DateTime]::UtcNow.ToString('o'); minutes = [math]::Round(((Get-Date) - $gStart).TotalMinutes, 1); gateway = $gw }))
}
Write-Host ("Done in {0:N1} minutes." -f ((Get-Date) - $started).TotalMinutes)
