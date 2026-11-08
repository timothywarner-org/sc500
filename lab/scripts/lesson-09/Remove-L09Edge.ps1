<#
.SYNOPSIS
    Deletes the bounded Lesson 9 edge and confirms nothing bounded is left.

.DESCRIPTION
    Deletes, in dependency order: ci-partsworker-prod-eastus2-001, the Front Door profile
    afd-servicehub-prod-001 (with its endpoint, route, origin, and security policy) and its WAF
    policy wafafdservicehubprod001, agw-servicehub-prod-eastus2-001, its WAF policy and public IP,
    then app-servicehub-prod-001 and its B1 plan asp-servicehub-prod-southcentralus-001. Each deletion
    checks the resource's tags first (managedby sc500-l09-iac and a lifecycle that starts
    "bounded"), so a same-named resource from anywhere else is never touched. Safe to run when the
    edge is already gone.

    The group is listed through ARM, never az resource list, and an empty listing stops the script:
    the retained lab always has resources, so an empty answer means the listing failed.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Remove-L09Edge.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L09.Common.ps1')
[void](Assert-L09Context)
$cfg = $script:L09Config
$rg = $cfg.resourceGroup
$n = $cfg.names
$started = Get-Date

# Resource type and name, in the order they have to go.
$all = @(Get-L09GroupResources)
if (-not $all.Count) { throw "Listed no resources in $rg. Check the listing before trusting a cleanup." }
$order = @(
    @('Microsoft.ContainerInstance/containerGroups', $n.containerGroup),
    @('Microsoft.Cdn/profiles', $n.frontDoor),
    @('Microsoft.Network/frontdoorWebApplicationFirewallPolicies', $n.frontDoorWaf),
    @('Microsoft.Network/applicationGateways', $n.gateway),
    @('Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies', $n.gatewayWaf),
    @('Microsoft.Network/publicIPAddresses', $n.gatewayIp),
    @('Microsoft.Web/sites', $n.webApp),
    @('Microsoft.Web/serverFarms', $n.webPlan)
)
foreach ($pair in $order) {
    $type, $name = $pair
    $res = @($all | Where-Object { $_.type -eq $type -and $_.name -eq $name })
    if (-not $res.Count) { continue }
    $r = $res[0]
    if (-not (Test-L09Bounded $r)) { throw "$type/$name isn't tagged as this lesson's bounded part (managedby $($cfg.managedBy), lifecycle bounded). Stopping." }
    Write-Host "Deleting $name."
    Invoke-L09Az -Raw @('resource', 'delete', '--ids', $r.id) | Out-Null
}

# The group listing can trail a finished delete: in rehearsal it still showed the gateway's WAF
# policy after the Network provider reported it gone. Re-read for up to two minutes first.
$left = @()
foreach ($try in 1..6) {
    $now = @(Get-L09GroupResources)
    if (-not $now.Count) { throw "Listed no resources in $rg after the deletes. The retained lab can't be empty; check the listing." }
    $left = @($now | Where-Object { Test-L09Bounded $_ })
    if (-not $left.Count) { break }
    Start-Sleep -Seconds 20
}
$row = [pscustomobject]@{ removedUtc = [DateTime]::UtcNow.ToString('o'); minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1); listed = $now.Count; boundedLeft = @($left | ForEach-Object name) }
[void](Write-L09Evidence 'edge-removed' $row)
if ($left.Count) { throw "Still present: $($row.boundedLeft -join ', ')" }
Write-Host ("Edge removed in {0:N1} minutes. Of {1} resources still listed in {2}, none is bounded." -f $row.minutes, $row.listed, $rg)
