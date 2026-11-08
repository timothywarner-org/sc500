<#
.SYNOPSIS
    Demo 14.2: the automation rule, the playbook, the identities that let them run, and the proof
    that the playbook actually ran on the incident.
.DESCRIPTION
    Modes (each saves a dated evidence file under lab/.azure/lesson-14/evidence/):
      Automation  Read-only. The automation rule read back: trigger, condition, and ordered actions.
      Playbook    Read-only. The playbook's trigger, action, state, and managed identity, plus the
                  two role assignments that make the chain work: Microsoft Sentinel's service
                  principal on the playbook's resource group, and the playbook's identity on the
                  workspace.
      Trace       Read-only. For the incident found by Invoke-L14DetectionDemo.ps1 -Mode Alert:
                  its tags, its comments, and the playbook run whose ID the comment carries.
                  A saved rule or a deployed playbook is configuration; this is the execution.
.PARAMETER Mode One of the modes above.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14ResponseDemo.ps1 -Mode Trace
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Automation', 'Playbook', 'Trace')][string]$Mode)
. (Join-Path $PSScriptRoot 'L14.Common.ps1')
$cfg = $script:L14Config
[void](Assert-L14Context)
$l13 = Get-L14L13Lab
$lab = Get-L14Outputs
$ws = $l13.workspaceId

switch ($Mode) {
    'Automation' {
        $a = Invoke-L14Rest -Path "$ws/providers/Microsoft.SecurityInsights/automationRules/$($cfg.names.automationRuleId)?api-version=2025-09-01"
        $t = $a.properties.triggeringLogic
        $cond = @($t.conditions | ForEach-Object {
            $v = @($_.conditionProperties.propertyValues | ForEach-Object { if ($_ -match '/alertRules/([^/]+)$') { "rule $($Matches[1])" } else { $_ } })
            "$($_.conditionProperties.propertyName) $($_.conditionProperties.operator) $($v -join ', ')" })
        $acts = @($a.properties.actions | Sort-Object order | ForEach-Object {
            if ($_.actionType -eq 'ModifyProperties') { "$($_.order). add tags: $((@($_.actionConfiguration.labels | ForEach-Object labelName)) -join ', ')" }
            elseif ($_.actionType -eq 'RunPlaybook') { "$($_.order). run playbook $(($_.actionConfiguration.logicAppResourceId -split '/')[-1])" }
            else { "$($_.order). $($_.actionType)" } })
        $out = [ordered]@{
            name = $a.properties.displayName; order = $a.properties.order; enabled = $t.isEnabled
            trigger = "$($t.triggersOn) $($t.triggersWhen)"; conditions = ($cond -join '; '); actions = ($acts -join ' | ')
            expires = $(if (Get-L14Value $t 'expirationTimeUtc') { $t.expirationTimeUtc } else { 'never' })
        }
        [pscustomobject]$out | Format-List | Out-Host
        [void](Write-L14Evidence 'automation' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); rule = $out }))
    }
    'Playbook' {
        $w = Invoke-L14Rest -Path "$($lab.playbookId)?api-version=2019-05-01"
        $def = $w.properties.definition
        $trigger = @($def.triggers.PSObject.Properties)[0]
        $actions = @($def.actions.PSObject.Properties | ForEach-Object { "$($_.Name) ($($_.Value.inputs.method) $($_.Value.inputs.path))" })
        $conn = $w.properties.parameters.'$connections'.value.azuresentinel
        $asi = Invoke-L14Az -NoSubscription -Raw @('ad', 'sp', 'show', '--id', $cfg.roles.azureSecurityInsightsAppId, '--query', 'id', '--output', 'tsv')
        $rgScope = "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$($cfg.resourceGroup)"
        $grants = @(
            @{ who = 'Microsoft Sentinel (Azure Security Insights)'; principal = $asi; scope = $rgScope; role = $cfg.roles.sentinelAutomationContributor }
            @{ who = "playbook identity ($($w.name))"; principal = $w.identity.principalId; scope = $ws; role = $cfg.roles.sentinelResponder }
        )
        $roles = foreach ($g in $grants) {
            $found = @(Invoke-L14Az @('role', 'assignment', 'list', '--assignee', $g.principal, '--scope', $g.scope, '--query', "[?ends_with(roleDefinitionId, '$($g.role)')].{role:roleDefinitionName, scope:scope}"))
            [pscustomobject][ordered]@{ Who = $g.who; Role = $(if ($found) { $found[0].role } else { 'MISSING' }); Scope = ($g.scope -split '/')[-1] }
        }
        $out = [ordered]@{
            name = $w.name; state = $w.properties.state; identity = "$($w.identity.type) $($w.identity.principalId)"
            trigger = "$($trigger.Name) ($($trigger.Value.type) $($trigger.Value.inputs.path))"
            actions = ($actions -join '; '); connection = "$($conn.connectionName) as $($conn.connectionProperties.authentication.type)"
        }
        [pscustomobject]$out | Format-List | Out-Host
        $roles | Format-Table -AutoSize | Out-Host
        [void](Write-L14Evidence 'playbook' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); playbook = $out; roles = $roles }))
    }
    'Trace' {
        $f = Join-Path $script:L14State 'last-incident.json'
        if (-not (Test-Path -LiteralPath $f)) { throw 'No incident yet. Run Invoke-L14DetectionDemo.ps1 -Mode Alert first.' }
        $inc = Get-L14RecordingIncident
        $i = Invoke-L14Rest -Path "$ws/providers/Microsoft.SecurityInsights/incidents/$($inc.incidentName)?api-version=2025-09-01"
        $tags = @($i.properties.labels | ForEach-Object labelName)
        $comments = @(Get-L14IncidentComments -L13Lab $l13 -IncidentName $inc.incidentName | Sort-Object { $_.properties.createdTimeUtc })
        $rows = foreach ($c in $comments) {
            $text = ($c.properties.message -replace '<[^>]+>', '').Trim()
            $runName = if ($text -match 'Run (\S+) received') { $Matches[1] } else { $null }
            $run = if ($runName -and $runName -match '^[A-Za-z0-9]+$') { Invoke-L14Rest -AllowNotFound -Path "$($lab.playbookId)/runs/$runName`?api-version=2019-05-01" }
            [pscustomobject][ordered]@{
                CommentUtc = ([DateTime]$c.properties.createdTimeUtc).ToUniversalTime().ToString('HH:mm:ss')
                Author = "$($c.properties.author.name)$(if ($c.properties.author.userPrincipalName) { " ($($c.properties.author.userPrincipalName))" })"
                Run = $runName; RunStatus = $(if ($run) { $run.properties.status }); RunStartUtc = $(if ($run) { ([DateTime]$run.properties.startTime).ToUniversalTime().ToString('HH:mm:ss') })
                Text = $(if ($text.Length -gt 90) { $text.Substring(0, 90) + '...' } else { $text })
            }
        }
        $created = ([DateTime]$i.properties.createdTimeUtc).ToUniversalTime()
        Write-Host "Incident $($i.properties.incidentNumber): $($i.properties.title)"
        Write-Host "  created $($created.ToString('HH:mm:ss')) UTC, status $($i.properties.status), tags: $(if ($tags) { $tags -join ', ' } else { '(none yet)' })"
        foreach ($r in $rows) {
            $run = if ($r.Run) { "run $($r.Run), $($r.RunStatus), started $($r.RunStartUtc) UTC" } else { 'no playbook run named' }
            Write-Host ("  {0} UTC  {1}`n      {2}`n      {3}" -f $r.CommentUtc, $r.Author, $run, $r.Text)
        }
        $playbookRow = @($rows | Where-Object { $_.Run }) | Select-Object -First 1
        if (-not $playbookRow) { Write-Host 'No playbook comment yet. Automation can take a few minutes (up to ten once the workspace is in the Defender portal); run -Mode Trace again.' }
        [void](Write-L14Evidence 'response-trace' ([ordered]@{
            readUtc = [DateTime]::UtcNow.ToString('o'); incidentNumber = $i.properties.incidentNumber; incidentName = $inc.incidentName
            createdUtc = $created.ToString('o'); status = $i.properties.status; tags = $tags; comments = $rows
            playbookRunMatched = [bool]($playbookRow -and $playbookRow.RunStatus -eq 'Succeeded')
        }))
    }
}
