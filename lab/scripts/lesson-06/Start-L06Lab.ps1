<#
.SYNOPSIS
    Starts, or with -Stop deallocates, the retained Lesson 6 VM (vm-servicehub-prod-001).

.DESCRIPTION
    The VM costs about 0.01 USD an hour while running and only its disk while deallocated.
    Demos 6.1 and 6.3 need it running; Run Command also needs the VM agent up, which takes a
    minute or two after the start returns. Other guests are not touched. Use
    Start-L06PrivateAccessLab.ps1 for the retained app, connector and client together.
    Enable maintenance egress before starting Linux; remove it after deallocation.

.PARAMETER Stop
    Deallocate instead of start.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Start-L06Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Start-L06Lab.ps1 -Stop
#>
[CmdletBinding()]
param([switch]$Stop)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$rg = $script:L06Config.resourceGroup
$ids = @(Invoke-L06Az @('vm', 'list', '--resource-group', $rg, '--query', '[].id'))
if ($ids.Count -ne 1) { throw "Expected one VM in $rg, found $($ids.Count)." }
$verb = if ($Stop) { 'deallocate' } else { 'start' }
Write-Host "Running vm $verb on $($ids.Count) VM."
[void](Invoke-L06Az -Raw (@('vm', $verb, '--ids') + $ids))
$state = @(Invoke-L06Az @('vm', 'list', '--resource-group', $rg, '--show-details', '--query', '[].{name:name, power:powerState}'))
[void](Write-L06Evidence "vms-$verb" $state)
$state | Format-Table -AutoSize | Out-String
