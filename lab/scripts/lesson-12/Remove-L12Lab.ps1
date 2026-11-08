<#
.SYNOPSIS
    Deletes the SC-500 Lesson 12 lab. Your step.
.DESCRIPTION
    -Easm deletes only rg-sc500-l12-easm and the Defender EASM workspace in it. Run it before the
    workspace's 30-day free trial ends (Test-L12Lab.ps1 prints the days left), because after the
    trial every approved inventory asset bills daily. Deleting the workspace deletes its inventory.
    -All runs Reset-L12Lab.ps1, then deletes both Lesson 12 resource groups.
    Nothing outside the Lesson 12 groups is touched: every Defender plan stays exactly as it is.
    This is a separate, explicitly selected action. Reset-L12Lab.ps1 is the routine cleanup.
.PARAMETER Easm Delete the EASM resource group only.
.PARAMETER All Delete both Lesson 12 resource groups.
.PARAMETER Confirm Asks before deleting (default). Pass -Confirm:$false only if you mean it.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Remove-L12Lab.ps1 -Easm
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Easm')]
param(
    [Parameter(ParameterSetName = 'Easm', Mandatory)][switch]$Easm,
    [Parameter(ParameterSetName = 'All', Mandatory)][switch]$All
)
. (Join-Path $PSScriptRoot 'L12.Common.ps1')
$cfg = $script:L12Config
[void](Assert-L12Context)
$targets = if ($All) { @($cfg.easmResourceGroup, $cfg.resourceGroup) } else { @($cfg.easmResourceGroup) }
if ($All -and $PSCmdlet.ShouldProcess('Lesson 12 lab', 'Reset before deletion')) { & (Join-Path $PSScriptRoot 'Reset-L12Lab.ps1') -Confirm:$false }
$gone = [ordered]@{}
foreach ($rg in $targets) {
    if ($PSCmdlet.ShouldProcess($rg, 'Delete resource group and everything in it')) {
        Write-Host "Deleting $rg (a few minutes)."
        [void](Invoke-L12Az -Raw @('group', 'delete', '--name', $rg, '--yes'))
        $gone[$rg] = ((Invoke-L12Az -AllowFailure @('group', 'show', '--name', $rg)).ExitCode -ne 0)
        Write-Host $(if ($gone[$rg]) { "$rg is gone." } else { "$rg still exists; check the portal." })
    }
}
if (-not $WhatIfPreference) { [void](Write-L12Evidence 'remove' ([ordered]@{ removedUtc = [DateTime]::UtcNow.ToString('o'); groupsGone = $gone })) }
