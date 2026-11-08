<#
.SYNOPSIS
    SC-500 demo 12.3: read what Defender for Cloud covers beyond Azure: AWS and GCP connectors and
    Azure Arc-enabled servers. Read-only.
.DESCRIPTION
    Design goal: no work inside AWS or GCP for this course. Demo 12.3 walks each
    connector wizard in the portal up to the generated CloudFormation template (AWS) and gcloud
    script (GCP) and stops there, so this script's job is the readback: which connectors exist,
    which Defender offerings each one carries, and which Arc machines Defender for Servers covers.
    Today the honest answer is none of either, and the script says so instead of implying coverage.
    Modes (each saves a dated evidence file under lab/.azure/lesson-12/evidence/):
      Connectors  Security connectors (AWS and GCP) on the subscription, with their offerings.
      Hybrid      Azure Arc-enabled machines in ServiceHub's groups, and the Defender for Servers
                  plan that would cover them.
      All         Both.
.PARAMETER Mode Connectors, Hybrid, or All.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12CloudDemo.ps1
#>
[CmdletBinding()]
param([ValidateSet('Connectors', 'Hybrid', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L12.Common.ps1')
$cfg = $script:L12Config
[void](Assert-L12Context)
$sub = "/subscriptions/$($cfg.subscriptionId)"
$ev = [ordered]@{ observedUtc = [DateTime]::UtcNow.ToString('o') }

if ($Mode -in 'Connectors', 'All') {
    Write-Host '== Multicloud connectors (Environment settings)'
    $c = Invoke-L12Rest -Path "$sub/providers/Microsoft.Security/securityConnectors?api-version=2024-08-01-preview"
    $rows = @(@($c.value) | Where-Object { $_ } | ForEach-Object {
        [ordered]@{ name = $_.name; environment = (Get-L12Value $_ 'properties.environmentName'); cloudScope = (Get-L12Value $_ 'properties.hierarchyIdentifier')
                    resourceGroup = ($_.id -split '/')[4]; offerings = @(@(Get-L12Value $_ 'properties.offerings') | Where-Object { $_ } | ForEach-Object { $_.offeringType }) } })
    if ($rows) { $rows | ForEach-Object { Write-Host ("  {0}: {1} scope {2}; offerings {3}" -f $_.name, $_.environment, $_.cloudScope, ($_.offerings -join ', ')) } }
    else { Write-Host '  None. ServiceHub has no AWS account or GCP project connected yet.' }
    $ev.connectors = $rows
}

if ($Mode -in 'Hybrid', 'All') {
    Write-Host '== Azure Arc-enabled servers'
    $arc = Invoke-L12Graph -Query @"
resources
| where type =~ 'microsoft.hybridcompute/machines'
| project name, resourceGroup, status = tostring(properties.status), os = tostring(properties.osName), lastStatusChange = tostring(properties.lastStatusChange)
"@
    if ($arc) { $arc | ForEach-Object { Write-Host ("  {0} ({1}) {2}, {3}" -f $_.name, $_.resourceGroup, $_.status, $_.os) } }
    else { Write-Host '  None. No server outside Azure is connected through Azure Arc in this subscription yet.' }
    $vm = Invoke-L12Rest -Path "$sub/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
    $plan = [ordered]@{ tier = $vm.properties.pricingTier; subPlan = (Get-L12Value $vm 'properties.subPlan') }
    # Free reads as "off" on the Defender plans page; Standard carries a subplan (P1 or P2).
    $label = if ($plan.tier -eq 'Standard') { "On ($($plan.subPlan))" } else { 'Off' }
    Write-Host ("  Defender for Servers on this subscription: {0}. An Arc machine added here would inherit that setting." -f $label)
    $ev.arcMachines = $arc
    $ev.serversPlan = $plan
}
[void](Write-L12Evidence 'cloud-coverage' $ev)
