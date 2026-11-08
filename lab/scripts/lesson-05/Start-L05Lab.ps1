<#
.SYNOPSIS
    Starts, or with -Stop deallocates, the four retained Lesson 5 test VMs.

.DESCRIPTION
    The VMs cost about 0.04 USD an hour together while running and only their disks while
    deallocated. Probes, IP flow verify, and effective rules all need them running; Run
    Command also needs the VM agent up, which takes a minute or two after the start returns.
    Deallocating stops compute billing. Nothing is deleted.

.PARAMETER Stop
    Deallocate instead of start.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Start-L05Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Start-L05Lab.ps1 -Stop
#>
[CmdletBinding()]
param([switch]$Stop)
. (Join-Path $PSScriptRoot 'L05.Common.ps1')
[void](Assert-L05Context)
$rg = $script:L05Config.resourceGroup
$ids = @(Invoke-L05Az @('vm', 'list', '--resource-group', $rg, '--query', '[].id'))
if ($ids.Count -ne 4) { throw "Expected four VMs in $rg, found $($ids.Count)." }
$verb = if ($Stop) { 'deallocate' } else { 'start' }
Write-Host "Running vm $verb on $($ids.Count) VMs."
[void](Invoke-L05Az -Raw (@('vm', $verb, '--ids') + $ids))
$state = @(Invoke-L05Az @('vm', 'list', '--resource-group', $rg, '--show-details', '--query', '[].{name:name, power:powerState}'))
[void](Write-L05Evidence "vms-$verb" $state)
$state | Format-Table -AutoSize | Out-String
