<#
.SYNOPSIS
    Starts, or with -Stop deallocates, the Lesson 8 VMs.

.DESCRIPTION
    Starts or deallocates the ServiceHub app server (vm-servicehub-prod-001) and the datacenter server (vm-datacenter-prod-001), plus the legacy app server (vm-legacyapp-prod-001) if the bounded part
    exists. Running, each B1ms costs about 0.02 USD an hour, and Defender for Servers Plan 2 adds
    about 0.02 USD an hour for the ServiceHub app server (vm-servicehub-prod-001) and for the connected Arc machine. Deallocated, only the
    disks bill, and the Arc machine shows Disconnected, which Defender doesn't bill.

    Start the VMs about 20 minutes before the demo: the Arc agent reconnects in a few minutes, but
    Defender and machine configuration report on their own schedules. Nothing is deleted here.

.PARAMETER Stop
    Deallocate instead of start.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Start-L08Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Start-L08Lab.ps1 -Stop
#>
[CmdletBinding()]
param([switch]$Stop)
. (Join-Path $PSScriptRoot 'L08.Common.ps1')
[void](Assert-L08Context)
$cfg = $script:L08Config
$rg = $cfg.resourceGroup
$vms = @(Invoke-L08Az @('vm', 'list', '--resource-group', $rg))
$expected = @($cfg.names.appVm, $cfg.names.onpremVm, $cfg.names.legacyVm)
$unknown = @($vms | Where-Object { $expected -notcontains $_.name })
if ($unknown.Count) { throw "Unexpected VMs in ${rg}: $(($unknown | ForEach-Object name) -join ', ')" }
foreach ($required in $cfg.names.appVm, $cfg.names.onpremVm) {
    if (-not ($vms | Where-Object name -eq $required)) { throw "$required is missing. Run Deploy-L08Lab.ps1 -Deploy." }
}
$verb = if ($Stop) { 'deallocate' } else { 'start' }
Write-Host "Running vm $verb on $($vms.Count) VMs."
[void](Invoke-L08Az -Raw (@('vm', $verb, '--ids') + @($vms | ForEach-Object id)))
$state = @(Invoke-L08Az @('vm', 'list', '--resource-group', $rg, '--show-details', '--query', '[].{name:name, power:powerState}'))
[void](Write-L08Evidence "vms-$verb" $state)
$state | Format-Table -AutoSize | Out-String
