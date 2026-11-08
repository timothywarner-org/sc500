<#
.SYNOPSIS
    Your step after you finish Lesson 15: removes the reaper, its custom role, and the guarded group.
.DESCRIPTION
    Refuses while any Security Copilot capacity still exists in the guarded group, because removing
    the reaper would leave that capacity billing with nothing watching it. Run
    Stop-L15CopilotSession.ps1 first. Security Copilot's workspace and settings are portal
    configuration and aren't touched. Lessons 13 and 14 are untouched.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Remove-L15Lab.ps1
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()
. (Join-Path $PSScriptRoot 'L15.Common.ps1')
$cfg = $script:L15Config
[void](Assert-L15Context)
$left = @(Get-L15Capacities | Where-Object guarded)
if ($left) { throw "A capacity still exists in $($cfg.resourceGroup) ($($left.name -join ', ')). Run Stop-L15CopilotSession.ps1 first." }
$g = Invoke-L15Az -AllowFailure @('group', 'show', '--name', $cfg.resourceGroup)
if ($g.ExitCode -ne 0) { Write-Host "$($cfg.resourceGroup) doesn't exist." }
else {
    $gObj = $g.Stdout | ConvertFrom-Json
    if ($gObj.tags.managedby -ne $cfg.managedBy) { throw "$($cfg.resourceGroup) isn't tagged managedby=$($cfg.managedBy); refusing to delete it." }
    if ($PSCmdlet.ShouldProcess($cfg.resourceGroup, 'Delete the group, the reaper, and its role assignment')) {
        [void](Invoke-L15Az @('group', 'delete', '--name', $cfg.resourceGroup, '--yes'))
        Write-Host "Deleted $($cfg.resourceGroup)."
    }
}
# If removal was declined (or WhatIf), keep the live safeguard's role and deployment record.
if ((Invoke-L15Az -AllowFailure @('group', 'show', '--name', $cfg.resourceGroup)).ExitCode -eq 0) {
    Write-Host 'Lesson group still exists; retaining its custom role and deployment record.'
    return
}
$roles = @(Invoke-L15Az @('role', 'definition', 'list', '--custom-role-only', 'true', '--query', "[?roleName == '$($cfg.reaper.roleName) ($($cfg.copilot.capacityResourceType))']"))
foreach ($r in $roles) {
    if ($PSCmdlet.ShouldProcess($r.roleName, 'Delete the custom role')) {
        [void](Invoke-L15Az @('role', 'definition', 'delete', '--name', $r.name, '--scope', "/subscriptions/$($cfg.subscriptionId)"))
        Write-Host "Deleted role $($r.roleName)."
    }
}
if ($PSCmdlet.ShouldProcess($cfg.deploymentName, 'Remove the completed lesson deployment record')) {
    [void](Invoke-L15Az @('deployment', 'sub', 'delete', '--name', $cfg.deploymentName))
}
[void](Write-L15Evidence 'remove' ([ordered]@{ removedUtc = [DateTime]::UtcNow.ToString('o'); group = $cfg.resourceGroup; roles = @($roles.roleName) }))
