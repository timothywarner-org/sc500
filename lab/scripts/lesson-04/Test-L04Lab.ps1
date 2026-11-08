<#
.SYNOPSIS
    Read-only readiness check: is the Lesson 4 lab at CTSO-L04-BASELINE, ready to record?

.DESCRIPTION
    Compares the live configuration with the documented starting checkpoint and prints one
    row per check with PASS, WARN, or FAIL spelled out (never color alone). It changes
    nothing in Azure. If anything FAILs, run Reset-L04Lab.ps1 and check again.

    Baseline, in plain words:
      records account  Shared Key still allowed (the fault demo 4.1 fixes), HTTPS only,
                       TLS 1.2, no public blob access, firewall default Deny with no IP rule.
      intake account   Shared Key off, no per-account Defender override, no test uploads.
      SQL              Entra-only on, TLS 1.2, TDE on, auditing to Log Analytics, vulnerability
                       assessment on, the workstation firewall rule present, three seed rows.
      Defender plans   Storage and Azure SQL plans on at the subscription (read only here).

    Storage data-plane checks are skipped for the records account on purpose: at baseline its
    firewall rejects the workstation, which is the first thing demo 4.1 shows.

.PARAMETER Parked
    For rehearsals and status checks with the Defender window closed. The Defender checks
    (the five plans, protection on both accounts, the vulnerability assessment scanner) report
    PARKED when they read their parked values (Free, False, Disabled), instead of FAIL. PARKED
    is not PASS: it means "closed on purpose", and the demo still needs the window open and a
    run without this switch.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Test-L04Lab.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Test-L04Lab.ps1 -Parked
#>
[CmdletBinding()]
param([switch]$Parked)
. (Join-Path $PSScriptRoot 'L04.Common.ps1')
[void](Assert-L04Context)
$lab = Get-L04Outputs
$rg = $script:L04Config.resourceGroup
$rows = [System.Collections.Generic.List[object]]::new()

function Add-Check([string]$Check, $Expected, $Actual, [ValidateSet('FAIL', 'WARN')][string]$Otherwise = 'FAIL', [string[]]$ParkedValues) {
    $ok = "$Actual" -eq "$Expected"
    # PARKED only with -Parked, and only for a Defender check reading one of its known parked values.
    $parkedHit = $Parked -and -not $ok -and $ParkedValues -and ("$Actual" -in $ParkedValues)
    $result = if ($ok) { 'PASS' } elseif ($parkedHit) { 'PARKED' } else { $Otherwise }
    $rows.Add([pscustomobject]@{ Result = $result; Check = $Check; Expected = "$Expected"; Actual = "$Actual" })
}

# --- Records account (management plane only) ----------------------------------------------
$rec = Invoke-L04Az @('storage', 'account', 'show', '--name', $lab.recordsAccount, '--resource-group', $rg)
Add-Check 'Records: Shared Key allowed (baseline fault)' 'True' (Get-L04Value $rec 'allowSharedKeyAccess')
Add-Check 'Records: HTTPS only' 'True' (Get-L04Value $rec 'enableHttpsTrafficOnly')
Add-Check 'Records: minimum TLS' 'TLS1_2' (Get-L04Value $rec 'minimumTlsVersion')
Add-Check 'Records: blob public access' 'False' (Get-L04Value $rec 'allowBlobPublicAccess')
Add-Check 'Records: firewall default action' 'Deny' (Get-L04Value $rec 'networkRuleSet.defaultAction')
# Wrap the filtered result in @() so an empty rule list counts as 0 under StrictMode.
Add-Check 'Records: IP rules at baseline' '0' @(@(Get-L04Value $rec 'networkRuleSet.ipRules') | Where-Object { $_ }).Count
Add-Check 'Records: infrastructure encryption' 'True' (Get-L04Value $rec 'encryption.requireInfrastructureEncryption')

# --- Intake account ------------------------------------------------------------------------
$in = Invoke-L04Az @('storage', 'account', 'show', '--name', $lab.intakeAccount, '--resource-group', $rg)
Add-Check 'Intake: Shared Key allowed' 'False' (Get-L04Value $in 'allowSharedKeyAccess')
$dfs = Invoke-L04Arm -Path "$($lab.intakeId)/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2025-06-01"
$override = Get-L04Value $dfs 'properties.overrideSubscriptionLevelSettings'
Add-Check 'Intake: Defender override removed' 'False' $override
foreach ($entry in @(@{ Name = 'Records'; Id = $lab.recordsId }, @{ Name = 'Intake'; Id = $lab.intakeId })) {
    # Subscription pricing alone cannot prove this resource has protection enabled.
    $setting = Invoke-L04Arm -Path "$($entry.Id)/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2025-06-01"
    Add-Check "$($entry.Name): Defender enabled at account" 'True' (Get-L04Value $setting 'properties.isEnabled') -ParkedValues 'False', ''
    Add-Check "$($entry.Name): malware scan on upload" 'True' (Get-L04Value $setting 'properties.malwareScanning.onUpload.isEnabled') -ParkedValues 'False', ''
    Add-Check "$($entry.Name): sensitive data detection" 'True' (Get-L04Value $setting 'properties.sensitiveDataDiscovery.isEnabled') -ParkedValues 'False', ''
    Add-Check "$($entry.Name): account override" 'False' (Get-L04Value $setting 'properties.overrideSubscriptionLevelSettings')
}
$blobs = @(Invoke-L04Az -NoSubscription @('storage', 'blob', 'list', '--account-name', $lab.intakeAccount, '--container-name', $script:L04Config.intakeContainer, '--auth-mode', 'login', '--query', '[].name')) | Where-Object { $_ }
Add-Check 'Intake: test uploads removed' '0' @($blobs).Count

# --- SQL -----------------------------------------------------------------------------------
$srv = Invoke-L04Az @('sql', 'server', 'show', '--name', $lab.sqlServer, '--resource-group', $rg)
Add-Check 'SQL: minimum TLS' '1.2' (Get-L04Value $srv 'minimalTlsVersion')
Add-Check 'SQL: public network access' 'Enabled' (Get-L04Value $srv 'publicNetworkAccess')
$adOnly = Invoke-L04Az @('sql', 'server', 'ad-only-auth', 'get', '--name', $lab.sqlServer, '--resource-group', $rg)
Add-Check 'SQL: Microsoft Entra-only authentication' 'True' (Get-L04Value $adOnly 'azureAdOnlyAuthentication')
$tde = Invoke-L04Az @('sql', 'db', 'tde', 'show', '--server', $lab.sqlServer, '--database', $lab.sqlDatabase, '--resource-group', $rg)
Add-Check 'SQL: TDE state' 'Enabled' (Get-L04Value $tde 'state')
$audit = Invoke-L04Az @('sql', 'server', 'audit-policy', 'show', '--name', $lab.sqlServer, '--resource-group', $rg)
Add-Check 'SQL: server auditing' 'Enabled' (Get-L04Value $audit 'state')
Add-Check 'SQL: audit to Log Analytics' 'True' (Get-L04Value $audit 'isAzureMonitorTargetEnabled')
$va = $null
try { $va = Invoke-L04Arm -Path "$($lab.sqlServerId)/sqlVulnerabilityAssessments/default?api-version=2023-08-01" } catch { $va = $null }
Add-Check 'SQL: vulnerability assessment (express)' 'Enabled' $(if ($va) { Get-L04Value $va 'properties.state' } else { 'unreadable' }) -ParkedValues 'Disabled', 'unreadable'
$fw = @(Invoke-L04Az @('sql', 'server', 'firewall-rule', 'list', '--server', $lab.sqlServer, '--resource-group', $rg))
$rule = $fw | Where-Object { $_.name -eq 'kim-akers-workstation' } | Select-Object -First 1
$ip = Get-L04OperatorIp
# WARN, not FAIL: a changed home IP only matters for demo 4.3, and Deploy-L04Lab.ps1 -Deploy refreshes it.
Add-Check 'SQL: firewall rule matches this workstation' $ip $(if ($rule) { $rule.startIpAddress } else { 'missing' }) -Otherwise WARN
$rowsInDb = 'unreadable'
if ($rule -and $rule.startIpAddress -eq $ip) {
    $token = Get-L04SqlToken
    try {
        $q = Invoke-Sqlcmd -ServerInstance $lab.sqlFqdn -Database $lab.sqlDatabase -AccessToken $token -Encrypt Mandatory -ErrorAction Stop -Query 'SELECT COUNT(*) AS Rows FROM dbo.ServiceRecords;'
        $rowsInDb = [int]$q.Rows
    }
    finally { $token = $null }
}
Add-Check 'SQL: seed rows in ServiceRecords' '3' $rowsInDb

# --- Subscription plans (read only; this script never changes them) ------------------------
foreach ($plan in @('StorageAccounts', 'SqlServers', 'OpenSourceRelationalDatabases', 'CosmosDbs', 'SqlServerVirtualMachines')) {
    $p = Invoke-L04Arm -Path "/subscriptions/$($script:L04Config.subscriptionId)/providers/Microsoft.Security/pricings/$($plan)?api-version=2024-01-01"
    Add-Check "Defender plan: $plan" 'Standard' (Get-L04Value $p 'properties.pricingTier') -ParkedValues 'Free'
}

# Audit preserves the deliberate starting fault; the demonstration changes this one assignment to Deny.
$guard=Invoke-L04Arm -Path "$($lab.recordsId)/providers/Microsoft.Authorization/policyAssignments/sc500-l04-no-sharedkey?api-version=2022-06-01"
Add-Check 'Records: Shared Key policy baseline' 'Audit' (Get-L04Value $guard 'properties.parameters.effect.value')

$rows | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host
$fails = @($rows | Where-Object Result -eq 'FAIL').Count
$warns = @($rows | Where-Object Result -eq 'WARN').Count
$parkedRows = @($rows | Where-Object Result -eq 'PARKED').Count
[void](Write-L04Evidence 'readiness' @{ checks = $rows; fail = $fails; warn = $warns; parked = $parkedRows; parkedSwitch = [bool]$Parked })
if ($fails) { Write-Host "NOT READY: $fails check(s) failed. Run Reset-L04Lab.ps1, then run this again."; exit 1 }
if ($parkedRows) { Write-Host "PARKED BASELINE: every other check passed$(if ($warns) { " ($warns warning(s))" }), and $parkedRows Defender check(s) read their parked values. Not take-ready: open the Defender window, then run this without -Parked."; exit 0 }
Write-Host $(if ($warns) { "BASELINE WITH WARNINGS: $warns check(s) need attention before demo 4.3." } else { 'BASELINE PASS: configuration checks passed. Detection evidence and a timed take are separate gates.' })
