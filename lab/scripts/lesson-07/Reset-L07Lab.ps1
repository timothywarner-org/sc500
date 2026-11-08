<#
.SYNOPSIS
    Returns the Lesson 7 lab to CTSO-L07-BASELINE after you finish.

.DESCRIPTION
    Re-applies the firewall policy in its baseline state (threat intelligence Alert, IDPS Alert,
    no signature override) and refreshes the DNAT source to the current public IP. Demo 7.3 is
    read-only, so nothing else drifts. Doesn't delete the firewall: Remove-L07Bounded.ps1 does
    that, and Test-L07Lab.ps1 warns while it still exists. With -Stop, also deallocates the VMs.

.PARAMETER Stop
    Deallocate both VMs after the reset.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Reset-L07Lab.ps1 -Stop
#>
[CmdletBinding()]
param([switch]$Stop)
. (Join-Path $PSScriptRoot 'L07.Common.ps1')
[void](Assert-L07Context)
& (Join-Path $PSScriptRoot 'Set-L07Policy.ps1') -State Baseline
if ($Stop) { & (Join-Path $PSScriptRoot 'Start-L07Lab.ps1') -Stop }
Write-Host 'Reset complete. Run Test-L07Lab.ps1 to confirm the baseline.'
