<#
.SYNOPSIS
    Returns the SC-500 Lesson 12 lab to its idle baseline (CTSO-L12-BASELINE) after a rehearsal or
    a take, and reads back that every change is undone.
.DESCRIPTION
    Undoes what the demos and -Stage change, in this order:
      1. Removes only the configured lesson governance assignment (demo 12.1).
      2. Puts Defender for Storage back to excluded on the store (demo 12.2 StorageOverride), so the
         per-account charge stops.
      3. Deletes the parts-exports container and its fictional export (Deploy-L12Lab.ps1 -Stage), so
         Defender CSPM stops counting the store as billable.
      4. Turns Shared Key authorization back on (demo 12.1 Remediate). That's the deliberate fault
         the next take fixes. It's safe to restore because the store holds no data.
    Retained and untouched: the store itself, your data role, the EASM workspace and its discovery
    group, and every Defender plan. Remove-L12Lab.ps1 (your step) deletes the lab.
.PARAMETER WhatIf Show what would change and change nothing.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Reset-L12Lab.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param()
. (Join-Path $PSScriptRoot 'L12.Common.ps1')
. (Join-Path $PSScriptRoot 'L12.Checks.ps1')
$cfg = $script:L12Config
[void](Assert-L12Context)
$lab = Get-L12Outputs
# The fixed assignment ID and named container bound the reset even if other work appears here.
$gaList = "$($lab.storageId)/providers/Microsoft.Security/assessments/$($cfg.posture.sharedKeyAssessment)/governanceAssignments?api-version=2025-05-04"
$dfsPath = "$($lab.storageId)/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2025-01-01"

$assignments = @(@(Get-L12Value (Invoke-L12Rest -AllowNotFound -Path $gaList) 'value') | Where-Object { $_ })
$containers = @(Invoke-L12Az @('storage', 'container-rm', 'list', '--resource-group', $lab.resourceGroup, '--storage-account', $lab.storage, '--query', '[].name'))
if (-not (Test-L12ResetScope $containers $assignments $lab.container $cfg.posture.governanceAssignmentKey)) {
    throw 'Unexpected container or governance assignment. Nothing changed; reconcile ownership before resetting this fixture.'
}
foreach ($a in $assignments) {
    if ($PSCmdlet.ShouldProcess("governance assignment $($a.name) (owner $($a.properties.owner))", 'Remove')) {
        [void](Invoke-L12Rest -Method delete -Path "$($a.id)?api-version=2025-05-04")
        Write-Host "Removed governance assignment $($a.name)."
    }
}
if ($PSCmdlet.ShouldProcess("$($lab.storage) Defender for Storage", 'Set to excluded')) {
    [void](Invoke-L12Rest -Method put -Path $dfsPath -Body @{ properties = @{ isEnabled = $false; overrideSubscriptionLevelSettings = $true } })
}
foreach ($name in $containers) {
    if ($PSCmdlet.ShouldProcess("$($lab.storage)/$name", 'Delete container')) {
        [void](Invoke-L12Az -Raw @('storage', 'container-rm', 'delete', '--resource-group', $lab.resourceGroup, '--storage-account', $lab.storage, '--name', $name, '--yes'))
        Write-Host "Deleted container $name."
    }
}
$remainingBeforeFault = @(Invoke-L12Az @('storage', 'container-rm', 'list', '--resource-group', $lab.resourceGroup, '--storage-account', $lab.storage, '--query', '[].name'))
if (-not $WhatIfPreference -and $remainingBeforeFault.Count) { throw 'A container remains; Shared Key will not be enabled.' }
if ($PSCmdlet.ShouldProcess($lab.storage, 'Allow Shared Key authorization again (the lesson fault)')) {
    [void](Invoke-L12Az @('storage', 'account', 'update', '--name', $lab.storage, '--resource-group', $lab.resourceGroup, '--allow-shared-key-access', 'true', '--query', 'id'))
}
if ($WhatIfPreference) { return }

# Read everything back.
$fx = Get-L12Fixture -Lab $lab
$dfs = Invoke-L12Rest -Path $dfsPath
$left = @(Invoke-L12Az @('storage', 'container-rm', 'list', '--resource-group', $lab.resourceGroup, '--storage-account', $lab.storage, '--query', '[].name'))
$ga = @(@(Get-L12Value (Invoke-L12Rest -AllowNotFound -Path $gaList) 'value') | Where-Object { $_ })
$ok = ($fx.allowSharedKeyAccess -eq $true) -and ($dfs.properties.isEnabled -eq $false) -and ($left.Count -eq 0) -and ($ga.Count -eq 0)
Write-Host ("Shared Key allowed: {0}. Defender for Storage on the store: {1}. Containers left: {2}. Governance assignment: {3}." -f
    $fx.allowSharedKeyAccess, $dfs.properties.isEnabled, $left.Count, $(if ($ga.Count) { "$($ga.Count) still present" } else { 'none' }))
[void](Write-L12Evidence 'reset' ([ordered]@{ resetUtc = [DateTime]::UtcNow.ToString('o'); removedContainers = $containers; fixture = $fx; defenderForStorageEnabled = $dfs.properties.isEnabled; containersLeft = $left; governanceAssignmentsLeft = $ga.Count; idle = $ok }))
if (-not $ok) { Write-Warning 'The lab is not fully back to idle. Check the portal before you assume billing stopped.'; exit 1 }
Write-Host 'Idle baseline restored.'
