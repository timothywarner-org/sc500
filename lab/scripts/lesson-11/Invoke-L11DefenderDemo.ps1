<#
.SYNOPSIS
    SC-500 demos 11.2 and 11.4: read Defender for AI Services coverage, the AI alerts it raised
    for ServiceHub's Foundry resource, and the audit evidence around them. Read-only.
.DESCRIPTION
    Modes (each saves a dated evidence file under lab/.azure/lesson-11/evidence/):
      Plan     The subscription's Defender for AI Services plan (pricing "AI"): tier, trial state,
               and components, plus the Foundry resource's own Defender for AI setting. It never
               changes a plan; you turn components on or off in the portal if you choose.
      Alerts   Defender for Cloud alerts on the lab's Foundry resource (alert types AI.*), with
               the fields an investigator correlates on, and a Microsoft Graph read of the
               matching Defender XDR alert and incident when the CLI token is allowed to read it.
      Audit    Control-plane changes from the Activity log (who changed the guardrail and the
               deployment, and when) and the Foundry resource logs in the workspace.
      All      Plan, Alerts, and Audit.
.PARAMETER Mode Plan, Alerts, Audit, or All.
.PARAMETER Hours How far back Alerts and Audit look. Default 24.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Invoke-L11DefenderDemo.ps1 -Mode All
#>
[CmdletBinding()]
param([ValidateSet('Plan', 'Alerts', 'Audit', 'All')][string]$Mode = 'All', [int]$Hours = 24)
. (Join-Path $PSScriptRoot 'L11.Common.ps1')
$cfg = $script:L11Config
[void](Assert-L11Context)
$lab = Get-L11Outputs
$sub = "/subscriptions/$($cfg.subscriptionId)"

if ($Mode -in 'Plan', 'All') {
    Write-Host '== Defender for AI Services, subscription plan'
    $p = Invoke-L11Rest -Path "$sub/providers/Microsoft.Security/pricings/AI?api-version=2024-01-01"
    $ext = @(Get-L11Value $p 'properties.extensions') | Where-Object { $_ } | ForEach-Object { [ordered]@{ name = $_.name; isEnabled = $_.isEnabled } }
    $plan = [ordered]@{ pricingTier = $p.properties.pricingTier; freeTrialRemaining = (Get-L11Value $p 'properties.freeTrialRemainingTime')
                        enablementTime = (Get-L11Value $p 'properties.enablementTime'); extensions = @($ext) }
    Write-Host ("  AI plan: {0}; trial remaining {1}; enabled {2}" -f $plan.pricingTier, $plan.freeTrialRemaining, $plan.enablementTime)
    $ext | ForEach-Object { Write-Host ("    {0} = {1}" -f $_.name, $_.isEnabled) }
    $res = Invoke-L11Rest -AllowNotFound -Path "$($lab.foundryId)/defenderForAISettings?api-version=2025-06-01"
    $resRows = @(@(Get-L11Value $res 'value') | Where-Object { $_ } | ForEach-Object { [ordered]@{ name = $_.name; state = (Get-L11Value $_ 'properties.state') } })
    Write-Host ("  Foundry resource setting: {0}" -f $(if ($resRows) { ($resRows | ForEach-Object { "$($_.name)=$($_.state)" }) -join ', ' } else { 'none returned' }))
    [void](Write-L11Evidence 'defender-plan' ([ordered]@{ subscriptionPlan = $plan; resourceSetting = $resRows; foundry = $lab.foundry }))
}

if ($Mode -in 'Alerts', 'All') {
    Write-Host "== Defender for Cloud alerts on $($lab.foundry), last $Hours hours"
    $since = [DateTime]::UtcNow.AddHours(-$Hours)
    $all = @()
    $next = "$sub/providers/Microsoft.Security/alerts?api-version=2022-01-01"
    while ($next) { $page = Invoke-L11Rest -Path $next; $all += @($page.value); $next = Get-L11Value $page 'nextLink' }
    $mine = $all | Where-Object {
        $_.properties.alertType -like 'AI.*' -and [DateTime]$_.properties.timeGeneratedUtc -ge $since -and
        (@($_.properties.resourceIdentifiers | ForEach-Object { Get-L11Value $_ 'azureResourceId' }) -contains $lab.foundryId -or $_.properties.compromisedEntity -eq $lab.foundry) }
    $rows = @(foreach ($a in ($mine | Sort-Object { $_.properties.timeGeneratedUtc })) {
        $x = $a.properties.extendedProperties
        [ordered]@{
            alert = $a.properties.alertDisplayName; alertType = $a.properties.alertType; severity = $a.properties.severity; status = $a.properties.status
            generatedUtc = $a.properties.timeGeneratedUtc; startUtc = $a.properties.startTimeUtc; systemAlertId = $a.name
            compromisedEntity = $a.properties.compromisedEntity; productName = $a.properties.productName
            tactics = (@($a.properties.intent) -join ', ')
            extended = if ($x) { $keep = [ordered]@{}; foreach ($pp in $x.PSObject.Properties) { if ($pp.Name -match 'application|user|ip|deployment|model|prompt|Resource|investigation') { $keep[$pp.Name] = [string]$pp.Value } }; $keep } else { $null }
            portalLink = $a.properties.alertUri
        }
    })
    if (-not $rows) { Write-Host '  none yet. Defender for AI alerts can take several minutes after the triggering call.' }
    $rows | ForEach-Object { Write-Host ("  {0}  {1}  {2}  {3}" -f $_.generatedUtc, $_.severity, $_.alert, $_.status) }
    # Defender XDR: Defender for Cloud alerts are integrated automatically. Try Microsoft Graph with the
    # CLI's token; if the token can't read security alerts, record that instead of guessing.
    $xdr = $null
    if ($rows) {
        $g = Invoke-L11Az -NoSubscription -AllowFailure @('rest', '--method', 'get', '--url',
            "https://graph.microsoft.com/v1.0/security/alerts_v2?`$filter=serviceSource eq 'microsoftDefenderForCloud' and createdDateTime ge $($since.ToString('yyyy-MM-ddTHH:mm:ssZ'))&`$top=50")
        if ($g.ExitCode -eq 0) {
            $xa = @((($g.Stdout | ConvertFrom-Json).value) | Where-Object { $_.title -like '*Jailbreak*' -or $_.title -like '*AI*' })
            $xdr = @($xa | ForEach-Object { [ordered]@{ title = $_.title; alertId = $_.id; incidentId = $_.incidentId; providerAlertId = $_.providerAlertId; status = $_.status; created = $_.createdDateTime } })
            Write-Host ("  Defender XDR (Graph): {0} matching alert(s)" -f $xdr.Count)
        } else {
            $xdr = "Graph read refused: $((($g.Stderr -split "`n")[0]).Trim())"
            Write-Host "  $xdr"
        }
    }
    [void](Write-L11Evidence 'defender-alerts' ([ordered]@{ foundry = $lab.foundry; sinceUtc = $since.ToString('o'); alerts = $rows; defenderXdr = $xdr }))
}

if ($Mode -in 'Audit', 'All') {
    Write-Host "== Activity log, $($cfg.resourceGroup), last $Hours hours"
    $acts = Invoke-L11Az @('monitor', 'activity-log', 'list', '--resource-group', $cfg.resourceGroup, '--offset', "$($Hours)h", '--max-events', '500')
    $writes = @($acts | Where-Object { $_.operationName.value -match 'Microsoft\.CognitiveServices/accounts/(raiPolicies|raiBlocklists|deployments|projects)/write|Microsoft\.CognitiveServices/accounts/write' -and $_.status.value -eq 'Succeeded' } |
        Sort-Object eventTimestamp | ForEach-Object { [ordered]@{ operation = $_.operationName.value; caller = $_.caller; timeUtc = $_.eventTimestamp; resource = ($_.resourceId -split '/')[-1]; correlationId = $_.correlationId } })
    $writes | ForEach-Object { Write-Host ("  {0}  {1}  {2}  by {3}" -f $_.timeUtc, $_.operation, $_.resource, $_.caller) }
    Write-Host '== Foundry resource logs in the workspace'
    $q = "AzureDiagnostics | where TimeGenerated > ago($($Hours)h) | where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES' | summarize calls=count(), lastSeen=max(TimeGenerated) by Category, OperationName, ResultSignature | order by Category asc, OperationName asc"
    $r = Invoke-L11Az -AllowFailure @('monitor', 'log-analytics', 'query', '--workspace', $lab.workspaceCustomerId, '--analytics-query', $q)
    $diag = if ($r.ExitCode -eq 0) { $r.Stdout | ConvertFrom-Json } else { "query failed: $((($r.Stderr -split "`n")[0]).Trim())" }
    $diag | Format-Table -AutoSize | Out-String -Width 200 | Out-Host
    [void](Write-L11Evidence 'defender-audit' ([ordered]@{ activityLogWrites = $writes; foundryResourceLogs = $diag }))
}
