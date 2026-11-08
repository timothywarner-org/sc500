<#
.SYNOPSIS
    Deploys the SC-500 Lesson 14 lab: detection and response on Lesson 13's Microsoft Sentinel
    workspace, with no VMs and no standing compute.
.DESCRIPTION
    Design goal: minimal or no cost. Everything here is free at rest or billed per
    use in fractions of a cent.
      (no switch)  ARM what-if. Changes nothing.
      -Deploy      main.bicep creates the response resource group (config.json resourceGroup) with the response playbook (a Consumption
                   logic app with a system-assigned managed identity), its Microsoft Sentinel
                   connection, and the investigation workbook. On Lesson 13's workspace it creates the
                   scheduled analytics rule, two saved hunting queries, and the automation rule.
                   It grants two roles, each at the narrowest scope that works:
                     - Microsoft Sentinel Automation Contributor for Microsoft Sentinel's own service
                       principal (Azure Security Insights) on that resource group, so automation
                       rules can run the playbook;
                     - Microsoft Sentinel Responder for the playbook's managed identity on the
                       workspace, so the playbook can comment on incidents.
    Nothing here is tenant scoped: no Microsoft Graph consent, no tenant setting, no Defender plan.
    Connecting the workspace to the Defender portal and the Microsoft 365 connector are your steps.
    No script signs in as anyone; every call uses your current Azure CLI session.
    Costs: the rule's queries and the workbook are free on Analytics-plan tables; Logic Apps
    Consumption bills each trigger and action execution, a fraction of a cent per playbook run.
.PARAMETER Deploy Create or update the lab.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Deploy-L14Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Deploy-L14Lab.ps1 -Deploy
#>
[CmdletBinding()]
param([switch]$Deploy)
. (Join-Path $PSScriptRoot 'L14.Common.ps1')
$cfg = $script:L14Config
$started = Get-Date
[void](Assert-L14Context)
[void][IO.Directory]::CreateDirectory($script:L14State)
$l13 = Get-L14L13Lab

# Microsoft Sentinel's service principal already exists in any tenant that uses Sentinel. Look it up;
# never create it, because that would be a tenant-level change.
$asi = Invoke-L14Az -NoSubscription -AllowFailure -Raw @('ad', 'sp', 'show', '--id', $cfg.roles.azureSecurityInsightsAppId, '--query', 'id', '--output', 'tsv')
if ($asi.ExitCode -ne 0 -or -not $asi.Stdout.Trim()) { throw 'The Azure Security Insights service principal was not found in this tenant. Stop and ask you; the lab does not create tenant objects.' }
$asiId = $asi.Stdout.Trim()
Write-Host "Azure Security Insights service principal: $asiId"

$params = [ordered]@{
    location = @{ value = $cfg.location }; resourceGroupName = @{ value = $cfg.resourceGroup }
    l13ResourceGroupName = @{ value = $cfg.l13.resourceGroup }; workspaceName = @{ value = $cfg.l13.workspace }
    tags = @{ value = $cfg.tags }; baseline = @{ value = $cfg.baseline }
    securityInsightsPrincipalId = @{ value = $asiId }
    names = @{ value = $cfg.names }; detection = @{ value = $cfg.detection }; roles = @{ value = $cfg.roles }
}
# No secret in these parameters; the temp file only avoids shell quoting of the JSON objects.
$paramFile = Join-Path ([IO.Path]::GetTempPath()) ("sc500-l14-" + [guid]::NewGuid().ToString('N') + '.parameters.json')
try {
    @{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $params } |
        ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $paramFile -Encoding utf8
    $common = @('--name', $cfg.deploymentName, '--location', $cfg.location, '--template-file', (Join-Path $script:L14Infra 'main.bicep'), '--parameters', "@$paramFile")
    if (-not $Deploy) {
        Write-Host '== ARM what-if (nothing changes)'
        Invoke-L14Az -Raw (@('deployment', 'sub', 'what-if') + $common + @('--result-format', 'ResourceIdOnly', '--no-pretty-print')) | Out-Host
        return
    }
    Write-Host 'Deploying the playbook, workbook, analytics rule, hunting queries, and automation rule. Allow a few minutes.'
    $d = $null
    foreach ($attempt in 1..3) {
        $r = Invoke-L14Az -AllowFailure (@('deployment', 'sub', 'create') + $common)
        if ($r.ExitCode -eq 0) { $d = $r.Stdout | ConvertFrom-Json -Depth 100; break }
        # A brand-new role assignment can take a few minutes to reach Microsoft Sentinel, which
        # checks it when the automation rule is saved. Wait and redeploy; ARM skips what's done.
        if ($attempt -lt 3 -and $r.Stderr -match '(?i)(permission|authoriz|playbook|logic app)') {
            Write-Host "  Attempt $attempt stopped on a permission check; waiting 90 seconds for role propagation."
            Start-Sleep -Seconds 90; continue
        }
        throw "Deployment failed: $($r.Stderr.Trim())"
    }
}
finally { Remove-Item -LiteralPath $paramFile -ErrorAction SilentlyContinue }

if ($d.properties.provisioningState -ne 'Succeeded') { throw "Deployment ended $($d.properties.provisioningState)." }
$lab = $d.properties.outputs.lab.value

# The notebook reads its workspace and rule from this private file (no secrets in it).
@{ workspaceCustomerId = $l13.workspaceCustomerId; analyticsRuleId = $cfg.names.analyticsRuleId; table = $cfg.l13.customTable } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:L14State 'notebook-params.json') -Encoding utf8

[void](Write-L14Evidence 'deploy' ([ordered]@{
    deployedUtc = [DateTime]::UtcNow.ToString('o'); minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
    lab = $lab; securityInsightsPrincipalId = $asiId
}))
Write-Host ("Done in {0:N1} minutes. Rule, automation rule, playbook {1}, and workbook are in place." -f ((Get-Date) - $started).TotalMinutes, $lab.playbookName)
