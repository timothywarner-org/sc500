<#
.SYNOPSIS
    Deletes the parked Lesson 6 lab, in Azure and in Microsoft Entra, when you finish Lesson 6.

.DESCRIPTION

    Default run is a DRY RUN. It reads the five Lesson 6 resource groups named in
    infra/lesson-06/config.json through Azure Resource Graph (the inventory of record; az resource
    list returned an empty list for populated subscriptions on 2026-10-24), checks each group's
    managedBy tag, finds the connector and device objects the lab left in Microsoft Entra, prints
    the plan, and changes nothing.

    With -Execute it asks you to type the word DELETE (skip with -Force), then:
      1. Deletes every Lesson 6 resource group that exists and carries managedBy=sc500-l06-iac.
         A group with any other tag value stops the run before anything is deleted.
      2. Deletes the Entra device object for the client computer (techlaptop-001). A stale device
         object blocked the client's Entra join with 0x801c0083 on October 30, so this is not optional.
      3. Tries to delete the connector object (pnconnector-001) from Microsoft Entra Private Access.
         Microsoft Graph doesn't document a delete for application proxy connectors, so when the call
         is refused the script tells you the portal path: the connector reads Inactive about 10 days
         after its host is gone, and the Connectors page then offers Delete.
      4. Deletes this subscription's saved SSH public key and image version so the next
         Deploy-L06Lab.ps1 starts clean. Evidence files stay.
      5. Reads Azure and Entra back and writes evidence under lab/.azure/lesson-06/evidence/.

    Left alone on purpose, because they're tenant configuration that bills nothing and the Lesson 6
    story may be re-shot from them: the Private Access pilot app, the connector group
    CTSO-L06-Connectors, the forwarding profile, the pilot group, and NetworkWatcherRG.

.PARAMETER Execute
    Delete. Without it the script only prints the plan.

.PARAMETER Force
    Skip the typed confirmation. Only for an unattended run you have already approved.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Remove-L06Lab.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Remove-L06Lab.ps1 -Execute

.NOTES
#>
[CmdletBinding()]
param([switch]$Execute, [switch]$Force)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$cfg = $script:L06Config
$names = $script:L06Names

# --- 1. Azure inventory through Resource Graph -------------------------------------------------
# Every group name comes from config.json. The script never spells one itself.
$groups = @($cfg.resourceGroup, $cfg.plsResourceGroup, $cfg.dnsResourceGroup, $cfg.connectorResourceGroup, $cfg.clientResourceGroup)
$groupList = ($groups | ForEach-Object { "'$_'" }) -join ','
$containerQuery = "resourcecontainers | where type == 'microsoft.resources/subscriptions/resourcegroups' and subscriptionId == '$($cfg.subscriptionId)' and name in~ ($groupList) | project name, tags"
$resourceQuery = "resources | where subscriptionId == '$($cfg.subscriptionId)' and resourceGroup in~ ($groupList) | project resourceGroup, type, name, power = tostring(properties.extended.instanceView.powerState.code) | order by resourceGroup asc, type asc"
$existing = @((Invoke-L06Az -NoSubscription @('graph', 'query', '-q', $containerQuery, '--first', '100')).data)
$resources = @((Invoke-L06Az -NoSubscription @('graph', 'query', '-q', $resourceQuery, '--first', '1000')).data)

Write-Host "`nLesson 6 resource groups in $($cfg.subscriptionId):"
if ($existing.Count -eq 0) { Write-Host '  none exist' }
foreach ($g in $existing) {
    $tag = Get-L06Value $g 'tags.managedBy'
    $count = @($resources | Where-Object resourceGroup -eq $g.name).Count
    Write-Host ("  {0,-32} managedBy={1,-14} {2} resources" -f $g.name, $tag, $count)
    # Refuse the whole run on a group the lab doesn't own. Nothing has been deleted at this point.
    if ($tag -ne $cfg.managedBy) { throw "$($g.name) isn't tagged managedBy=$($cfg.managedBy). Nothing was deleted." }
}
$running = @($resources | Where-Object { $_.type -eq 'microsoft.compute/virtualmachines' -and $_.power -eq 'PowerState/running' })
if ($running.Count) { Write-Host ("  Running VMs: {0} (deallocation isn't needed before a group delete)" -f (($running | ForEach-Object name) -join ', ')) }

# --- 2. Entra inventory: the device object and the connector object ----------------------------
# Graph goes through the Azure CLI's cached sign-in (az rest picks the Graph audience from the URL), not
# Connect-MgGraph: asking the Graph SDK for a scope its cache doesn't hold (Device.ReadWrite.All) opens a
# browser, and from a non-interactive host that fails with "A window handle must be configured". The CLI
# token already carries the delegated directory permissions a tenant admin has.
function Invoke-L06Graph {
    param([Parameter(Mandatory)][ValidateSet('GET', 'DELETE')][string]$Method, [Parameter(Mandatory)][string]$Uri)
    $r = Invoke-L06Az -NoSubscription -AllowFailure @('rest', '--method', $Method.ToLower(), '--url', $Uri)
    if ($r.ExitCode -ne 0) { throw "Graph $Method $Uri failed: $($r.Stderr.Trim())" }
    if ([string]::IsNullOrWhiteSpace($r.Stdout)) { return $null }
    return $r.Stdout | ConvertFrom-Json -Depth 50
}
$deviceUri = "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$($names.clientComputer)'"
$devices = @((Invoke-L06Graph GET $deviceUri).value)
$proxyBase = 'https://graph.microsoft.com/beta/onPremisesPublishingProfiles/applicationProxy'
$connectors = @((Invoke-L06Graph GET "$proxyBase/connectors").value | Where-Object machineName -like "$($names.connectorComputer)*")

Write-Host "`nMicrosoft Entra objects:"
Write-Host ("  Device objects named {0}: {1}" -f $names.clientComputer, $devices.Count)
foreach ($d in $devices) { Write-Host ("    {0}  trust={1}  last sign-in {2}" -f $d.id, $d.trustType, $d.approximateLastSignInDateTime) }
Write-Host ("  Connector objects named {0}*: {1}" -f $names.connectorComputer, $connectors.Count)
foreach ($c in $connectors) { Write-Host ("    {0}  {1}  status={2}  externalIp={3}" -f $c.id, $c.machineName, $c.status, $c.externalIp) }

if (-not $Execute) {
    Write-Host "`nDry run. Add -Execute to delete the $($existing.Count) group(s), $($devices.Count) device object(s) and $($connectors.Count) connector object(s) above."
    return
}

# --- 3. Confirm, then delete ------------------------------------------------------------------
if (-not $Force) {
    $answer = Read-Host "Delete the Lesson 6 lab listed above? Type DELETE to confirm"
    if ($answer -cne 'DELETE') { Write-Host 'Cancelled. Nothing was deleted.'; return }
}

$deleted = [ordered]@{ groups = @(); devices = @(); connectors = @(); connectorNote = $null }
foreach ($g in $existing) {
    Write-Host "Deleting $($g.name)."
    [void](Invoke-L06Az -Raw @('group', 'delete', '--name', $g.name, '--yes'))
    $deleted.groups += $g.name
}
foreach ($d in $devices) {
    [void](Invoke-L06Graph DELETE "https://graph.microsoft.com/v1.0/devices/$($d.id)")
    $deleted.devices += $d.id
    Write-Host "Deleted device object $($d.id) ($($names.clientComputer))."
}
foreach ($c in $connectors) {
    try {
        [void](Invoke-L06Graph DELETE "$proxyBase/connectors/$($c.id)")
        $deleted.connectors += $c.id
        Write-Host "Deleted connector object $($c.id) ($($c.machineName))."
    }
    catch {
        # Graph documents no delete for application proxy connectors. The portal removes one once
        # its host has been gone long enough to read Inactive (about 10 days).
        $deleted.connectorNote = "Graph refused the delete for connector $($c.id): $($_.Exception.Message). Remove it in the Microsoft Entra admin center: Global Secure Access > Connect > Connectors, once it reads Inactive (about 10 days after its host is gone)."
        Write-Warning $deleted.connectorNote
    }
}
foreach ($f in 'ssh-public-key.txt', 'image-version.txt') {
    $p = Join-Path $script:L06State $f
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}

# --- 4. Read back and write evidence ----------------------------------------------------------
$left = @((Invoke-L06Az -NoSubscription @('graph', 'query', '-q', $containerQuery, '--first', '100')).data)
$devicesLeft = @((Invoke-L06Graph GET $deviceUri).value)
$readback = [ordered]@{
    deleted = $deleted
    groupsStillPresent = @($left | ForEach-Object name)
    deviceObjectsStillPresent = @($devicesLeft | ForEach-Object id)
    checkedUtc = [DateTime]::UtcNow.ToString('o')
}
$evidence = Write-L06Evidence 'remove-lab' $readback
Write-Host "Evidence: $evidence"
if ($left.Count) { throw "Still present: $(($left | ForEach-Object name) -join ', ')" }
if ($devicesLeft.Count) { throw "Device object(s) still present: $(($devicesLeft | ForEach-Object id) -join ', ')" }
Write-Host 'Lesson 6 lab removed. Azure groups gone; device object gone. See any connector warning above.'
