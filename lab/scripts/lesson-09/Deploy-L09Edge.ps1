<#
.SYNOPSIS
    Previews, or deploys, the bounded Lesson 9 edge: the App Service origin, Application Gateway
    WAF_v2, Front Door Standard with its WAF policy, and the Container Instances worker.

.DESCRIPTION
    Default run: ARM validation and what-if, saved as private evidence. Nothing is created.

    With -Deploy, adds to rg-appplatform-prod-eastus2 (every resource tagged with this lesson's
    managedby and lifecycle "bounded: remove after the rehearsal or take"):
      - app-servicehub-prod-<your-name-suffix> on asp-servicehub-prod-southcentralus-001 (B1 Linux, southcentralus,
        because the lab subscription has no App Service plan quota in eastus2): HTTPS only,
        TLS 1.3 minimum, no FTP or basic-auth publishing, default-deny inbound with allow rules for
        this gateway's address and for this Front Door profile (service tag plus X-Azure-FDID header).
      - agw-servicehub-prod-eastus2-001 (WAF_v2) with waf-agw-servicehub-prod-eastus2-001 and its
        public IP pip-agw-servicehub-prod-eastus2-001: Microsoft Default Rule Set 2.1 in Prevention
        mode; firewall and access logs to log-appplatform-prod-eastus2-001.
      - afd-servicehub-prod-001 (Standard) with endpoint fde-servicehub-prod-001 and WAF policy
        wafafdservicehubprod001: one custom rule that blocks scanner paths.
      - ci-partsworker-prod-eastus2-001: a private-IP container group in snet-aci that pulls its
        image with a user-assigned managed identity.

    Registers the Microsoft.Cdn and Microsoft.ContainerInstance resource providers first if the
    subscription hasn't (Microsoft.Cdn was unregistered in the lab subscription on November 1, 2026).
    Registration is a one-time subscription-level step with no cost, and each one is printed.

    Application Gateway takes about 6 minutes; Front Door answered 404 from its own edge for about
    17 minutes after the September deployment finished. Deploy at least 45 minutes before demo 9.3
    and remove it right after.

.PARAMETER Deploy
    Create the edge after the preview passes.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Deploy-L09Edge.ps1 -Deploy

.NOTES
    Cost: about 0.65 USD an hour while it exists. Application Gateway WAF_v2 bills by the hour;
    Front Door Standard's base fee and WAF policy bill monthly, prorated; B1 and the container group
    bill by the hour. Remove-L09Edge.ps1 deletes all of it.
#>
[CmdletBinding()]
param([switch]$Deploy)
. (Join-Path $PSScriptRoot 'L09.Common.ps1')
[void](Assert-L09Context)
$cfg = $script:L09Config
$lab = Get-L09Outputs -Lab Retained

$pending = @('Microsoft.Cdn', 'Microsoft.ContainerInstance' | Where-Object { (Invoke-L09Az @('provider', 'show', '--namespace', $_, '--query', 'registrationState')) -ne 'Registered' })
if ($pending.Count) {
    if (-not $Deploy) { Write-Host "Not registered yet: $($pending -join ', '). -Deploy registers them before creating the edge, so the what-if waits for that." }
    else { Register-L09Provider -Namespace $pending; $pending = @() }
}

# The web app's name is global. It's free, or it's already this lab's.
$mine = @(Get-L09GroupResources | Where-Object { $_.type -eq 'Microsoft.Web/sites' -and $_.name -eq $cfg.names.webApp })
if (-not $mine.Count) {
    $check = Invoke-L09Rest -Method post -Path "/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.Web/checknameavailability?api-version=2023-12-01" -Body @{ name = $cfg.names.webApp; type = 'Microsoft.Web/sites' }
    if (-not $check.nameAvailable) { throw "The web app name $($cfg.names.webApp) is taken ($($check.reason)). Take the next instance number in config.json." }
}

$values = [ordered]@{
    location = $cfg.location; webLocation = $cfg.webLocation; names = $cfg.names; registryServer = $lab.registryServer
    pullIdentityId = $lab.pullIdentityId; workspaceId = $lab.workspaceId; tags = $cfg.tags
}
$parameters = [ordered]@{}; foreach ($k in $values.Keys) { $parameters[$k] = @{ value = $values[$k] } }
[void][IO.Directory]::CreateDirectory($script:L09State)
$paramsPath = Join-Path $script:L09State 'edge.parameters.json'
[ordered]@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $paramsPath -Encoding utf8

$template = Join-Path $script:L09Lab 'infra/lesson-09/edge.bicep'
$base = @('--resource-group', $cfg.resourceGroup, '--name', $cfg.edgeDeploymentName, '--template-file', $template, '--parameters', ('@' + $paramsPath))
if (-not $pending.Count) {
    $validation = Invoke-L09Az (@('deployment', 'group', 'validate') + $base)
    [void](Write-L09Evidence 'edge-validation' ($validation | Select-Object -ExcludeProperty properties))
    $preview = Invoke-L09Az (@('deployment', 'group', 'what-if') + $base + @('--result-format', 'ResourceIdOnly', '--no-pretty-print'))
    [void](Write-L09Evidence 'edge-what-if' $preview)
    $deletes = @($preview.changes | Where-Object changeType -eq 'Delete')
    if ($deletes.Count) { throw "What-if contains $($deletes.Count) deletion(s). Nothing was deployed." }
    $preview.changes | Where-Object changeType -ne 'Ignore' | ForEach-Object { '{0,-10} {1}' -f $_.changeType, ($_.resourceId -replace '^/subscriptions/[^/]+/resourceGroups/[^/]+', '') } | Out-Host
}
if (-not $Deploy) { Write-Host 'Preview only. Re-run with -Deploy to create the Lesson 9 edge.'; return }

$started = Get-Date
$result = Invoke-L09Az (@('deployment', 'group', 'create') + $base)
if ($result.properties.provisioningState -ne 'Succeeded') { throw 'ARM did not report success.' }
$edge = $result.properties.outputs.edge.value
[void](Write-L09Evidence 'edge-deployment' ([ordered]@{ state = $result.properties.provisioningState; duration = $result.properties.duration; webApp = $edge.webApp; webHost = $edge.webHost; gatewayIp = $edge.gatewayIp; frontDoorHost = $edge.frontDoorHost; workerIp = $edge.workerIp }))
$edge | Select-Object webApp, webHost, gatewayIp, frontDoorHost, workerIp | Format-List | Out-Host
Write-Host ("Edge deployed in {0:N0} minutes at {1}. Front Door can take about 17 more minutes to answer from every edge." -f ((Get-Date) - $started).TotalMinutes, (Get-Date).ToString('HH:mm'))
