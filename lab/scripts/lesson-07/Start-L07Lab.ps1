<#
.SYNOPSIS
    Starts, or with -Stop deallocates, the two retained Lesson 7 VMs.

.DESCRIPTION
    Each B1s VM costs about 0.01 USD an hour running and only its disk while deallocated.
    Demo 7.1 needs production running (its probe and status page). Demo 7.3 needs both running:
    Network Watcher's IP flow verify and next hop, and the NIC's effective routes and effective
    security rules, all read a running VM. Nothing is deleted here.

.PARAMETER Stop
    Deallocate instead of start.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Start-L07Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Start-L07Lab.ps1 -Stop
#>
[CmdletBinding()]
param([switch]$Stop)
. (Join-Path $PSScriptRoot 'L07.Common.ps1')
[void](Assert-L07Context)
$rg = $script:L07Config.resourceGroup
$ids = @(Invoke-L07Az @('vm', 'list', '--resource-group', $rg, '--query', '[].id'))
if ($ids.Count -ne 2) { throw "Expected two VMs in $rg, found $($ids.Count)." }
$verb = if ($Stop) { 'deallocate' } else { 'start' }
Write-Host "Running vm $verb on $($ids.Count) VMs."
[void](Invoke-L07Az -Raw (@('vm', $verb, '--ids') + $ids))
$state = @(Invoke-L07Az @('vm', 'list', '--resource-group', $rg, '--show-details', '--query', '[].{name:name, power:powerState}'))
[void](Write-L07Evidence "vms-$verb" $state)
$state | Format-Table -AutoSize | Out-String
