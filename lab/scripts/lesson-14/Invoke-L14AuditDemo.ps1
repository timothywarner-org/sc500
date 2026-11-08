<#
.SYNOPSIS
    Demo 14.4: stage one genuine Microsoft 365 action for Microsoft Purview Audit, check for it where
    a script is allowed to look, and assemble the case timeline.
.DESCRIPTION
    These modes support the Defender portal Audit demonstration. Existing delegated Exchange
    Online access can also search Audit without new app consent. Collection must be enabled first.
      Stage     Writes a small synthetic CSV named exactly like the file in the latest fixture's
                intended match, under lab/.azure/lesson-14/staging/, and prints your upload steps.
                Uploading it to OneDrive is your own action; audit search typically shows it after
                60 to 90 minutes, so stage at least 90 minutes before the demo.
      Office    Read-only. If you have connected the Microsoft 365 connector, looks for the upload in
                OfficeActivity (the Sentinel copy of the same audit record). INFO when the table
                has no rows; that isn't a failure, because the connector is your decision.
      Timeline  Read-only. The case in UTC order: fixture events, ingestion, the alert, the incident,
                the automation tags, the playbook's comment, and any comment you added from the
                audit record. Each row carries its evidence class.
.PARAMETER Mode One of the modes above.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14AuditDemo.ps1 -Mode Stage
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Stage', 'Office', 'Timeline')][string]$Mode)
. (Join-Path $PSScriptRoot 'L14.Common.ps1')
$cfg = $script:L14Config
[void](Assert-L14Context)
$l13 = Get-L14L13Lab
$fx = Get-L14LastFixture

switch ($Mode) {
    'Stage' {
        $dir = Join-Path $script:L14State 'staging'
        [void][IO.Directory]::CreateDirectory($dir)
        $file = Join-Path $dir $fx.fileName
        # Invented parts rows; nothing real, nothing personal.
        @(
            'PartNumber,Description,Supplier,UnitCost'
            'CTSO-P200,Pump assembly,Northwind Traders,1240.00'
            'CTSO-V110,Valve kit,Northwind Traders,310.50'
            'CTSO-S045,Seal set,Fabrikam Inc.,42.75'
        ) | Set-Content -LiteralPath $file -Encoding utf8
        Write-Host "Synthetic export file: $file"
        Write-Host ''
        Write-Host 'Upload under your authorized sign-in after auditing reads enabled:'
        Write-Host "  1. Open https://www.office.com as $($cfg.operatorUpn), then Apps and more > OneDrive."
        Write-Host "  2. Select Create or upload > Files upload and choose $($fx.fileName) from $dir."
        Write-Host '  3. Note UTC time. Audit delivery typically takes 60 to 90 minutes, without a guaranteed upper bound.'
        [void](Write-L14Evidence 'audit-stage' ([ordered]@{ stagedUtc = [DateTime]::UtcNow.ToString('o'); fileName = $fx.fileName; fixtureId = $fx.fixtureId }))
    }
    'Office' {
        # OfficeActivity only exists once the Microsoft 365 connector has sent something.
        $rows = @()
        try {
            $rows = @(Invoke-L14Query -Lab $l13 -Timespan 'P7D' -Kql @"
OfficeActivity
| where Operation == 'FileUploaded'
| where SourceFileName == '$($fx.fileName)'
| project TimeGenerated, UserId, Operation, OfficeWorkload, SourceFileName, Site_Url
"@)
        }
        catch { if ($_.Exception.Message -notmatch '(?i)(resolve|OfficeActivity)') { throw } }
        if ($rows) { $rows | Format-Table -AutoSize | Out-String -Width 200 | Out-Host }
        else { Write-Host "INFO: no FileUploaded row for $($fx.fileName) in OfficeActivity. Either the Microsoft 365 connector isn't connected (your decision) or the upload hasn't arrived yet. Purview Audit in the Defender portal is the source of record either way." }
        [void](Write-L14Evidence 'audit-office' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); fileName = $fx.fileName; rows = $rows }))
    }
    'Timeline' {
        $events = [Collections.Generic.List[object]]::new()
        $add = { param($t, $what, $class) if ($t) { $events.Add([pscustomobject][ordered]@{ Utc = ([DateTime]$t).ToUniversalTime(); Event = $what; Evidence = $class }) } }
        # P7D, not P2D: the KQL pins one FixtureId, so a wider window changes no rows; it keeps the retained
        # fixture on the timeline for a week instead of two days after the Send.
        $rows = @(Invoke-L14Query -Lab $l13 -Timespan 'P7D' -Kql "$($cfg.l13.customTable) | where FixtureId == '$($fx.fixtureId)' | project TimeGenerated, Ingested = ingestion_time(), Actor, CaseId, ClientIp, TargetResource")
        foreach ($r in $rows) {
            $case = if ($r.CaseId) { "case $($r.CaseId)" } else { 'no case' }
            & $add $r.TimeGenerated "ServiceHub: $($r.Actor) read $(($r.TargetResource -split '/')[-1]) from $($r.ClientIp), $case" 'synthetic fixture'
        }
        $firstIngest = @($rows | ForEach-Object { [DateTime]$_.Ingested } | Sort-Object) | Select-Object -First 1
        & $add $firstIngest 'Service-recorded ingestion time (queryability checked separately)' 'live observation'
        $incFile = Join-Path $script:L14State 'last-incident.json'
        if (Test-Path -LiteralPath $incFile) {
            $inc = Get-L14RecordingIncident
            # Same source as Invoke-L14DetectionDemo.ps1 -Mode Alert (the incidents API), so the
            # times on the timeline match the times the Alert readout and the slides quote.
            $alert = @(Get-L14IncidentAlerts -L13Lab $l13 -IncidentName $inc.incidentName | Sort-Object { $_.properties.timeGenerated }) | Select-Object -First 1
            if ($alert) { & $add $alert.properties.timeGenerated "Alert: $($alert.properties.alertDisplayName)" 'live observation' }
            $i = Invoke-L14Rest -Path "$($l13.workspaceId)/providers/Microsoft.SecurityInsights/incidents/$($inc.incidentName)?api-version=2025-09-01"
            & $add $i.properties.createdTimeUtc "Incident $($i.properties.incidentNumber) created ($($i.properties.status); tags $((@($i.properties.labels | ForEach-Object labelName)) -join ', '))" 'live observation'
            foreach ($c in @(Get-L14IncidentComments -L13Lab $l13 -IncidentName $inc.incidentName)) {
                $text = ($c.properties.message -replace '<[^>]+>', '').Trim()
                $who = $c.properties.author.name
                $class = if ($text -match 'response playbook') { 'playbook comment (run checked separately)' } elseif ($text -match '(?i)purview|audit') { 'analyst note mentioning Audit (not independently validated)'  } else { 'analyst note' }
                & $add $c.properties.createdTimeUtc "Comment ($who): $(if ($text.Length -gt 110) { $text.Substring(0, 110) + '...' } else { $text })" $class
            }
        }
        else { Write-Host 'No incident recorded yet; run Invoke-L14DetectionDemo.ps1 -Mode Alert first.' }
        $sorted = @($events | Sort-Object Utc)
        $sorted | ForEach-Object { '{0:HH:mm:ss}  {1,-34} {2}' -f $_.Utc, $_.Evidence, $_.Event } | Out-Host
        [void](Write-L14Evidence 'timeline' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); fixtureId = $fx.fixtureId; events = $sorted }))
    }
}
