<#
.SYNOPSIS
    Read-only service checks for SC-500 Lesson 15; writes private evidence locally.
.DESCRIPTION
    PASS, FAIL, WARN, and INFO lines, then a summary. Without -Recording it checks what the lab can
    prove on its own: the course context, Lesson 13's workspace and ServiceHub table, Lesson 14's
    pinned case, your Sentinel read access (Security Copilot reads data as him), the plugin manifest
    and its KQL, and the reaper. -Recording adds the recording gates: the case must still be open,
    the named lesson capacity needs at least 45 minutes on its explicit UTC expiry. An included
    allocation follows its own route. Dated, case-bound portal captures must establish the actual
    plugin, summary, response, agent and claim-review outcomes. Other-course capacities are not managed.
.PARAMETER Recording Also apply the recording gates.
.PARAMETER IncludedCapacity you saw a Microsoft 365 E5 or E7 included capacity in the Security Copilot portal,
    so no paid capacity is needed. A matching captured portal rehearsal is still required.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Test-L15Lab.ps1 -Recording
#>
[CmdletBinding()]
param([switch]$Recording, [switch]$IncludedCapacity)
. (Join-Path $PSScriptRoot 'L15.Common.ps1')
. (Join-Path $PSScriptRoot 'L15.RecordingGates.ps1')
$cfg = $script:L15Config
$results = [System.Collections.Generic.List[object]]::new()
function Add-Check([string]$Status, [string]$Name, [string]$Detail) {
    $results.Add([pscustomobject]@{ status = $Status; check = $Name; detail = $Detail })
    Write-Host ("{0,-5} {1}: {2}" -f $Status, $Name, $Detail)
}

try { $account = Assert-L15Context; Add-Check PASS 'Context' "$($account.name) as $($account.user.name)" }
catch { Add-Check FAIL 'Context' $_.Exception.Message; throw }

# Lesson 13's workspace and the ServiceHub table.
$l13 = $null
try {
    $l13 = Get-L15L13Lab
    $n = @(Invoke-L15Query -L13Lab $l13 -Timespan 'P7D' -Kql "$($cfg.l13.customTable) | where Operation == 'PartsExportRead' | count")[0].Count
    Add-Check $(if ($n -gt 0) { 'PASS' } else { 'FAIL' }) 'ServiceHub rows' "$n parts-export rows in $($cfg.l13.customTable) over 7 days"
} catch { Add-Check FAIL 'Workspace' $_.Exception.Message }

# Lesson 14's case: pinned, present, and (for recording) still open.
if ($l13) {
    try {
        $case = Get-L15Case
        $inc = Get-L15Incident -L13Lab $l13 -IncidentName $case.incidentName
        if (-not $inc) { Add-Check FAIL 'Case' "Incident $($case.incidentNumber) not found ($($case.source))" }
        else {
            $status = $inc.properties.status
            $detail = "Incident $($inc.properties.incidentNumber) · Defender incident $(Get-L15Value $inc 'properties.providerIncidentId') · $status · $($case.source)"
            $st = if ($status -ne 'Closed') { 'PASS' } elseif ($Recording) { 'FAIL' } else { 'WARN' }
            if ($st -ne 'PASS') { $detail += '. Reopen it with Reset-L15Lab.ps1 -ReopenCase before the demo.' }
            Add-Check $st 'Case' $detail
            if ($case.source -notlike '*pin*') { Add-Check $(if ($Recording) { 'FAIL' } else { 'WARN' }) 'Case pin' 'No Lesson 14 handoff pin; recording cannot use an unpinned incident.' }
        }
    } catch { Add-Check FAIL 'Case' $_.Exception.Message }
}

# Your own Sentinel read access: Security Copilot uses it for the Sentinel plugin, the KQL plugin, and the agent.
if ($l13) {
    try {
        $me = Invoke-L15Rest -Path 'https://graph.microsoft.com/v1.0/me?$select=id' -Resource 'https://graph.microsoft.com'
        $assign = @(Invoke-L15Az @('role', 'assignment', 'list', '--assignee', $me.id, '--scope', $l13.workspaceId, '--include-inherited', '--query', '[].roleDefinitionName'))
        $read = @($assign | Where-Object { $cfg.copilot.sentinelReadRoles -contains $_ } | Sort-Object -Unique)
        Add-Check $(if ($read) { 'PASS' } else { 'FAIL' }) 'Sentinel read access' $(if ($read) { "You hold $($read -join ', ') on or above $($cfg.l13.workspace)" } else { 'You have no role that reads the workspace' })
    } catch { Add-Check FAIL 'Sentinel read access' $_.Exception.Message }
}

# The plugin: parses, and every skill's KQL runs as you and returns rows.
if ($l13) {
    try {
        $m = Get-L15PluginManifest
        $skills = @($m.SkillGroups | ForEach-Object { $_.Skills })
        $bad = @($skills | Where-Object { $_.Settings.Target -ne 'Sentinel' -or -not $_.Settings.Template })
        if ($bad -or @($m.Descriptor.SupportedAuthTypes) -notcontains 'None') { Add-Check FAIL 'Plugin manifest' 'Every skill needs Target Sentinel and a Template, and auth None' }
        else {
            $counts = foreach ($s in $skills) {
                $kql = $s.Settings.Template
                foreach ($prop in $cfg.plugin.sampleInputs.PSObject.Properties) { $kql = $kql.Replace("{{$($prop.Name)}}", [string]$prop.Value) }
                "$($s.Name)=$(@(Invoke-L15Query -L13Lab $l13 -Kql $kql).Count)"
            }
            $empty = @($counts | Where-Object { $_ -match '=0$' })
            Add-Check $(if ($empty) { 'FAIL' } else { 'PASS' }) 'Plugin KQL' ("$($m.Descriptor.Name): " + ($counts -join ', ') + ' rows')
        }
    } catch { Add-Check FAIL 'Plugin' $_.Exception.Message }
}

# The reaper: deployed, enabled, and its last run succeeded.
$lab = Get-L15Outputs
if (-not $lab) { Add-Check $(if ($Recording) { 'FAIL' } else { 'WARN' }) 'Reaper' 'Not deployed. Run Deploy-L15Lab.ps1 -Deploy before creating a capacity.' }
else {
    try {
        $wf = Invoke-L15Rest -Path "$($lab.reaperId)?api-version=2019-05-01"
        $run = @((Invoke-L15Rest -Path "$($lab.reaperId)/runs?api-version=2019-05-01&`$top=1").value) | Select-Object -First 1
        $state = $wf.properties.state
        $last = if ($run) { "$($run.properties.status) at $(([DateTime]$run.properties.startTime).ToUniversalTime().ToString('HH:mm')) UTC" } else { 'no runs yet' }
        $ok = $state -eq 'Enabled' -and $run -and $run.properties.status -eq 'Succeeded' -and
            ([DateTimeOffset]$run.properties.startTime -gt [DateTimeOffset]::UtcNow.AddMinutes(-90))
        Add-Check $(if ($ok) { 'PASS' } else { 'FAIL' }) 'Reaper' "$($lab.reaperName) $state, every $($lab.recurrenceMinutes) minutes, last run $last"
    } catch { Add-Check FAIL 'Reaper' $_.Exception.Message }
}

# Only the lesson-owned capacity is gated; unrelated resources remain untouched.
try {
    $caps = @(Get-L15Capacities)
    foreach ($c in @($caps | Where-Object { -not $_.guarded })) { Add-Check INFO 'Other capacity' "$($c.name) is outside the Lesson 15 group; not managed by this lesson." }
    $inside = @($caps | Where-Object { $_.guarded -and $_.name -eq $cfg.copilot.capacityName })
    if (-not $inside) {
        if ($IncludedCapacity) { Add-Check INFO 'Capacity' 'No lesson-owned paid capacity. Included allocation requires matching captured portal evidence below.' }
        else { Add-Check $(if ($Recording) { 'FAIL' } else { 'INFO' }) 'Capacity' 'No lesson-owned paid capacity. Recording needs one, or a verified included allocation. Other-course costs are separate.' }
    }
    foreach ($c in $inside) {
        $deadlineCheck = Test-L15CapacityDeadline -Capacity $c
        $st = if ($deadlineCheck.passed) { 'PASS' } elseif ($Recording) { 'FAIL' } else { 'WARN' }
        $detail = "$($c.name): $($deadlineCheck.detail)"
        Add-Check $st 'Capacity' $detail
    }
} catch { Add-Check FAIL 'Capacity' $_.Exception.Message }

# Portal outcomes need dated, case-bound captures, not a command-line switch alone.
if ($Recording) {
    try {
        $recordFile = Join-Path $script:L15State 'portal-rehearsal.json'
        if (-not (Test-Path -LiteralPath $recordFile)) { throw 'No portal-rehearsal.json. Complete the observed outcome record described in prep.' }
        $record = Get-Content -LiteralPath $recordFile -Raw | ConvertFrom-Json -Depth 30
        $proof = Test-L15PortalEvidence -Evidence $record -Case $case -Config $cfg -EvidenceRoot $script:L15Evidence `
            -PluginSha256 (Get-FileHash (Join-Path $script:L15Lab $cfg.plugin.file) -Algorithm SHA256).Hash `
            -CapacityKind $(if ($IncludedCapacity) { 'included' } else { 'paid' })
        Add-Check $(if ($proof.passed) { 'PASS' } else { 'FAIL' }) 'Copilot execution' $proof.detail
    } catch { Add-Check FAIL 'Copilot execution' $_.Exception.Message }
} else { Add-Check INFO 'Copilot execution' 'Baseline checks do not prove portal configuration, an imported plugin, a Copilot answer or an agent run. Use -Recording after rehearsal.' }

$fail = @($results | Where-Object status -eq 'FAIL').Count
$warn = @($results | Where-Object status -eq 'WARN').Count
[void](Write-L15Evidence ($(if ($Recording) { 'test-recording' } else { 'test' })) ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); recording = [bool]$Recording; results = $results }))
Write-Host ''
Write-Host ("{0}: {1} failed, {2} warnings." -f $(if ($fail) { 'NOT READY' } elseif ($Recording) { 'RECORDING EVIDENCE PASS' } else { 'BASELINE CHECKS PASS; RECORDING NOT CERTIFIED' }), $fail, $warn)
if ($fail) { exit 1 }
