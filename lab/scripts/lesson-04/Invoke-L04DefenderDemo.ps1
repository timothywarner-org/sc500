<#
.SYNOPSIS
    Demos 4.2 and 4.4 helper: Defender for Storage and Defender for Databases coverage,
    configuration, and evidence for the Lesson 4 resources.

.DESCRIPTION
    Modes:
      Plans            Subscription plans that cover this lesson: Storage, Azure SQL, SQL on
                       machines, open-source relational databases, and Cosmos DB (read-only).
      StorageSettings  What each storage account actually runs: inherited or overridden,
                       malware scanning and its monthly cap, sensitive data detection.
      OverrideIntake   Give the intake account its own settings: malware scanning on upload
                       with a 10 GB monthly cap. This is the per-account override.
      ScanResults      The intake blobs and their malware-scan result tags, plus Defender
                       alerts raised on the lesson resources in the last 24 hours.
      SqlCoverage      Defender for Azure SQL on the lesson server: threat protection state,
                       vulnerability assessment (express configuration), and recent alerts.
      VaResults        The latest vulnerability assessment scan on servicehub-records: its
                       state and rule counts, then each failing rule with its remediation.
                       Read-only. Scans live at database scope for express configuration.

.PARAMETER Mode
    One of the modes above.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Invoke-L04DefenderDemo.ps1 -Mode Plans

.NOTES
    Only OverrideIntake writes anything, and only to the lesson's intake account. No
    subscription-wide plan is changed; Reset-L04Lab.ps1 removes the override.
    Get-L04Value reads optional ARM properties safely; ARM simply omits unset ones.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Plans', 'StorageSettings', 'OverrideIntake', 'UploadClean', 'ScanResults', 'SqlCoverage', 'VaResults')]
    [string]$Mode
)
. (Join-Path $PSScriptRoot 'L04.Common.ps1')
[void](Assert-L04Context)
$lab = Get-L04Outputs
$sub = $script:L04Config.subscriptionId
# Use the documented stable contract, checked against Microsoft Learn on 2026-09-26.
$dfsApi = 'api-version=2025-06-01'

function Get-DfsSetting([string]$AccountId) {
    return Invoke-L04Arm -Path "$AccountId/providers/Microsoft.Security/defenderForStorageSettings/current?$dfsApi"
}

function ConvertTo-DfsRow([string]$Name, $Setting) {
    [pscustomobject]@{
        Account               = $Name
        Enabled               = Get-L04Value $Setting 'properties.isEnabled'
        OverridesSubscription = Get-L04Value $Setting 'properties.overrideSubscriptionLevelSettings'
        MalwareOnUpload       = Get-L04Value $Setting 'properties.malwareScanning.onUpload.isEnabled'
        CapGbPerMonth         = Get-L04Value $Setting 'properties.malwareScanning.onUpload.capGBPerMonth'
        SensitiveData         = Get-L04Value $Setting 'properties.sensitiveDataDiscovery.isEnabled'
    }
}

function Get-RecentAlerts {
    # Alerts on this lesson's resources in the last day, plus sample alerts (which Defender
    # raises against simulated resources). The Alert name keeps the SAMPLE label intact.
    $next = "/subscriptions/$sub/providers/Microsoft.Security/alerts?api-version=2022-01-01"
    $items = [System.Collections.Generic.List[object]]::new()
    do {
        $page = Invoke-L04Arm -Path $next -AsHashtable
        foreach ($item in @(Get-L04Value $page 'value')) { if ($item) { $items.Add($item) } }
        $next = Get-L04Value $page 'nextLink'
    } while ($next)
    $since = [DateTime]::UtcNow.AddHours(-24)
    $rgPattern = [regex]::Escape($script:L04Config.resourceGroup)
    foreach ($a in $items) {
        $time = Get-L04Value $a 'properties.timeGeneratedUtc'
        if (-not $time -or [DateTime]$time -lt $since) { continue }
        $name = [string](Get-L04Value $a 'properties.alertDisplayName')
        $ids = @(@(Get-L04Value $a 'properties.resourceIdentifiers') | ForEach-Object { Get-L04Value $_ 'azureResourceId' })
        $ours = [bool]($ids -match $rgPattern)
        if (-not $ours -and $name -notmatch 'sample') { continue }
        [pscustomobject]@{
            TimeUtc  = ([DateTime]$time).ToUniversalTime().ToString('o')
            Severity = Get-L04Value $a 'properties.severity'
            Alert    = $name
            Entity   = Get-L04Value $a 'properties.compromisedEntity'
            Source   = $(if ($name -match 'sample') { 'sample (simulated resource)' } else { 'lesson resource' })
            AlertType = Get-L04Value $a 'properties.alertType'
            Id = Get-L04Value $a 'id'
            ResourceIds = $ids
        }
    }
}

switch ($Mode) {
    'Plans' {
        $rows = foreach ($plan in 'StorageAccounts', 'SqlServers', 'SqlServerVirtualMachines', 'OpenSourceRelationalDatabases', 'CosmosDbs') {
            $p = Invoke-L04Arm -Path "/subscriptions/$sub/providers/Microsoft.Security/pricings/$plan`?api-version=2024-01-01"
            $ext = foreach ($e in @(Get-L04Value $p 'properties.extensions')) {
                if (-not $e -or [string](Get-L04Value $e 'isEnabled') -ne 'True') { continue }
                $more = Get-L04Value $e 'additionalExtensionProperties'
                $detail = if ($more) { ' (' + (($more.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', ') + ')' } else { '' }
                (Get-L04Value $e 'name') + $detail
            }
            [pscustomobject]@{ Plan = $plan; Tier = (Get-L04Value $p 'properties.pricingTier'); SubPlan = (Get-L04Value $p 'properties.subPlan'); Extensions = (@($ext) -join '; ') }
        }
        $rows | Format-Table -AutoSize -Wrap | Out-String -Width 180 | Write-Host
        [void](Write-L04Evidence 'defender-plans' @($rows))
    }
    'StorageSettings' {
        $rows = @(
            (ConvertTo-DfsRow 'records' (Get-DfsSetting $lab.recordsId)),
            (ConvertTo-DfsRow 'intake' (Get-DfsSetting $lab.intakeId))
        )
        $rows | Format-Table -AutoSize | Out-String -Width 180 | Write-Host
        [void](Write-L04Evidence 'defender-storage-settings' $rows)
    }
    'OverrideIntake' {
        # The override flag is what makes these account settings win over the subscription
        # plan. Without it, the subscription's settings apply and this body is ignored.
        $body = @{ properties = @{
            isEnabled = $true
            overrideSubscriptionLevelSettings = $true
            malwareScanning = @{ onUpload = @{ isEnabled = $true; capGBPerMonth = 10 } }
            sensitiveDataDiscovery = @{ isEnabled = $true }
        } }
        [void](Invoke-L04Arm -Path "$($lab.intakeId)/providers/Microsoft.Security/defenderForStorageSettings/current?$dfsApi" -Method PUT -Body $body)
        Start-Sleep -Seconds 5
        $row = ConvertTo-DfsRow 'intake' (Get-DfsSetting $lab.intakeId)
        $row | Format-List | Out-String | Write-Host
        [void](Write-L04Evidence 'defender-override-intake' $row)
        if (-not $row.Enabled -or -not $row.OverridesSubscription -or -not $row.MalwareOnUpload -or $row.CapGbPerMonth -ne 10) { throw 'Intake override did not converge to the intended 10 GB scan configuration.' }
    }
    'UploadClean' {
        # A harmless synthetic file, uploaded with Entra authorization (intake allows no keys).
        # It gives the scan a clean result to compare with the test file's Malicious result.
        $file = Join-Path $script:L04Lab 'infra/lesson-04/seed/CTSO-UPLOAD-7731-site-photo-notes.txt'
        [void](Invoke-L04Az -NoSubscription @('storage', 'blob', 'upload', '--account-name', $lab.intakeAccount, '--container-name', $script:L04Config.intakeContainer, '--name', (Split-Path $file -Leaf), '--file', $file, '--overwrite', 'true', '--auth-mode', 'login'))
        Write-Host "Uploaded $(Split-Path $file -Leaf) to $($lab.intakeAccount)/$($script:L04Config.intakeContainer). Scan results usually appear within a minute or two."
        [void](Write-L04Evidence 'defender-upload-clean' @{ blob = (Split-Path $file -Leaf); account = $lab.intakeAccount })
    }
    'ScanResults' {
        $blobs = @(Invoke-L04Az -NoSubscription @('storage', 'blob', 'list', '--account-name', $lab.intakeAccount, '--container-name', $script:L04Config.intakeContainer, '--auth-mode', 'login', '--query', '[].name'))
        $rows = foreach ($b in $blobs) {
            if (-not $b) { continue }
            $tags = Invoke-L04Az -NoSubscription @('storage', 'blob', 'tag', 'list', '--account-name', $lab.intakeAccount, '--container-name', $script:L04Config.intakeContainer, '--name', $b, '--auth-mode', 'login')
            [pscustomobject]@{
                Blob       = $b
                ScanResult = Get-L04Value $tags 'Malware Scanning scan result'
                ScanTime   = Get-L04Value $tags 'Malware Scanning scan time UTC'
            }
        }
        if ($rows) { $rows | Format-Table -AutoSize | Out-String -Width 160 | Write-Host } else { Write-Host 'No blobs in intake-uploads yet.' }
        $alerts = @(Get-RecentAlerts)
        if ($alerts.Count) { $alerts | Format-Table -AutoSize -Wrap | Out-String -Width 180 | Write-Host } else { Write-Host 'No Defender alerts on the lesson resources in the last 24 hours.' }
        [void](Write-L04Evidence 'defender-scan-results' @{ blobs = @($rows); alerts = $alerts })
    }
    'SqlCoverage' {
        $atp = Invoke-L04Az @('sql', 'server', 'advanced-threat-protection-setting', 'show', '--name', $lab.sqlServer, '--resource-group', $script:L04Config.resourceGroup)
        $va = $null
        $va = Invoke-L04Arm -Path "$($lab.sqlServerId)/sqlVulnerabilityAssessments/default?api-version=2023-08-01"
        $row = [pscustomobject]@{
            Server                  = $lab.sqlServer
            ThreatProtection        = Get-L04Value $atp 'state'
            VulnerabilityAssessment = $(if ($va) { Get-L04Value $va 'properties.state' } else { 'not readable yet' })
            VaConfiguration         = $(if ($va) { 'Express (no storage account)' } else { '-' })
        }
        $row | Format-List | Out-String | Write-Host
        $alerts = @(Get-RecentAlerts | Where-Object { $_.AlertType -match 'SQL\.' -or $_.Alert -match 'SQL' })
        if ($alerts.Count) { $alerts | Format-Table -AutoSize -Wrap | Out-String -Width 180 | Write-Host } else { Write-Host 'No SQL alerts in the last 24 hours.' }
        [void](Write-L04Evidence 'defender-sql-coverage' @{ coverage = $row; alerts = $alerts })
    }
    'VaResults' {
        # Express configuration keeps scans per database. A server-scope scan list returns 405,
        # which is why this reads the database path.
        $base = "$($lab.sqlServerId)/databases/$($lab.sqlDatabase)/sqlVulnerabilityAssessments/default/scans"
        $scans = @(Get-L04Value (Invoke-L04Arm -Path "$base`?api-version=2023-08-01") 'value') | Where-Object { $_ }
        if (-not $scans.Count) { Write-Host 'No vulnerability assessment scan has finished yet. The first scan can take a while after enablement.'; return }
        $latest = $scans | Sort-Object { Get-L04Value $_ 'properties.endTime' } -Descending | Select-Object -First 1
        $summary = [pscustomobject]@{
            Database    = $lab.sqlDatabase
            Finished    = Get-L04Value $latest 'properties.endTime'
            Trigger     = Get-L04Value $latest 'properties.triggerType'
            State       = Get-L04Value $latest 'properties.state'
            FailedRules = Get-L04Value $latest 'properties.totalFailedRulesCount'
            PassedRules = Get-L04Value $latest 'properties.totalPassedRulesCount'
        }
        $summary | Format-List | Out-String | Write-Host
        $results = @(Get-L04Value (Invoke-L04Arm -Path "$base/$($latest.name)/scanResults?api-version=2023-08-01") 'value')
        $findings = @($results | Where-Object { $_ -and (Get-L04Value $_ 'properties.status') -eq 'Finding' } | ForEach-Object {
            [pscustomobject]@{
                Rule        = Get-L04Value $_ 'properties.ruleId'
                Severity    = Get-L04Value $_ 'properties.ruleMetadata.severity'
                Title       = Get-L04Value $_ 'properties.ruleMetadata.title'
                Remediation = Get-L04Value $_ 'properties.remediation.description'
            }
        })
        if ($findings.Count) { $findings | Format-List | Out-String -Width 160 | Write-Host } else { Write-Host 'No failing rules in the latest scan.' }
        [void](Write-L04Evidence 'defender-va-results' @{ scan = $summary; findings = $findings })
    }
}
