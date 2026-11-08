<#
.SYNOPSIS
Opens or closes the Lesson 4 Defender window around a recording: plans, account settings, vulnerability assessment.

.DESCRIPTION
Sections 4.2 and 4.4 show live Defender for Storage and Defender for Azure SQL evidence. On 2026-10-10 the
StorageAccounts, SqlServers, SqlServerVirtualMachines, OpenSourceRelationalDatabases and CosmosDbs plans all read
Free: Test-L04Lab.ps1 failed 12 checks, vulnerability assessment on the lesson server read Disabled, and
Reset-L04Lab.ps1 can't run, because it applies the subscription's Storage V2 settings to each account and throws
when that plan is off. The September 26 storage malware alert and SQL sample alerts were still listed.

  Status  Reads the five plans, both accounts' Defender for Storage settings, and vulnerability assessment on the
          lesson server. Changes nothing. (Default.)
  Open    Saves the current plan state as private evidence, deploys infra/lesson-04/defender-plans.bicep with
          state=TakeReady, deploys infra/lesson-04/sql-vulnerability-assessment.bicep with state=Enabled, runs
          Reset-L04Lab.ps1 (CTSO-L04-BASELINE, which applies the plan to both accounts explicitly), then starts an
          on-demand vulnerability assessment scan. Idempotent: run it again if a step reports it isn't ready yet.
  Close   Runs Reset-L04Lab.ps1 while the Storage plan is still on (removes the take's test uploads, the
          workstation IP rule and the intake override), then deploys defender-plans.bicep with state=Parked.

The templates are the single declaration of both states (see infra/DEMO-STATE-L04.md). With -WhatIf, the script
runs ARM what-if for each template instead of deploying, and doesn't reset the lab or start a scan. Every plan
change is read back; a mismatch stops the script. No resource is created or deleted.


The lab subscription, 2026-10-20: every plan read Free with its 30-day trial still available, so the first Open starts
each plan's trial. The subscription held five storage accounts (three outside Lesson 4) and one Cosmos DB account,
cosmos-ptgdgyrjdxfo4 in rg-mcp-oct-2026, which the CosmosDbs plan would also cover. It's outside this course, so
mention it to you before the first Open.

Grounding (checked 2026-10-10):
  https://learn.microsoft.com/azure/defender-for-cloud/faq-defender-for-storage
  https://learn.microsoft.com/azure/defender-for-cloud/sql-azure-vulnerability-assessment-enable
  https://learn.microsoft.com/rest/api/sql/database-sql-vulnerability-assessment-execute-scan/execute

.PARAMETER State
Status, Open or Close.

.EXAMPLE
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\lesson-04\Set-L04DefenderWindow.ps1 -State Open -WhatIf

.EXAMPLE
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\lesson-04\Set-L04DefenderWindow.ps1 -State Close
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Status', 'Open', 'Close')][string]$State = 'Status')

. (Join-Path $PSScriptRoot 'L04.Common.ps1')
[void](Assert-L04Context)
$lab = Get-L04Outputs
$sub = $script:L04Config.subscriptionId
$rg = $script:L04Config.resourceGroup
$planNames = @('StorageAccounts', 'SqlServers', 'SqlServerVirtualMachines', 'OpenSourceRelationalDatabases', 'CosmosDbs')
$plansTemplate = Join-Path $script:L04Lab 'infra/lesson-04/defender-plans.bicep'
$vaTemplate = Join-Path $script:L04Lab 'infra/lesson-04/sql-vulnerability-assessment.bicep'
$dfsApi = 'api-version=2025-06-01'

function Get-L04Plan([string]$Name) {
    # Hashtable keeps optional properties (subPlan, extensions) readable under StrictMode.
    $p = Invoke-L04Arm -Path "/subscriptions/$sub/providers/Microsoft.Security/pricings/$($Name)?api-version=2024-01-01" -AsHashtable
    $props = $p['properties']
    $ext = @($props['extensions'] | Where-Object { $_ -and [string]$_['isEnabled'] -eq 'True' } | ForEach-Object { $_['name'] }) -join ', '
    [pscustomobject]@{ plan = $Name; tier = $props['pricingTier']; subPlan = $props['subPlan']; extensions = $ext; raw = $p }
}

function Get-L04Window {
    $accounts = foreach ($pair in @(@('records', $lab.recordsId), @('intake', $lab.intakeId))) {
        $s = Invoke-L04Arm -Path "$($pair[1])/providers/Microsoft.Security/defenderForStorageSettings/current?$dfsApi"
        [pscustomobject]@{
            account   = $pair[0]
            enabled   = Get-L04Value $s 'properties.isEnabled'
            override  = Get-L04Value $s 'properties.overrideSubscriptionLevelSettings'
            malware   = Get-L04Value $s 'properties.malwareScanning.onUpload.isEnabled'
            sensitive = Get-L04Value $s 'properties.sensitiveDataDiscovery.isEnabled'
        }
    }
    $va = Invoke-L04Arm -Path "$($lab.sqlServerId)/sqlVulnerabilityAssessments/default?api-version=2023-08-01"
    [pscustomobject]@{
        plans    = @($planNames | ForEach-Object { Get-L04Plan $_ })
        accounts = @($accounts)
        va       = Get-L04Value $va 'properties.state'
    }
}

function Show-L04Window($w) {
    $w.plans | ForEach-Object { Write-Host ('  {0,-30} {1,-9} subPlan={2} {3}' -f $_.plan, $_.tier, $_.subPlan, $_.extensions) }
    $w.accounts | ForEach-Object { Write-Host ('  {0,-30} enabled={1} override={2} malwareOnUpload={3} sensitiveData={4}' -f "account $($_.account)", $_.enabled, $_.override, $_.malware, $_.sensitive) }
    Write-Host ('  {0,-30} {1}' -f 'SQL vulnerability assessment', $w.va)
}

function Show-L04WhatIf($Preview, [string]$Label) {
    # Report what ARM would change, leaving out NoChange and Ignore rows.
    $lines = foreach ($c in @($Preview.changes | Where-Object { $_.changeType -notin 'NoChange', 'Ignore' })) {
        $paths = @($c.delta | ForEach-Object { '{0} {1}' -f $_.path, $_.propertyChangeType }) -join '; '
        '    {0} {1}  {2}' -f $c.changeType, ($c.resourceId -replace '^.*/providers/', ''), $paths
    }
    Write-Host "  what-if $Label : $(if (@($lines).Count) { '' } else { 'no change' })"
    $lines | ForEach-Object { Write-Host $_ }
}

function Set-L04Plans([ValidateSet('TakeReady', 'Parked')][string]$PlanState) {
    $common = @('--location', $script:L04Config.location, '--name', "sc500-l04-defender-plans-$($PlanState.ToLower())",
        '--template-file', $plansTemplate, '--parameters', "state=$PlanState")
    if ($WhatIfPreference) {
        Show-L04WhatIf (Invoke-L04Az (@('deployment', 'sub', 'what-if', '--no-pretty-print') + $common)) "defender-plans state=$PlanState"
        return
    }
    $result = Invoke-L04Az (@('deployment', 'sub', 'create') + $common)
    [void](Write-L04Evidence "defender-plans-$($PlanState.ToLower())" $result)
    $want = if ($PlanState -eq 'TakeReady') { 'Standard' } else { 'Free' }
    foreach ($name in $planNames) {
        $after = Get-L04Plan $name
        if ($after.tier -ne $want) { throw "$name reads $($after.tier) after the deployment, expected $want." }
    }
    Write-Host "  all five plans now $want"
}

function Set-L04VulnerabilityAssessment {
    $common = @('--resource-group', $rg, '--name', 'sc500-l04-sql-va-enabled', '--template-file', $vaTemplate,
        '--parameters', "serverName=$($lab.sqlServer)", 'state=Enabled')
    if ($WhatIfPreference) {
        Show-L04WhatIf (Invoke-L04Az (@('deployment', 'group', 'what-if', '--no-pretty-print') + $common)) 'sql-vulnerability-assessment state=Enabled'
        return
    }
    # Express configuration needs the SQL plan; give the plan change a few minutes to land before giving up.
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try { [void](Invoke-L04Az (@('deployment', 'group', 'create') + $common)); break }
        catch {
            if ($attempt -eq 6) { throw }
            Write-Host "  vulnerability assessment not accepted yet (attempt $attempt of 6); retrying in 30 seconds"
            Start-Sleep -Seconds 30
        }
    }
    $va = Invoke-L04Arm -Path "$($lab.sqlServerId)/sqlVulnerabilityAssessments/default?api-version=2023-08-01"
    if ((Get-L04Value $va 'properties.state') -ne 'Enabled') { throw 'Vulnerability assessment did not read back Enabled.' }
    Write-Host '  SQL vulnerability assessment Enabled (express)'
}

function Start-L04VaScan {
    # On-demand scan of servicehub-records, so VaResults has a scan to read on take day. The service answers
    # 202 Accepted and scans in the background; a failure here is reported, never treated as a finding.
    $path = "$($lab.sqlServerId)/databases/$($lab.sqlDatabase)/sqlVulnerabilityAssessments/default/initiateScan?api-version=2025-01-01"
    try {
        [void](Invoke-L04Arm -Path $path -Method POST)
        Write-Host '  on-demand vulnerability assessment scan started on servicehub-records'
    }
    catch {
        Write-Host "  WARN: the scan didn't start ($($_.Exception.Message)). Run -State Open again in a few minutes."
    }
}

function Invoke-L04Reset {
    if ($WhatIfPreference) { Write-Host '  would run Reset-L04Lab.ps1 (CTSO-L04-BASELINE; applies the Storage plan to both accounts)'; return }
    & (Join-Path $PSScriptRoot 'Reset-L04Lab.ps1')
}

$before = Get-L04Window
Write-Host "BEFORE ($State)"
Show-L04Window $before
if ($State -eq 'Status') { return }

if ($WhatIfPreference) { Write-Host "`nDry run (-WhatIf): ARM what-if only; nothing is deployed, reset or scanned." }
else {
    # Keep the exact prior plan payloads so any change can be compared or reversed by hand.
    [void](Write-L04Evidence ("defender-plans-before-window-$($State.ToLower())") @($before.plans | ForEach-Object { $_.raw }))
}

if ($State -eq 'Open') {
    Set-L04Plans 'TakeReady'
    Set-L04VulnerabilityAssessment
    Invoke-L04Reset
    if ($WhatIfPreference) { Write-Host '  would start an on-demand vulnerability assessment scan on servicehub-records'; return }
    Start-L04VaScan
    Write-Host "`nDefender window OPEN. About 10 minutes later, before the take:"
    Write-Host '  pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\lesson-04\Test-L04Lab.ps1'
    Write-Host '  (every check should PASS; then Invoke-L04DefenderDemo.ps1 -Mode VaResults should list VA1143)'
}

if ($State -eq 'Close') {
    $storage = $before.plans | Where-Object plan -eq 'StorageAccounts'
    if ($storage.tier -eq 'Standard') { Invoke-L04Reset }
    else { Write-Host '  Storage plan already Free, so Reset-L04Lab.ps1 is skipped; open the window to reset the lab.' }
    Set-L04Plans 'Parked'
    if ($WhatIfPreference) { return }
    Write-Host "`nDefender window CLOSED."
}

Write-Host "`nAFTER"
Show-L04Window (Get-L04Window)
