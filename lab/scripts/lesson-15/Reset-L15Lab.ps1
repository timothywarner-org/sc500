<#
.SYNOPSIS
    Returns Lesson 15 to its starting checkpoint between runs: the pinned case open, no paid capacity.
.DESCRIPTION
    Lesson 15 ends with you closing the Lesson 14 case in the Defender portal. That close is the lesson's
    authorized action, so it only happens in the demo. For a rerun:
      -ReopenCase  sets the pinned incident's status back to Active through the Microsoft Sentinel API,
                   keeping its title, severity, owner, tags, and comments. Your close comment stays in
                   the history, which is what an audit trail should do.
      -StopCapacity  runs Stop-L15CopilotSession.ps1 (it asks before deleting).
    Portal settings (the uploaded ServiceHub plugin, plugin toggles, the Security Analyst Agent's data
    source) are Security Copilot configuration; the prep page lists how to remove them by hand.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Reset-L15Lab.ps1 -ReopenCase
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$ReopenCase, [switch]$StopCapacity)
. (Join-Path $PSScriptRoot 'L15.Common.ps1')
[void](Assert-L15Context)
if (-not $ReopenCase -and -not $StopCapacity) { throw 'Choose -ReopenCase, -StopCapacity, or both.' }
if ($ReopenCase) {
    $l13 = Get-L15L13Lab
    $case = Get-L15Case
    $inc = Get-L15Incident -L13Lab $l13 -IncidentName $case.incidentName
    if (-not $inc) { throw "Incident $($case.incidentNumber) not found." }
    if ($inc.properties.status -ne 'Closed') { Write-Host "Incident $($inc.properties.incidentNumber) is already $($inc.properties.status)." }
    elseif ($PSCmdlet.ShouldProcess("incident $($inc.properties.incidentNumber)", 'Reopen (status Active)')) {
        # PUT needs the current etag and the required properties; classification fields are dropped on reopen.
        $p = $inc.properties
        $body = @{ etag = $inc.etag; properties = @{ title = $p.title; severity = $p.severity; status = 'Active'
            description = $p.description; labels = @($p.labels); owner = $p.owner } }
        $r = Invoke-L15Rest -Method put -Path "$($l13.workspaceId)/providers/Microsoft.SecurityInsights/incidents/$($inc.name)?api-version=2025-09-01" -Body $body
        Write-Host "Incident $($r.properties.incidentNumber) is $($r.properties.status). Defender portal sync can take a few minutes."
        [void](Write-L15Evidence 'reset-reopen' ([ordered]@{ reopenedUtc = [DateTime]::UtcNow.ToString('o'); incident = $r.properties.incidentNumber; status = $r.properties.status }))
    }
}
if ($StopCapacity) { & (Join-Path $PSScriptRoot 'Stop-L15CopilotSession.ps1') }
