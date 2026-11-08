<#
.SYNOPSIS
    Routine cleanup between Lesson 14 rehearsals: closes rehearsal incidents from the export rule.
.DESCRIPTION
    Rehearsal sends can create additional incidents. This closes open incidents from the
    Lesson 14 rule with classification Undetermined and a comment saying it was a rehearsal reset,
    not an investigation outcome. It keeps every rule, playbook, table, and row.
    Don't run it between recording Lesson 14 and recording Lesson 15: Lesson 15 picks up the same
    incident. -Keep preserves the pinned recording case, regardless of newer incidents.
.PARAMETER Keep Leave the exact selected incident open for the Lesson 15 handoff.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Reset-L14Lab.ps1 -Keep
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Keep)
. (Join-Path $PSScriptRoot 'L14.Common.ps1')
[void](Assert-L14Context)
# The recorded L14 case is a dependency of L15, not whichever incident happens to be newest.
$pin = Get-L14PinnedCase
if ($pin -and -not $Keep) { throw 'L15 handoff is pinned. Use -Keep; the default reset may not close that case.' }
$l13 = Get-L14L13Lab
$open = @(Get-L14Incidents -L13Lab $l13 -Top 50 | Where-Object { $_.properties.status -ne 'Closed' } | Sort-Object { $_.properties.createdTimeUtc } -Descending)
if ($Keep -and $open) {
    $keepName = if ($pin) { $pin.incident.incidentName } else { (Get-L14RecordingIncident).incidentName }
    Write-Host "Keeping selected incident $keepName for the Lesson 15 handoff."
    $open = @($open | Where-Object name -ne $keepName)
}
$closed = @()
foreach ($i in $open) {
    if (-not $PSCmdlet.ShouldProcess("incident $($i.properties.incidentNumber)", 'Close as a rehearsal reset')) { continue }
    $path = "$($l13.workspaceId)/providers/Microsoft.SecurityInsights/incidents/$($i.name)?api-version=2025-09-01"
    # PUT needs the current etag plus the required fields; send the incident back with only status changed.
    $body = @{ etag = $i.etag; properties = @{
        title = $i.properties.title; severity = $i.properties.severity; status = 'Closed'
        classification = 'Undetermined'; classificationComment = 'Lesson 14 rehearsal reset. Not an investigation outcome.'
        labels = @($i.properties.labels) } }
    [void](Invoke-L14Rest -Method put -Path $path -Body $body)
    $closed += $i.properties.incidentNumber
    Write-Host "Closed incident $($i.properties.incidentNumber) as a rehearsal reset."
}
if (-not $closed) { Write-Host 'No rehearsal incidents to close.' }
[void](Write-L14Evidence 'reset' ([ordered]@{ resetUtc = [DateTime]::UtcNow.ToString('o'); closed = $closed; kept = [bool]$Keep }))
