<#
.SYNOPSIS
    Routine cleanup after a Lesson 13 take: removes the demo role assignments and puts the custom
    table's retention back, then reads both back.
.DESCRIPTION
    Keeps everything Lesson 14 needs: the workspace, tables, collected rows, collection rules, WEF,
    and the groups. It doesn't stop the VMs; Stop-L13Lab.ps1 does that.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Reset-L13Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L13.Common.ps1')
$cfg = $script:L13Config
[void](Assert-L13Context)
$lab = Get-L13Outputs
$rgScope = "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$($cfg.resourceGroup)"
$removed = @()
foreach ($g in @($cfg.names.analystGroup, $cfg.names.engineerGroup)) {
    $gid = @(Invoke-L13Az -NoSubscription @('ad', 'group', 'list', '--filter', "displayName eq '$g'", '--query', '[].id'))[0]
    if (-not $gid) { continue }
    foreach ($a in @(Invoke-L13Az @('role', 'assignment', 'list', '--assignee', $gid, '--scope', $rgScope))) {
        if ($a.scope -ne $rgScope) { continue }
        [void](Invoke-L13Az -Raw @('role', 'assignment', 'delete', '--ids', $a.id))
        $removed += "$g : $($a.roleDefinitionName)"; Write-Host "Removed $($a.roleDefinitionName) from $g."
    }
}
[void](Invoke-L13Az @('monitor', 'log-analytics', 'workspace', 'table', 'update', '--resource-group', $cfg.resourceGroup, '--workspace-name', $lab.workspace,
    '--name', $cfg.names.customTable, '--retention-time', "$($cfg.customTable.retentionInDays)", '--total-retention-time', "$($cfg.customTable.totalRetentionInDays)"))
$t = Invoke-L13Rest -Path "$($lab.workspaceId)/tables/$($cfg.names.customTable)?api-version=2023-09-01"
$left = foreach ($g in @($cfg.names.analystGroup, $cfg.names.engineerGroup)) {
    $gid = @(Invoke-L13Az -NoSubscription @('ad', 'group', 'list', '--filter', "displayName eq '$g'", '--query', '[].id'))[0]
    if ($gid) { @(Invoke-L13Az @('role', 'assignment', 'list', '--assignee', $gid, '--scope', $rgScope) | Where-Object scope -EQ $rgScope).Count }
}
$state = [ordered]@{ resetUtc = [DateTime]::UtcNow.ToString('o'); removed = $removed; assignmentsLeft = ($left | Measure-Object -Sum).Sum
    customTable = [ordered]@{ plan = $t.properties.plan; analytics = $t.properties.retentionInDays; total = $t.properties.totalRetentionInDays } }
[void](Write-L13Evidence 'reset' $state)
if ($state.assignmentsLeft -gt 0 -or $t.properties.totalRetentionInDays -ne $cfg.customTable.totalRetentionInDays) { throw 'Reset did not reach the baseline. Read the evidence file.' }
Write-Host "Reset: no demo role assignments; $($cfg.names.customTable) $($t.properties.plan) $($t.properties.retentionInDays)/$($t.properties.totalRetentionInDays) days."
