<#
.SYNOPSIS
    Demo 8.4 for SC-500 Lesson 8: machine configuration's verdict on each server, and what
    Defender Vulnerability Management reports and how it's set.

.DESCRIPTION
    Read-only.
      Assignments      Machine configuration guest assignments on the ServiceHub app server (vm-servicehub-prod-001) and the Arc machine,
                       with their compliance status and last check.
      Rules            The Linux baseline's non-compliant rules on a machine, with the reason each
                       one gives. -Machine picks App (default) or Arc.
      Recommendations  Defender for Cloud's recommendations for the lab machines, unhealthy first.
      Vulnerabilities  Vulnerability findings (Defender Vulnerability Management) for the lab
                       machines, by severity, with the top CVEs.
      Settings         Where vulnerability assessment is set: the subscription's provider, and the
                       per-VM assessment resource on the ServiceHub app server (vm-servicehub-prod-001).
      All              Assignments, Rules, Recommendations, Vulnerabilities, and Settings.

.PARAMETER Mode
    One of the modes above.
.PARAMETER Machine
    App or Arc, for -Mode Rules.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Invoke-L08ConfigDemo.ps1 -Mode Assignments
#>
[CmdletBinding()]
param(
    [ValidateSet('Assignments', 'Rules', 'Recommendations', 'Vulnerabilities', 'Settings', 'All')][string]$Mode = 'All',
    [ValidateSet('App', 'Arc')][string]$Machine = 'App'
)
. (Join-Path $PSScriptRoot 'L08.Common.ps1')
[void](Assert-L08Context)
$cfg = $script:L08Config
$rg = $cfg.resourceGroup
$n = $cfg.names
$sub = $cfg.subscriptionId
$gcApi = 'api-version=2024-04-05'
$targets = [ordered]@{
    App = Get-L08VmId $n.appVm
    Arc = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.HybridCompute/machines/$($n.arcMachine)"
}

function Get-Assignments([string]$MachineId) {
    $r = Invoke-L08Arm -Path "$MachineId/providers/Microsoft.GuestConfiguration/guestConfigurationAssignments?$gcApi" -AllowNotFound
    return @(if ($r) { @($r.value) })
}

if ($Mode -in 'Assignments', 'All') {
    Write-Host '== Machine configuration guest assignments'
    $rows = foreach ($k in $targets.Keys) {
        foreach ($a in Get-Assignments $targets[$k]) {
            [pscustomobject]@{
                Machine     = $k
                Assignment  = ($a.name -split '\$')[0]
                Compliance  = Get-L08Value $a 'properties.complianceStatus'
                LastChecked = Get-L08Value $a 'properties.lastComplianceStatusChecked'
                Type        = Get-L08Value $a 'properties.guestConfiguration.assignmentType'
            }
        }
    }
    $rows = @($rows)
    [void](Write-L08Evidence 'config-assignments' ([pscustomobject]@{ rows = $rows }))
    if ($rows.Count) { $rows | Format-Table -AutoSize | Out-String -Width 180 | Out-Host } else { Write-Host '(no guest assignments yet; the first report can take 30 minutes or more)' }
}

if ($Mode -in 'Rules', 'All') {
    Write-Host "== Linux baseline rules on $Machine that aren't compliant"
    $baseline = @(Get-Assignments $targets[$Machine] | Where-Object { $_.name -like 'AzureLinuxBaseline*' })
    if (-not $baseline.Count) { Write-Host '(no baseline report yet)' }
    else {
        # The assignment names its latest report; the report holds one entry per baseline rule.
        $report = Invoke-L08Arm -Path ((Get-L08Value $baseline[0] 'properties.latestReportId') + "?$gcApi")
        $resources = @(Get-L08Value $report 'properties.details.resources')
        $bad = @($resources | Where-Object { $_.complianceStatus -ne 'Compliant' })
        $rows = @($bad | ForEach-Object {
                $reason = @(Get-L08Value $_ 'reasons') | Select-Object -First 1
                [pscustomobject]@{ Rule = Get-L08Value $_ 'properties.ResourceId'; Status = $_.complianceStatus; Reason = $(if ($reason) { ($reason.phrase -replace '\s+', ' ').Trim() } else { '' }) }
            })
        $summary = [pscustomobject]@{ Machine = $Machine; Rules = $resources.Count; NotCompliant = $bad.Count; ReportTime = Get-L08Value $report 'properties.endTime' }
        [void](Write-L08Evidence "config-rules-$($Machine.ToLower())" ([pscustomobject]@{ summary = $summary; notCompliant = $rows }))
        $summary | Format-List | Out-String -Width 180 | Out-Host
        $rows | Select-Object -First 12 | Format-Table -Wrap | Out-String -Width 180 | Out-Host
    }
}

if ($Mode -in 'Recommendations', 'All') {
    Write-Host '== Defender for Cloud recommendations for the lab machines'
    $q = @"
securityresources
| where type == 'microsoft.security/assessments'
| where tolower(id) contains '/resourcegroups/$($rg.ToLower())/'
| extend machine = tostring(split(tolower(id), '/providers/microsoft.security/')[0])
| project machine = tostring(split(machine, '/')[-1]), recommendation = tostring(properties.displayName), status = tostring(properties.status.code), severity = tostring(properties.metadata.severity)
| order by status desc, machine asc, recommendation asc
"@
    $rows = @(Invoke-L08Graph -Query $q)
    [void](Write-L08Evidence 'config-recommendations' ([pscustomobject]@{ rows = $rows }))
    if ($rows.Count) { $rows | Format-Table -AutoSize | Out-String -Width 200 | Out-Host } else { Write-Host '(no assessments yet; Defender assesses new machines within hours)' }
}

if ($Mode -in 'Vulnerabilities', 'All') {
    Write-Host '== Vulnerability findings (Defender Vulnerability Management)'
    $q = @"
securityresources
| where type == 'microsoft.security/assessments/subassessments'
| where tolower(id) contains '/resourcegroups/$($rg.ToLower())/'
| where tostring(properties.status.code) == 'Unhealthy'
| extend machine = tostring(split(tostring(split(tolower(id), '/providers/microsoft.security/')[0]), '/')[-1])
| project machine, cve = tostring(properties.id), title = tostring(properties.displayName), severity = tostring(properties.status.severity)
"@
    $rows = @(Invoke-L08Graph -Query $q)
    $bySev = @($rows | Group-Object machine, severity | ForEach-Object { [pscustomobject]@{ Machine = $_.Group[0].machine; Severity = $_.Group[0].severity; Findings = $_.Count } })
    [void](Write-L08Evidence 'config-vulnerabilities' ([pscustomobject]@{ summary = $bySev; top = @($rows | Select-Object -First 15) }))
    if ($rows.Count) {
        $bySev | Sort-Object Machine, Severity | Format-Table -AutoSize | Out-String -Width 160 | Out-Host
        $rows | Where-Object severity -in 'Critical', 'High' | Select-Object -First 8 | Format-Table -AutoSize | Out-String -Width 200 | Out-Host
    } else { Write-Host '(no findings returned; check sensor health and collection freshness before interpreting this as a clean result)' }
}

if ($Mode -in 'Settings', 'All') {
    Write-Host '== Vulnerability assessment settings'
    $va = Invoke-L08Arm -Path "/subscriptions/$sub/providers/Microsoft.Security/serverVulnerabilityAssessmentsSettings/AzureServersSetting?api-version=2023-05-01"
    $perVm = Invoke-L08Arm -Path "$($targets.App)/providers/Microsoft.Security/serverVulnerabilityAssessments?api-version=2015-06-01-preview" -AllowNotFound
    $row = [pscustomobject]@{
        'Subscription provider'  = Get-L08Value $va 'properties.selectedProvider'
        'Set by'                 = Get-L08Value $va 'systemData.createdBy'
        "Per-VM on $($n.appVm)"  = $(if ($perVm -and @($perVm.value).Count) { (@($perVm.value) | ForEach-Object { "$($_.name) ($($_.properties.provisioningState))" }) -join ', ' } else { 'none' })
    }
    [void](Write-L08Evidence 'config-va-settings' $row)
    $row | Format-List | Out-String -Width 160 | Out-Host
}
