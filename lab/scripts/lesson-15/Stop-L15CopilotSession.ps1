<#
.SYNOPSIS
    Your step when you finish Lesson 15: deletes the Security Copilot capacity in the guarded
    group now and confirms it's gone, so provisioned billing stops at the end of the current hour.
.DESCRIPTION
    Deleting the capacity is permanent and can't be undone, and Security Copilot can't run prompts
    until a capacity is associated again. The workspace, its settings, and its owners and contributors
    are Security Copilot configuration; this script doesn't touch them. Microsoft's privacy page says
    customer data is deleted within 180 days of deleting all provisioned capacity. For the next session,
    create a capacity again and associate it in Owner settings (see the prep page); what carries over is
    a rehearsal observation, not something this script promises. Confirmation is required
    (ConfirmImpact High).
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Stop-L15CopilotSession.ps1
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()
. (Join-Path $PSScriptRoot 'L15.Common.ps1')
$cfg = $script:L15Config
[void](Assert-L15Context)
$caps = @(Get-L15Capacities)
if (-not $caps) { Write-Host 'No paid Security Copilot capacity exists in this subscription. Other resource charges are separate.'; return }
$deleted = @()
foreach ($c in $caps) {
    if (-not $c.guarded -or $c.name -ne $cfg.copilot.capacityName) { Write-Host "$($c.name) is not this lesson's named capacity; left unchanged."; continue }
    $est = Get-L15ProvisionedEstimate $c
    if (-not $PSCmdlet.ShouldProcess("$($c.name) in $($c.resourceGroup)", 'Delete the Security Copilot capacity (permanent)')) { continue }
    [void](Invoke-L15Rest -Method delete -Path "$($c.id)?api-version=$($cfg.copilot.capacityApiVersion)")
    $gone = $false
    foreach ($i in 1..20) {
        Start-Sleep -Seconds 6
        if (-not (Invoke-L15Rest -AllowNotFound -Path "$($c.id)?api-version=$($cfg.copilot.capacityApiVersion)")) { $gone = $true; break }
    }
    Write-Host ("{0}: {1}" -f $c.name, $(if ($gone) { 'deleted.' } else { 'delete requested; still visible after 2 minutes. Run Invoke-L15CopilotDemo.ps1 -Mode Capacity to check again.' }))
    if ($est) { Write-Host ("  Retail estimate for provisioned units: {0} SCU x {1} started hours = about `${2}, before credits and tax. Overage isn't included." -f $est.units, $est.startedHours, $est.usd) }
    $deleted += [ordered]@{ name = $c.name; id = $c.id; gone = $gone; estimate = $est }
}
[void](Write-L15Evidence 'session-stop' ([ordered]@{ stoppedUtc = [DateTime]::UtcNow.ToString('o'); capacities = $deleted }))
if (@($deleted | Where-Object { -not $_.gone }).Count) { throw 'Capacity deletion was requested but not confirmed. Billing may continue; inspect the recorded resource ID.' }
