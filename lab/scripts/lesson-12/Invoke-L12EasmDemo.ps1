<#
.SYNOPSIS
    SC-500 demo 12.4: read what Defender EASM discovered from ServiceHub's seed (your own domain),
    what needs an ownership decision, and what it flags as a priority. Read-only.
.DESCRIPTION
    Modes (each saves a dated evidence file under lab/.azure/lesson-12/evidence/):
      Discovery   The discovery group's seed, schedule, and latest run (state, times, counts).
      Inventory   Asset counts by state and kind, the approved domains and hosts by name, and the
                  candidates that still need an ownership decision.
      Priorities  The attack surface priorities dashboard: high, medium, and low severity
                  observations with the count of affected assets.
      Billable    Billable asset counts per day, which is what EASM charges for after the trial.
      All         Every mode.
    Privacy: IP addresses, IP blocks, ASNs, and Whois or email contacts are counted, never
    listed. Nothing here reads Whois records. Ownership decisions (approve, dependency, dismiss) are
    yours to make in the portal; this script never changes an asset's state.
.PARAMETER Mode One of the modes above.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12EasmDemo.ps1 -Mode Discovery
#>
[CmdletBinding()]
param([ValidateSet('Discovery', 'Inventory', 'Priorities', 'Billable', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L12.Common.ps1')
$cfg = $script:L12Config
[void](Assert-L12Context)
$lab = Get-L12Outputs
$group = $cfg.names.discoveryGroup
# The API's state names differ from the portal's labels.
$stateLabels = [ordered]@{ confirmed = 'Approved'; candidate = 'Candidate'; candidateInvestigate = 'Requires investigation'; associatedThirdparty = 'Dependency'; associatedPartner = 'Monitor only' }
$listable = @('domain', 'host', 'page', 'sslCert')

function Assert-Ok($r, [string]$What) { if ($r.Status -ge 300) { throw "$What returned HTTP $($r.Status): $($r.Text)" } }

if ($Mode -in 'Discovery', 'All') {
    Write-Host "== Discovery group $group"
    $g = Invoke-L12Easm -Path "discoGroups/$group"
    Assert-Ok $g 'Reading the discovery group'
    $run = Get-L12Value $g.Body 'latestRun'
    Write-Host ("  Seeds: {0}" -f ((@(Get-L12Value $g.Body 'seeds') | ForEach-Object { "$($_.kind) $($_.name)" }) -join ', '))
    Write-Host ("  Recurrence: every {0} days" -f ([long](Get-L12Value $g.Body 'frequencyMilliseconds') / 86400000))
    function Show($v) { if ($null -eq $v -or "$v" -eq '') { 'not reported' } else { $v } }
    Write-Host ("  Latest run: {0}; submitted {1}; completed {2}" -f (Show (Get-L12Value $run 'state')), (Show (Get-L12Value $run 'submittedDate')), (Show (Get-L12Value $run 'completedDate')))
    Write-Host '  The run record can report zero counts even when assets arrive; -Mode Inventory reads the inventory itself.'
    $ws = Invoke-L12Rest -Path "$($lab.easmWorkspaceId)?api-version=2023-04-01-preview"
    $created = [DateTime](Get-L12Value $ws 'systemData.createdAt')
    # Learn: a customer's first EASM resource gets a 30-day trial, and after it only Approved assets bill.
    # This tenant's first workspace was the September 28 build, so this script doesn't claim a trial date.
    Write-Host ("  Workspace created {0:yyyy-MM-dd HH:mm} UTC. Only Approved assets bill; -Mode Billable reads the count." -f $created.ToUniversalTime())
    [void](Write-L12Evidence 'easm-discovery' ([ordered]@{ group = $group; seeds = (Get-L12Value $g.Body 'seeds'); latestRun = $run; workspaceCreatedUtc = $created.ToUniversalTime().ToString('o') }))
}

if ($Mode -in 'Inventory', 'All') {
    Write-Host '== Inventory by state and kind'
    $filters = @($stateLabels.Keys | ForEach-Object { "state = `"$_`"" })
    $s = Invoke-L12Easm -Method POST -Path 'reports/assets:getSummary' -Body @{ filters = $filters; groupBy = 'kind' }
    Assert-Ok $s 'The inventory summary'
    $summary = @(foreach ($a in @($s.Body.assetSummaries)) {
        $state = ($a.filter -replace '.*state\s*=\s*"?([A-Za-z]+)"?.*', '$1')
        [ordered]@{ state = $(if ($stateLabels.Contains($state)) { $stateLabels[$state] } else { $state }); total = $a.count
                    byKind = @(@($a.children) | Where-Object { $_ } | ForEach-Object { [ordered]@{ kind = $_.displayName; count = $_.count } }) }
    })
    foreach ($row in $summary) {
        Write-Host ("  {0,-24} {1,5}   {2}" -f $row.state, $row.total, (($row.byKind | ForEach-Object { "$($_.kind) $($_.count)" }) -join ', '))
    }
    function Get-Named([string]$State) {
        $kinds = ($listable | ForEach-Object { "`"$_`"" }) -join ', '
        $q = [uri]::EscapeDataString("state = `"$State`" AND kind in ($kinds)")
        $r = Invoke-L12Easm -Path 'assets' -Query "&filter=$q&maxpagesize=50&orderby=kind"
        Assert-Ok $r "Listing $State assets"
        @(@($r.Body.value) | ForEach-Object { [ordered]@{ kind = $_.kind; name = $_.name; firstSeen = (Get-L12Value $_ 'firstSeen'); lastSeen = (Get-L12Value $_ 'lastSeen') } })
    }
    $approved = Get-Named 'confirmed'
    $candidates = Get-Named 'candidate'
    Write-Host '  Approved (domains, hosts, pages, certificates):'
    $approved | Select-Object -First 25 | ForEach-Object { Write-Host ("    {0,-8} {1}" -f $_.kind, $_.name) }
    Write-Host ("  Candidates that need an ownership decision: {0}" -f @($candidates).Count)
    $candidates | Select-Object -First 15 | ForEach-Object { Write-Host ("    {0,-8} {1}" -f $_.kind, $_.name) }
    [void](Write-L12Evidence 'easm-inventory' ([ordered]@{ observedUtc = [DateTime]::UtcNow.ToString('o'); summary = $summary; approvedNamed = $approved; candidatesNamed = $candidates }))
}

if ($Mode -in 'Priorities', 'All') {
    Write-Host '== Attack surface priorities'
    $cats = @('priority_high_severity', 'priority_medium_severity', 'priority_low_severity')
    $p = Invoke-L12Easm -Method POST -Path 'reports/assets:getSummary' -Body @{ metricCategories = $cats }
    Assert-Ok $p 'The priorities summary'
    $rows = @(foreach ($cat in @($p.Body.assetSummaries)) {
        $items = @(@($cat.children) | Where-Object { $_ -and $_.count -gt 0 } | ForEach-Object { [ordered]@{ observation = $_.displayName; metric = $_.metric; assets = $_.count } })
        [ordered]@{ category = $cat.displayName; assets = $cat.count; updatedUtc = $cat.updatedAt; observations = $items }
    })
    foreach ($r in $rows) {
        Write-Host ("  {0}: {1} asset(s), updated {2}" -f $r.category, $r.assets, $r.updatedUtc)
        $r.observations | ForEach-Object { Write-Host ("    {0} ({1})" -f $_.observation, $_.assets) }
    }
    [void](Write-L12Evidence 'easm-priorities' ([ordered]@{ observedUtc = [DateTime]::UtcNow.ToString('o'); categories = $rows }))
}

if ($Mode -in 'Billable', 'All') {
    Write-Host '== Billable assets'
    $b = Invoke-L12Easm -Method POST -Path 'reports/assets:getBillable'
    Assert-Ok $b 'The billable summary'
    $days = @(@($b.Body.assetSummaries) | Where-Object { $_ } | Sort-Object date)
    $last = $days | Select-Object -Last 1
    if ($last) { Write-Host ("  {0}: {1} billable ({2})" -f $last.date, $last.total, ((@($last.assetBreakdown) | ForEach-Object { "$($_.kind) $($_.count)" }) -join ', ')) }
    else { Write-Host '  No billable days recorded yet.' }
    [void](Write-L12Evidence 'easm-billable' ([ordered]@{ days = $days }))
}
