<#
.SYNOPSIS
Opens or closes the Lesson 3 Defender scan window around a demo: plans, runner power, auto-shutdown.

.DESCRIPTION
Sections 3.2 and 3.3 show live Defender evidence. On 2026-10-10 the CloudPosture, VirtualMachines and
KeyVaults plans all read Free, so the SSH-key recommendation on vm-sc500-l03-runner was gone and regulatory
compliance assessments weren't available. The September 26 Key Vault alerts were still listed.

  Status  Reads the plans, the runner's power state and its auto-shutdown. Changes nothing. (Default.)
  Open    Saves the current plan state as private evidence, deploys infra/lesson-03/defender-plans.bicep
          with state=TakeReady (Defender CSPM with agentless VM scanning, Defender for Key Vault), deploys
          infra/auto-shutdown.bicep with status=Disabled for the runner, and starts the runner. Agentless
          scanning reads disk snapshots once every 24 hours, and the VM has to be running during that
          cycle. It needs no network egress, so no NAT is created.
  Close   Deallocates the runner and removes any temporary egress through Stop-L03Lab.ps1, redeploys the
          runner's auto-shutdown as Enabled, and deploys defender-plans.bicep with state=Parked.

The templates are the single declaration of both states (see infra/DEMO-STATE-L01-L03.md). With -WhatIf,
the script runs ARM what-if for each template instead of deploying, and doesn't start or stop the VM.
VirtualMachines (Defender for Servers) is left exactly as found. Every change is read back; a mismatch stops
the script.

Grounding (checked 2026-10-10):
  https://learn.microsoft.com/azure/defender-for-cloud/secrets-scanning-servers
  https://learn.microsoft.com/azure/defender-for-cloud/enable-agentless-scanning-vms
  https://learn.microsoft.com/azure/defender-for-cloud/concept-cloud-security-posture-management

.PARAMETER State
Status, Open or Close.

.EXAMPLE
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\lesson-03\Set-L03ScanWindow.ps1 -State Open -WhatIf

.EXAMPLE
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\lesson-03\Set-L03ScanWindow.ps1 -State Close
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Status', 'Open', 'Close')][string]$State = 'Status')

. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
$sub = $script:L03Config.subscriptionId
$rg = $script:L03Config.resourceGroup
$vmName = $script:L03Config.vmName
[void](Assert-L03Group $rg)
$pricing = "/subscriptions/$sub/providers/Microsoft.Security/pricings/"
$api = '?api-version=2024-01-01'
$schedule = "shutdown-computevm-$vmName"
$plansTemplate = Join-Path $script:L03Root 'infra/lesson-03/defender-plans.bicep'
$shutdownTemplate = Join-Path $script:L03Root 'infra/auto-shutdown.bicep'

function Get-L03Plan([string]$Name) {
    # Hashtable keeps optional properties readable under StrictMode.
    $p = Invoke-L03Arm -Path ($pricing + $Name + $api) -AsHashtable
    $props = $p['properties']
    $agentless = @($props['extensions'] | Where-Object { $_ -and $_['name'] -eq 'AgentlessVmScanning' } |
        ForEach-Object { $_['isEnabled'] })
    [pscustomobject]@{
        plan      = $Name
        tier      = $props['pricingTier']
        subPlan   = $props['subPlan']
        agentless = if ($agentless.Count) { $agentless[0] } else { $null }
        raw       = $p
    }
}

function Get-L03Window {
    $vm = Invoke-L03Az @('vm', 'show', '--show-details', '--name', $vmName, '--resource-group', $rg)
    $sched = Invoke-L03Az @('resource', 'show', '--resource-group', $rg, '--name', $schedule,
        '--resource-type', 'Microsoft.DevTestLab/schedules')
    [pscustomobject]@{
        plans    = @('CloudPosture', 'KeyVaults', 'VirtualMachines' | ForEach-Object { Get-L03Plan $_ })
        power    = $vm.powerState
        shutdown = $sched.properties.status
    }
}

function Show-L03Window($w) {
    $w.plans | ForEach-Object { Write-Host ('  {0,-16} {1,-9} subPlan={2} agentlessVmScanning={3}' -f $_.plan, $_.tier, $_.subPlan, $_.agentless) }
    Write-Host ('  {0,-16} {1}' -f $vmName, $w.power)
    Write-Host ('  {0,-16} auto-shutdown {1} (23:00 Central)' -f 'schedule', $w.shutdown)
}

function Show-L03WhatIf($Preview, [string]$Label) {
    # Report what ARM would change, ignoring service-computed noise such as notificationSettings.hasWebhook.
    $noise = @('properties.notificationSettings.hasWebhook')
    $lines = foreach ($c in @($Preview.changes | Where-Object { $_.changeType -notin 'NoChange', 'Ignore' })) {
        $real = @($c.delta | Where-Object { $_.path -notin $noise })
        if ($c.changeType -eq 'Modify' -and -not $real.Count) { continue }
        $paths = @($real | ForEach-Object { '{0} {1}' -f $_.path, $_.propertyChangeType }) -join '; '
        '    {0} {1}  {2}' -f $c.changeType, ($c.resourceId -replace '^.*/providers/', ''), $paths
    }
    Write-Host "  what-if $Label : $(if (@($lines).Count) { '' } else { 'no change' })"
    $lines | ForEach-Object { Write-Host $_ }
}

function Set-L03Plans([ValidateSet('TakeReady', 'Parked')][string]$PlanState) {
    $common = @('--location', $script:L03Config.location, '--name', "sc500-l03-defender-plans-$($PlanState.ToLower())",
        '--template-file', $plansTemplate, '--parameters', "state=$PlanState")
    if ($WhatIfPreference) {
        Show-L03WhatIf (Invoke-L03Az (@('deployment', 'sub', 'what-if', '--no-pretty-print') + $common)) "defender-plans state=$PlanState"
        return
    }
    $result = Invoke-L03Az (@('deployment', 'sub', 'create') + $common)
    [void](Write-L03Evidence "defender-plans-$($PlanState.ToLower())" $result)
    $want = if ($PlanState -eq 'TakeReady') { 'Standard' } else { 'Free' }
    foreach ($name in 'KeyVaults', 'CloudPosture') {
        $after = Get-L03Plan $name
        if ($after.tier -ne $want) { throw "$name reads $($after.tier) after the deployment, expected $want." }
        Write-Host "  $name now $($after.tier)"
    }
}

function Set-L03Shutdown([ValidateSet('Enabled', 'Disabled')][string]$Status) {
    $common = @('--resource-group', $rg, '--name', "sc500-l03-runner-autoshutdown-$($Status.ToLower())",
        '--template-file', $shutdownTemplate, '--parameters', "vmName=$vmName", "status=$Status")
    if ($WhatIfPreference) {
        Show-L03WhatIf (Invoke-L03Az (@('deployment', 'group', 'what-if', '--no-pretty-print') + $common)) "auto-shutdown status=$Status"
        return
    }
    [void](Invoke-L03Az (@('deployment', 'group', 'create') + $common))
    $after = Invoke-L03Az @('resource', 'show', '--resource-group', $rg, '--name', $schedule, '--resource-type', 'Microsoft.DevTestLab/schedules')
    if ($after.properties.status -ne $Status) { throw "Auto-shutdown reads $($after.properties.status), expected $Status." }
    Write-Host "  auto-shutdown $Status"
}

$before = Get-L03Window
Write-Host "BEFORE ($State)"
Show-L03Window $before
if ($State -eq 'Status') { return }

if ($WhatIfPreference) { Write-Host "`nDry run (-WhatIf): ARM what-if only; nothing is deployed, started or stopped." }
else {
    # Keep the exact prior plan payloads so any change can be compared or reversed by hand.
    [void](Write-L03Evidence ("defender-plans-before-scan-window-$($State.ToLower())") @($before.plans | ForEach-Object { $_.raw }))
}

if ($State -eq 'Open') {
    Set-L03Plans 'TakeReady'
    Set-L03Shutdown 'Disabled'
    if ($WhatIfPreference) { Write-Host "  would start $vmName (no NAT; scanning reads disk snapshots)"; return }
    if ($before.power -ne 'VM running') { [void](Invoke-L03Az @('vm', 'start', '--name', $vmName, '--resource-group', $rg)) }
    Write-Host "`nScan window OPEN. Allow up to 24 hours, then check before the demo:"
    Write-Host '  pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\lesson-03\Get-L03DetectionEvidence.ps1'
    Write-Host '  (secretFindingCount should be 1 or more; zero means the scan has not reported yet)'
}

if ($State -eq 'Close') {
    if ($WhatIfPreference) { Write-Host "  would run Stop-L03Lab.ps1 (deallocate $vmName, remove temporary egress)" }
    else { & (Join-Path $PSScriptRoot 'Stop-L03Lab.ps1') }
    Set-L03Shutdown 'Enabled'
    Set-L03Plans 'Parked'
    if ($WhatIfPreference) { return }
    Write-Host "`nScan window CLOSED."
}

Write-Host "`nAFTER"
Show-L03Window (Get-L03Window)
