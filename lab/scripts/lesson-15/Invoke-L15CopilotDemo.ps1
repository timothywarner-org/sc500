<#
.SYNOPSIS
    Lesson 15 demo readouts: the capacity and its clock, your access, the ServiceHub plugin's
    ground truth, and the case ledger that every Security Copilot answer is checked against.
.DESCRIPTION
    Every mode is read-only. None of them calls Security Copilot: Security Copilot's answers appear in
    its own portal, and these readouts are the records you compare them with.
      -Mode Capacity  Security Copilot capacities in the course subscription: group, region, units,
                      created time, expiry, a retail estimate of provisioned charges so far, and the
                      reaper's last run. Says so plainly when there's no paid capacity.
      -Mode Access    your Microsoft Entra roles (and which ones inherit Security Copilot owner) and his
                      Azure roles on log-secops-shared-eastus2-001, because Security Copilot reads data on his behalf.
      -Mode Plugin    Parses the ServiceHub KQL plugin and runs each skill's KQL with the sample input,
                      as you, against log-secops-shared-eastus2-001: the rows the plugin should return in Security Copilot.
      -Mode Case      The ledger for Lesson 14's pinned incident: status, entities, alerts and times,
                      tags, the playbook comment, and the fixture rows, each labeled with its source.
.PARAMETER Mode Capacity, Access, Plugin, or Case.
.PARAMETER ShowSettings With -Mode Plugin, also print the tenant and subscription IDs the plugin's settings need (for prep, before the demo).
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Invoke-L15CopilotDemo.ps1 -Mode Case
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Capacity', 'Access', 'Plugin', 'Case')][string]$Mode, [switch]$ShowSettings)
. (Join-Path $PSScriptRoot 'L15.Common.ps1')
$cfg = $script:L15Config
$account = Assert-L15Context
$utc = { param($t) if ($t) { ([DateTime]$t).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC' } else { 'not reported' } }

switch ($Mode) {
    'Capacity' {
        $caps = @(Get-L15Capacities)
        $lab = Get-L15Outputs
        Write-Host ''
        if (-not $caps) {
            Write-Host 'No paid Security Copilot capacity exists in this subscription, so nothing is billing by the hour.'
            Write-Host 'If Security Copilot is included with Microsoft 365 E5 or E7 for this tenant, that capacity is not an Azure resource and doesn''t appear here.'
        }
        foreach ($c in $caps) {
            $est = Get-L15ProvisionedEstimate $c
            $units = Get-L15Value $c 'properties.numberOfUnits'
            Write-Host ("Capacity        {0}" -f $c.name)
            Write-Host ("Resource group  {0}{1}" -f $c.resourceGroup, $(if ($c.guarded) { ' (guarded by the reaper)' } else { ' (NOT guarded: the reaper only watches ' + $cfg.resourceGroup + ')' }))
            Write-Host ("Region          {0}" -f $c.location)
            Write-Host ("Provisioned     {0}" -f $(if ($units) { "$units SCU" } else { 'not reported by ARM' }))
            foreach ($k in @('overageAmount', 'overageState', 'geo', 'crossGeoCompute')) {
                $v = Get-L15Value $c "properties.$k"
                if ($null -ne $v) { Write-Host ("{0,-15} {1}" -f $k, $v) }
            }
            Write-Host ("Created         {0}" -f (& $utc $c.createdUtc))
            $deadline = if ($c.expiresUtc) { [DateTime]$c.expiresUtc } elseif ($c.createdUtc) { ([DateTime]$c.createdUtc).AddHours([int]$cfg.reaper.defaultMaxHours) } else { $null }
            Write-Host ("Deleted by      {0}{1}" -f (& $utc $deadline), $(if ($c.expiresUtc) { ' (expiry tag)' } else { " (no tag: created + $($cfg.reaper.defaultMaxHours) hours)" }))
            if ($est) { Write-Host ("Provisioned so far  {0} SCU x {1} billed clock hours = about `${2} retail, before credits and tax. Overage isn't included." -f $est.units, $est.startedHours, $est.usd) }
            Write-Host ''
        }
        if ($lab) {
            $runs = Invoke-L15Rest -Path "$($lab.reaperId)/runs?api-version=2019-05-01&`$top=1"
            $last = @($runs.value) | Select-Object -First 1
            Write-Host ("Reaper          {0}, every {1} minutes, last run {2}: {3}" -f $lab.reaperName, $lab.recurrenceMinutes, (& $utc (Get-L15Value $last 'properties.startTime')), (Get-L15Value $last 'properties.status'))
        } else { Write-Host 'Reaper          not deployed. Run Deploy-L15Lab.ps1 -Deploy before creating a capacity.' }
        [void](Write-L15Evidence 'capacity' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); capacities = $caps; reaper = $lab }))
    }

    'Access' {
        # Directory roles through Microsoft Graph with your CLI session (read-only).
        $me = Invoke-L15Rest -Path 'https://graph.microsoft.com/v1.0/me?$select=id,userPrincipalName' -Resource 'https://graph.microsoft.com'
        $roles = @((Invoke-L15Rest -Path 'https://graph.microsoft.com/v1.0/me/transitiveMemberOf/microsoft.graph.directoryRole?$select=displayName' -Resource 'https://graph.microsoft.com').value |
            ForEach-Object displayName | Sort-Object)
        $inherit = @($roles | Where-Object { $cfg.copilot.ownerInheritingEntraRoles -contains $_ })
        $l13 = Get-L15L13Lab
        $assign = @(Invoke-L15Az @('role', 'assignment', 'list', '--assignee', $me.id, '--scope', $l13.workspaceId, '--include-inherited', '--query', '[].{role:roleDefinitionName, scope:scope}'))
        $read = @($assign | Where-Object { $cfg.copilot.sentinelReadRoles -contains $_.role })
        Write-Host ''
        Write-Host "Signed in as $($me.userPrincipalName)"
        Write-Host 'Microsoft Entra roles (active):'
        foreach ($r in $roles) { Write-Host ("  {0}{1}" -f $r, $(if ($inherit -contains $r) { '   -> inherits Security Copilot owner' } else { '' })) }
        Write-Host ''
        Write-Host "Azure roles that reach $($cfg.l13.workspace):"
        foreach ($a in $assign) {
            # Name the scope level instead of printing IDs, so nothing identifying lands.
            $where = if ($a.scope -ieq $l13.workspaceId) { 'the workspace' } elseif ($a.scope -match '/resourceGroups/[^/]+$') { 'its resource group' } elseif ($a.scope -match '^/subscriptions/[^/]+$') { 'the subscription' } elseif ($a.scope -eq '/') { 'the root scope (/)' } elseif ($a.scope -match '/managementGroups/') { 'a management group' } else { 'another scope' }
            Write-Host ("  {0,-34} on {1}" -f $a.role, $where)
        }
        Write-Host ''
        Write-Host ("Security Copilot reads Sentinel as this account. Sentinel read access: {0}" -f $(if ($read) { 'yes, through ' + (($read.role | Sort-Object -Unique) -join ', ') } else { 'NO. Copilot would return nothing for this workspace.' }))
        [void](Write-L15Evidence 'access' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); upn = $me.userPrincipalName
            entraRoles = $roles; inheritsCopilotOwner = $inherit; workspaceRoles = $assign; sentinelRead = [bool]$read }))
    }

    'Plugin' {
        $m = Get-L15PluginManifest
        $l13 = Get-L15L13Lab
        $skills = @($m.SkillGroups | ForEach-Object { $_.Skills })
        Write-Host ''
        Write-Host ("Plugin {0}: {1} (auth: {2})" -f $m.Descriptor.Name, $m.Descriptor.DisplayName, (@($m.Descriptor.SupportedAuthTypes) -join ', '))
        # The tenant and subscription IDs print only with -ShowSettings (prep), so they don't land.
        if ($ShowSettings) {
            Write-Host ("Settings for the upload: TenantId {0} · SubscriptionId {1} · ResourceGroupName {2} · WorkspaceName {3}" -f `
                $cfg.tenantId, $cfg.subscriptionId, $cfg.l13.resourceGroup, $cfg.l13.workspace)
        } else {
            Write-Host ("Settings for the upload: TenantId and SubscriptionId (run with -ShowSettings) · ResourceGroupName {0} · WorkspaceName {1}" -f $cfg.l13.resourceGroup, $cfg.l13.workspace)
        }
        $results = @()
        foreach ($s in $skills) {
            $kql = $s.Settings.Template
            foreach ($prop in $cfg.plugin.sampleInputs.PSObject.Properties) { $kql = $kql.Replace("{{$($prop.Name)}}", [string]$prop.Value) }
            if ($kql -match '\{\{') { throw "Skill $($s.Name) still has an unfilled input after substitution." }
            $rows = @(Invoke-L15Query -L13Lab $l13 -Kql $kql)
            Write-Host ''
            Write-Host ("Skill {0}  ({1} rows)" -f $s.Name, $rows.Count)
            $rows | Select-Object -First 10 | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
            $results += [ordered]@{ skill = $s.Name; target = $s.Settings.Target; rows = $rows.Count; sample = @($rows | Select-Object -First 10) }
        }
        [void](Write-L15Evidence 'plugin' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); plugin = $m.Descriptor.Name; results = $results }))
    }

    'Case' {
        $case = Get-L15Case
        $l13 = Get-L15L13Lab
        $inc = Get-L15Incident -L13Lab $l13 -IncidentName $case.incidentName
        if (-not $inc) { throw "Incident $($case.incidentNumber) isn't in $($cfg.l13.workspace). Stop and check Lesson 14's handoff." }
        $p = $inc.properties
        $alerts = @(Get-L15IncidentPart -L13Lab $l13 -IncidentName $inc.name -Part alerts | Sort-Object { $_.properties.timeGenerated })
        $entities = @(Get-L15IncidentPart -L13Lab $l13 -IncidentName $inc.name -Part entities)
        $comments = @(Get-L15IncidentPart -L13Lab $l13 -IncidentName $inc.name -Part comments | Sort-Object { $_.properties.createdTimeUtc })
        $fixture = @(Invoke-L15Query -L13Lab $l13 -Timespan 'P30D' -Kql (@'
ServiceHubAudit_CL
| where FixtureId == '{0}'
| extend FileName = extract(@"([^/]+)$", 1, TargetResource)
| project TimeGenerated, Actor, ClientIp, CaseId, FileName, EvidenceClass
| order by TimeGenerated asc
'@ -f $case.fixtureId))
        $cut = { param([string]$t, [int]$n) if ($t.Length -le $n) { $t } else { $t.Substring(0, $n - 3) + '...' } }
        $row = { param($time, [string]$record, [string]$source) Write-Host ("{0}   {1,-60}  {2}" -f ([DateTime]$time).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'), (& $cut $record 60), $source) }
        $name = { param($e) $k = $e.kind; switch ($k) { 'Account' { $e.properties.accountName } 'Ip' { $e.properties.address } 'File' { $e.properties.fileName } default { $e.properties.friendlyName } } }
        Write-Host ''
        Write-Host ("Case            Incident {0} · Defender incident {1} · {2} ({3})" -f $p.incidentNumber, (Get-L15Value $p 'providerIncidentId'), $p.status, $case.source)
        Write-Host ("Title           {0}" -f $p.title)
        Write-Host ("Severity        {0} · Created {1} · Tags {2}" -f $p.severity, (& $utc $p.createdTimeUtc), ((@($p.labels) | ForEach-Object labelName) -join ', '))
        Write-Host ("Entities        {0}" -f ((@($entities | ForEach-Object { '{0}: {1}' -f $_.kind, (& $name $_) })) -join ' · '))
        Write-Host ''
        Write-Host ("{0,-22}{1,-62}{2}" -f 'UTC', 'Record', 'Source')
        foreach ($r in $fixture) { & $row $r.TimeGenerated ("{0} exported from {1}, case {2}" -f $r.Actor, $r.ClientIp, $(if ($r.CaseId) { $r.CaseId } else { 'none' })) "ServiceHubAudit_CL, $($r.EvidenceClass)" }
        foreach ($a in $alerts) { & $row $a.properties.timeGenerated ('Alert: ' + $a.properties.alertDisplayName) 'Sentinel alert' }
        & $row $p.createdTimeUtc "Incident $($p.incidentNumber) created" 'Sentinel incident'
        foreach ($c in $comments) {
            $text = ($c.properties.message -replace '<[^>]+>', '' -replace '\s+', ' ').Trim()
            $who = Get-L15Value $c 'properties.author.name'
            & $row $c.properties.createdTimeUtc ('Comment: ' + $text) $(if ($who) { $who } else { 'Comment' })
        }
        Write-Host ''
        Write-Host 'Check every Security Copilot claim against a line above. A claim with no line behind it is a lead, not a finding.'
        $ledger = [ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); case = $case; incidentNumber = $p.incidentNumber
            defenderIncident = (Get-L15Value $p 'providerIncidentId'); status = $p.status; title = $p.title; severity = $p.severity
            createdUtc = $p.createdTimeUtc; tags = @($p.labels | ForEach-Object labelName)
            entities = @($entities | ForEach-Object { [ordered]@{ kind = $_.kind; name = (& $name $_) } })
            alerts = @($alerts | ForEach-Object { [ordered]@{ name = $_.properties.alertDisplayName; timeUtc = $_.properties.timeGenerated } })
            comments = @($comments | ForEach-Object { [ordered]@{ timeUtc = $_.properties.createdTimeUtc; author = (Get-L15Value $_ 'properties.author.name'); message = (($_.properties.message -replace '<[^>]+>', '').Trim()) } })
            fixtureRows = $fixture }
        [void][IO.Directory]::CreateDirectory($script:L15State)
        $ledger | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $script:L15State 'case-ledger.json') -Encoding utf8
        [void](Write-L15Evidence 'case' $ledger)
    }
}
