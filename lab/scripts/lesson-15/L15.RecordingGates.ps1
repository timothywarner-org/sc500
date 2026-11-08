<#
.SYNOPSIS
    Pure checks for Lesson 15 capacity and observed portal evidence.
.DESCRIPTION
    A passing KQL query outside Copilot cannot prove a Copilot response. Keep these
    checks separate so a missing, stale, or mismatched rehearsal fails closed.
#>
function Test-L15CapacityDeadline {
    <# .SYNOPSIS Requires an explicit future UTC deadline with enough time for the demo. #>
    param($Capacity, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow, [int]$MinimumMinutes = 45)
    $value = [string](Get-L15Value $Capacity 'expiresUtc')
    $parsed = [DateTimeOffset]::MinValue
    $ok = $value -match '(Z|\+00:00)$' -and [DateTimeOffset]::TryParse($value, [ref]$parsed)
    $minutes = if ($ok) { ($parsed - $Now).TotalMinutes } else { -1 }
    [pscustomobject]@{ passed = [bool]($ok -and $minutes -ge $MinimumMinutes)
        detail = if (-not $ok) { 'Missing or invalid explicit UTC expiry tag; run Start-L15CopilotSession.ps1.' }
                 elseif ($minutes -lt $MinimumMinutes) { "Only $([math]::Floor($minutes)) minutes remain; at least $MinimumMinutes are required." }
                 else { "$([math]::Floor($minutes)) minutes remain before the deadline; deletion may follow by one reaper interval." } }
}

function Test-L15PortalEvidence {
    <#
    .SYNOPSIS Validates a dated human/agent inspection record and its captured evidence files.
    .DESCRIPTION This validates the record's integrity, not the semantic truth of a screenshot.
                 The reviewer must inspect each captured outcome before marking it observed.
    #>
    param($Evidence, $Case, $Config, [string]$PluginSha256, [string]$EvidenceRoot,
          [ValidateSet('paid','included')][string]$CapacityKind,
          [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
    $issues = [Collections.Generic.List[string]]::new()
    foreach ($pair in @(@('tenantId',$Config.tenantId), @('operatorUpn',$Config.operatorUpn),
        @('incidentName',$Case.incidentName), @('fixtureId',$Case.fixtureId),
        @('pluginSha256',$PluginSha256), @('capacityKind',$CapacityKind))) {
        if ((Get-L15Value $Evidence $pair[0]) -ne $pair[1]) { $issues.Add("Mismatched or missing $($pair[0])") }
    }
    $stamp = [DateTimeOffset]::MinValue
    $dated = [DateTimeOffset]::TryParse([string](Get-L15Value $Evidence 'observedUtc'), [ref]$stamp)
    if (-not $dated -or $stamp -gt $Now.AddMinutes(5) -or $stamp -lt $Now.AddHours(-24)) { $issues.Add('Portal rehearsal must be dated within the last 24 hours') }
    # These are the actual demo outcomes, not merely available menu headings.
    foreach ($name in @('workspaceCapacity','roles','pluginImported','pluginAnswer','incidentSummary','guidedResponse','analystAgent','claimReview')) {
        $row = Get-L15Value $Evidence "checks.$name"
        if ((Get-L15Value $row 'status') -ne 'observed' -or -not (Get-L15Value $row 'detail')) { $issues.Add("Missing observed $name"); continue }
        $file = [string](Get-L15Value $row 'file')
        $digest = [string](Get-L15Value $row 'sha256')
        try {
            $root = [IO.Path]::GetFullPath($EvidenceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            $path = [IO.Path]::GetFullPath((Join-Path $root $file))
            if (-not $file -or -not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-Path -LiteralPath $path -PathType Leaf) -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $digest) { $issues.Add("Missing or changed capture for $name") }
        } catch { $issues.Add("Invalid capture for $name") }
    }
    [pscustomobject]@{ passed = $issues.Count -eq 0; detail = if ($issues.Count) { $issues -join '; ' } else { 'Dated portal rehearsal and captured outcomes match this operator, case, fixture and plugin. Human delivery remains separate.' } }
}
