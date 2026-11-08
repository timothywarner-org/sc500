<#
.SYNOPSIS
    Your step after you create the Security Copilot capacity: puts a deadline on it, so the reaper
    deletes it when the session is over.
.DESCRIPTION
    Provisioned Security Compute Units bill every hour a capacity exists. Microsoft recommends deleting
    capacity you aren't using during testing and recreating it when you need it. So a Lesson 15 session is:
      1. Deploy-L15Lab.ps1 -Deploy (once): the guarded group and the reaper.
      2. You create the capacity in the Security Copilot portal (first run or Owner settings) in
         rg-secopscopilot-shared-eastus2, with the units and overage cap in the prep page.
      3. This script: finds that capacity, tags it sc500-expiresUtc = now + Hours, and prints the
         deadline and the retail estimate.
      4. Stop-L15CopilotSession.ps1 when you finish. If nobody runs it, the reaper deletes the
         capacity at the deadline (within one reaper interval).
    Running it again extends the deadline from now. It never creates or resizes a capacity, and it
    manages only this lesson's named capacity in the guarded group, because the reaper is scoped there.
.PARAMETER Hours Session length from now, 1 to the configured maximum (8).
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Start-L15CopilotSession.ps1 -Hours 1
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateRange(1, 8)][int]$Hours = 1)
. (Join-Path $PSScriptRoot 'L15.Common.ps1')
$cfg = $script:L15Config
[void](Assert-L15Context)
if ($Hours -gt [int]$cfg.copilot.session.maxHours) { throw "The lab's maximum session is $($cfg.copilot.session.maxHours) hours." }
$lab = Get-L15Outputs
if (-not $lab) { throw 'The reaper isn''t deployed. Run Deploy-L15Lab.ps1 -Deploy first, then create the capacity.' }
$workflow = Invoke-L15Rest -Path "$($lab.reaperId)?api-version=2019-05-01"
$lastRun = @((Invoke-L15Rest -Path "$($lab.reaperId)/runs?api-version=2019-05-01&`$top=1").value) | Select-Object -First 1
if ($workflow.properties.state -ne 'Enabled' -or -not $lastRun -or $lastRun.properties.status -ne 'Succeeded' -or
    [DateTimeOffset]$lastRun.properties.startTime -lt [DateTimeOffset]::UtcNow.AddMinutes(-90)) {
    throw 'The deletion safeguard must be enabled with a recent successful run before starting a paid session.'
}

$caps = @(Get-L15Capacities)
$outside = @($caps | Where-Object { -not $_.guarded })
if ($outside) {
    Write-Host 'Other capacities exist outside the Lesson 15 group. This script leaves them unchanged.'
}
$guarded = @($caps | Where-Object { $_.guarded -and $_.name -eq $cfg.copilot.capacityName })
if (-not $guarded) { throw "No capacity in $($cfg.resourceGroup) yet. Create it in the Security Copilot portal first (see the Lesson 15 prep page)." }

$deadline = [DateTime]::UtcNow.AddHours($Hours).ToString('yyyy-MM-ddTHH:mm:ssZ')
$applied = @()
foreach ($c in $guarded) {
    if (-not $PSCmdlet.ShouldProcess($c.name, "Set $($cfg.reaper.expiryTag)=$deadline")) { continue }
    # Merge keeps any tags the portal set; only the expiry tag changes.
    [void](Invoke-L15Az @('tag', 'update', '--resource-id', $c.id, '--operation', 'Merge', '--tags', "$($cfg.reaper.expiryTag)=$deadline", "managedBy=$($cfg.managedBy)") )
    # A CLI success alone does not prove the deadline the service retained.
    $readback = Invoke-L15Rest -Path "$($c.id)?api-version=$($cfg.copilot.capacityApiVersion)"
    if ((Get-L15Value $readback "tags.$($cfg.reaper.expiryTag)") -ne $deadline) { throw 'Expiry tag readback differs from the requested deadline.' }
    $applied += [ordered]@{id=$c.id;deadlineUtc=$deadline;readbackVerified=$true}
    $est = Get-L15ProvisionedEstimate $c
    $perHour = if ($est) { $est.units * [double]$cfg.copilot.provisionedUsdPerUnitHour } else { $null }
    Write-Host ("{0}: the reaper deletes it after {1} UTC." -f $c.name, $deadline)
    if ($perHour) { Write-Host ("  Provisioned: {0} SCU, about `${1} retail per started hour. {2} hours from creation so far." -f $est.units, $perHour, $est.startedHours) }
}
if ($applied.Count) { [void](Write-L15Evidence 'session-start' ([ordered]@{ startedUtc = [DateTime]::UtcNow.ToString('o'); deadlineUtc = $deadline; capacities = $applied })) }
Write-Host 'When you finish, run Stop-L15CopilotSession.ps1 instead of waiting for the deadline.'
