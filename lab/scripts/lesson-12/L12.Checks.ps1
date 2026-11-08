<#
.SYNOPSIS
    Pure evidence checks for L12, separated so failures can be tested without changing Azure.
.DESCRIPTION
    A denied request, a stale tag, or a configured switch alone cannot prove the lesson outcome.
#>
function ConvertTo-L12UtcTime {
    param([Parameter(Mandatory)]$Value)
    # JSON may already have parsed a timestamp; avoid converting it through localized display text.
    if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
    if ($Value -is [DateTime]) { return [DateTimeOffset]::new($Value.ToUniversalTime()) }
    return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
}
function Get-L12KeyProbeOutcome {
    param([int]$ExitCode, [string]$ErrorText)
    if ($ExitCode -eq 0) { return 'ALLOWED' }
    if ($ErrorText -match 'KeyBasedAuthenticationNotPermitted|Key based authentication is not permitted') { return 'KEY AUTH DISABLED' }
    return 'ERROR: refusal cause not established'
}
function Test-L12RemediationProof {
    param($Before, $After, [bool]$SharedKeyDisabled, [int]$EntraExitCode)
    return ($Before.outcome -eq 'ALLOWED' -and $After.outcome -eq 'KEY AUTH DISABLED' -and
        $SharedKeyDisabled -and $EntraExitCode -eq 0)
}
function Test-L12StorageOverride {
    param($Setting, [int]$Cap)
    return ($null -ne $Setting -and $Setting.isEnabled -eq $true -and $Setting.overrideSubscription -eq $true -and
        $Setting.malwareScanningOnUpload -eq $true -and $Setting.capGBPerMonth -eq $Cap -and $Setting.sensitiveDataDiscovery -eq $true)
}
function Test-L12FreshCleanScan {
    param($Tags, [DateTimeOffset]$UploadedUtc)
    $stamp = Get-L12Value $Tags 'Malware Scanning scan time UTC'
    $verdict = Get-L12Value $Tags 'Malware Scanning scan result'
    if (-not $stamp -or $verdict -ne 'No threats found') { return $false }
    try { return (ConvertTo-L12UtcTime $stamp) -ge $UploadedUtc.AddSeconds(-1) } catch { return $false }
}
function Test-L12ResetScope {
    param([array]$Containers, [array]$Assignments, [string]$Container, [string]$AssignmentKey)
    # Refuse unfamiliar state before removing anything or restoring the intentionally weak setting.
    return (@($Containers | Where-Object { $_ -ne $Container }).Count -eq 0 -and
        @($Assignments | Where-Object { $_.name -ne $AssignmentKey }).Count -eq 0)
}
function Get-L12AssessmentGate {
    param([string]$Status, [bool]$Recording)
    if ($Status -eq 'Unhealthy') { return 'PASS' }
    if ($Recording) { return 'FAIL' }
    return 'WARN'
}
function Test-L12AssignmentProof {
    <# .SYNOPSIS Rejects a successful write whose readback does not match the intended assignment. #>
    param($Assignment, [string]$ExpectedId, [string]$Owner, [DateTimeOffset]$DueUtc)
    # A 2xx write or an assignment on a different finding cannot close the governance demonstration.
    if ((Get-L12Value $Assignment 'id') -ne $ExpectedId -or
        (Get-L12Value $Assignment 'properties.owner') -ne $Owner -or
        (Get-L12Value $Assignment 'properties.isGracePeriod') -ne $true -or
        (Get-L12Value $Assignment 'properties.governanceEmailNotification.disableManagerEmailNotification') -ne $true -or
        (Get-L12Value $Assignment 'properties.governanceEmailNotification.disableOwnerEmailNotification') -ne $true) { return $false }
    try { return (ConvertTo-L12UtcTime (Get-L12Value $Assignment 'properties.remediationDueDate')) -eq $DueUtc }
    catch { return $false }
}
