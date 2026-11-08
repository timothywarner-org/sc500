<#
.SYNOPSIS
    Returns the Lesson 8 lab to CTSO-L08-BASELINE after you finish.

.DESCRIPTION
    Removes the bounded part if it exists (the JIT policy, the legacy app server (vm-legacyapp-prod-001), its public IP, and its
    NSG), and with -Stop deallocates the retained VMs. The retained VMs, Bastion, and the policy
    assignments stay, and so does the Arc machine: once you have connected it, it stays connected
    and shows Disconnected while its VM is deallocated. Run Test-L08Lab.ps1 afterward.

.PARAMETER Stop
    Also deallocate the ServiceHub app server (vm-servicehub-prod-001) and the datacenter server (vm-datacenter-prod-001).

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Reset-L08Lab.ps1 -Stop
#>
[CmdletBinding()]
param([switch]$Stop)
. (Join-Path $PSScriptRoot 'L08.Common.ps1')
[void](Assert-L08Context)
& (Join-Path $PSScriptRoot 'Remove-L08Bounded.ps1')
if ($Stop) { & (Join-Path $PSScriptRoot 'Start-L08Lab.ps1') -Stop }
Write-Host 'Reset complete. Run Test-L08Lab.ps1 to confirm the baseline.'
