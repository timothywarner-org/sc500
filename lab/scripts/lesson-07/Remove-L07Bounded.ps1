<#
.SYNOPSIS
    Deletes the Lesson 7 firewall after you finish, and proves it's gone.

.DESCRIPTION
    Deletes the lesson firewall (names.firewall in config.json; its diagnostic setting goes with
    it) and the firewall deployment record. The retained policy, public IP, VNets, Key Vault,
    workspace, and VMs stay; the workspace keeps the logs for 30 days. Refuses to delete a
    firewall that isn't tagged managedby=sc500-l07-iac and bounded=true. Deletion usually takes
    5 to 10 minutes.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Remove-L07Bounded.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L07.Common.ps1')
[void](Assert-L07Context)
$cfg = $script:L07Config
$rg = $cfg.resourceGroup
$name = $cfg.names.firewall
$type = 'Microsoft.Network/azureFirewalls'

function Test-Firewall { $null -ne (Get-L07Firewall) }

if (Test-Firewall) {
    $fw = Invoke-L07Az @('resource', 'show', '--resource-group', $rg, '--resource-type', $type, '--name', $name)
    if ("$(Get-L07Value $fw 'tags.managedby')" -ne $cfg.managedBy -or "$(Get-L07Value $fw 'tags.bounded')" -ne 'true') { throw "$name isn't tagged as this lesson's bounded firewall. Nothing was deleted." }
    Write-Host "Deleting $name. This usually takes 5 to 10 minutes."
    $started = Get-Date
    [void](Invoke-L07Az -Raw @('resource', 'delete', '--ids', $fw.id))
    Write-Host ("Deleted in {0:N0} minutes." -f ((Get-Date) - $started).TotalMinutes)
}
[void](Invoke-L07Az -Raw -AllowFailure @('deployment', 'group', 'delete', '--resource-group', $rg, '--name', $cfg.firewallDeploymentName))
$removed = [ordered]@{ firewall = if (Test-Firewall) { 'still present' } else { 'absent' } }
[void](Write-L07Evidence 'remove-firewall' $removed)
$removed.GetEnumerator() | ForEach-Object { '{0,-12} {1}' -f $_.Key, $_.Value }
if (@($removed.Values) -contains 'still present') { throw 'The firewall still exists. Check the portal before assuming billing stopped.' }
