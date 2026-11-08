<#
.SYNOPSIS
    Checks, or refreshes, every Lesson 9 allow list that names the operator's public IP.

.DESCRIPTION
    Three retained resources let in only the operator's workstation, by its public IPv4 address as
    it was when they were deployed:
      - aks-servicehub-prod-eastus2-001: the API server's authorized IP ranges. Every kubectl call
        (through the runCommand API) and the portal's Kubernetes resources view need it.
      - ca-status-prod-001: the container app's ingress allow list (rule allow-operator).
      - logic-intake-prod-eastus2-001: the trigger's allowed caller addresses and the run-history
        content's allowed addresses.
    Nothing in the bounded edge names the operator's IP (the web origin allows only the gateway's
    address and this Front Door profile), and the function and API Management don't filter by IP.

      Default  Read-only: prints your current public IP's match against each of the three, in
               words, and saves the result as private evidence. Changes nothing.
      -Apply   Sets each mismatched one to your current IP (/32), then reads all three back and
               stops on a mismatch. AKS must be running for its update (a few minutes); the other
               two take seconds.

    Run it after an overnight IP change (a home router or ISP lease renewal), before the take.

.PARAMETER Apply
    Update the mismatched allow lists to the current public IP.

.PARAMETER Force
    With -Apply, rewrite all three even when they already match (a rehearsal of the refresh path).

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Set-L09OperatorIp.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Set-L09OperatorIp.ps1 -Apply

.NOTES
    Rehearsed with -Apply -Force on November 1, 2026: all three rewritten and read back.
#>
[CmdletBinding()]
param([switch]$Apply, [switch]$Force)
. (Join-Path $PSScriptRoot 'L09.Common.ps1')
[void](Assert-L09Context)
$cfg = $script:L09Config
$n = $cfg.names
$cidr = "$(Get-L09OperatorIp)/32"
$caId = Get-L09ResourceId 'Microsoft.App/containerApps' $n.containerApp
$logicId = Get-L09ResourceId 'Microsoft.Logic/workflows' $n.logicApp

function Get-IpState {
    $aks = Invoke-L09Az @('aks', 'show', '--resource-group', $cfg.resourceGroup, '--name', $n.aks)
    $ranges = @(Get-L09Value $aks 'apiServerAccessProfile.authorizedIpRanges')
    $ca = Invoke-L09Rest -Path "$caId`?api-version=2024-03-01"
    $caRules = @(Get-L09Value $ca 'properties.configuration.ingress.ipSecurityRestrictions')
    $wf = Invoke-L09Rest -Path "$logicId`?api-version=2019-05-01"
    $trig = @(Get-L09Value $wf 'properties.accessControl.triggers.allowedCallerIpAddresses' | ForEach-Object addressRange)
    $cont = @(Get-L09Value $wf 'properties.accessControl.contents.allowedCallerIpAddresses' | ForEach-Object addressRange)
    $say = { param($list) if ($list.Count -eq 1 -and $list[0] -eq $cidr) { 'matches your current IP' } elseif ($list.Count) { "$($list.Count) other address(es)" } else { 'none' } }
    [pscustomobject]@{
        AksPower               = $aks.powerState.code
        AksAuthorizedRanges    = & $say $ranges
        ContainerAppAllowList  = & $say @($caRules | Where-Object { $_.action -eq 'Allow' } | ForEach-Object ipAddressRange)
        LogicTriggerCallers    = & $say $trig
        LogicRunHistoryCallers = & $say $cont
    }
}

$before = Get-IpState
$before | Format-List | Out-Host
$stale = @($before.PSObject.Properties | Where-Object { $_.Name -ne 'AksPower' -and $_.Value -ne 'matches your current IP' } | ForEach-Object Name)
if (-not $Apply) {
    [void](Write-L09Evidence 'operator-ip-status' $before)
    if ($stale.Count) { Write-Host "Stale: $($stale -join ', '). Re-run with -Apply to set them to your current IP." } else { Write-Host 'Every operator allow list matches your current IP.' }
    return
}
[void](Write-L09Evidence 'operator-ip-before-apply' $before)
if ($Force) { $stale = @('AksAuthorizedRanges', 'ContainerAppAllowList', 'LogicTriggerCallers'); Write-Host 'Force: rewriting all three.' }

if ($stale -contains 'AksAuthorizedRanges') {
    if ($before.AksPower -ne 'Running') { throw "$($n.aks) is $($before.AksPower); start it with Start-L09Lab.ps1 first, because AKS won't update a stopped cluster." }
    Write-Host "Setting $($n.aks)'s authorized IP range to your IP (a few minutes)."
    Invoke-L09Az -Raw @('aks', 'update', '--resource-group', $cfg.resourceGroup, '--name', $n.aks, '--api-server-authorized-ip-ranges', $cidr) | Out-Null
}
if ($stale -contains 'ContainerAppAllowList') {
    $app = Invoke-L09Rest -Path "$caId`?api-version=2024-03-01"
    $ing = $app.properties.configuration.ingress
    $ing.ipSecurityRestrictions = @(@{ name = 'allow-operator'; description = 'Operator workstation only'; ipAddressRange = $cidr; action = 'Allow' })
    Invoke-L09Rest -Method patch -Path "$caId`?api-version=2024-03-01" -Body @{ properties = @{ configuration = @{ ingress = $ing } } } | Out-Null
    Write-Host "Set $($n.containerApp)'s allow list to your IP."
}
if ($stale -contains 'LogicTriggerCallers' -or $stale -contains 'LogicRunHistoryCallers') {
    # A workflow PUT replaces the whole resource, so send back what ARM returned with only the
    # two address lists changed: the Entra policy, SAS off, and secure inputs stay as they are.
    $wf = Invoke-L09Rest -Path "$logicId`?api-version=2019-05-01"
    $ac = $wf.properties.accessControl
    $ac.triggers.allowedCallerIpAddresses = @(@{ addressRange = $cidr })
    $ac.contents.allowedCallerIpAddresses = @(@{ addressRange = $cidr })
    $body = @{ location = $wf.location; tags = $wf.tags; identity = @{ type = 'SystemAssigned' }; properties = @{ state = $wf.properties.state; definition = $wf.properties.definition; parameters = (Get-L09Value $wf 'properties.parameters'); accessControl = $ac } }
    Invoke-L09Rest -Method put -Path "$logicId`?api-version=2019-05-01" -Body $body | Out-Null
    Write-Host "Set $($n.logicApp)'s caller and run-history allow lists to your IP."
}

$after = Get-IpState
[void](Write-L09Evidence 'operator-ip-after-apply' $after)
$after | Format-List | Out-Host
$still = @($after.PSObject.Properties | Where-Object { $_.Name -ne 'AksPower' -and $_.Value -ne 'matches your current IP' } | ForEach-Object Name)
if ($still.Count) { throw "Still not your current IP: $($still -join ', '). See the evidence files." }
Write-Host "Operator allow lists: PASS, read back at $((Get-Date).ToString('yyyy-MM-dd HH:mm zzz'))."
