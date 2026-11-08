<#
.SYNOPSIS
    Waits for Defender's real L12 Shared Key assessment without manufacturing a finding.
.DESCRIPTION
    Reads only the existing export store and saves a dated private receipt. An optional refresh
    requests Azure Policy evaluation for the L12 resource group only. Policy completion is not
    Defender assessment completion. No container, paid plan, policy assignment or finding is created.
.PARAMETER Minutes
    Maximum foreground observation window. A timeout exits 1 and leaves the gate open.
.PARAMETER RefreshPolicy
    Request the documented resource-group evaluation once before polling Defender.
.EXAMPLE
    ./Wait-L12Assessment.ps1 -Minutes 15 -RefreshPolicy
#>
[CmdletBinding()]
param([ValidateRange(0,60)][int]$Minutes=15, [switch]$RefreshPolicy)
. (Join-Path $PSScriptRoot 'L12.Common.ps1')
. (Join-Path $PSScriptRoot 'L12.Checks.ps1')
[void](Assert-L12Context)
$cfg=$script:L12Config
$lab=Get-L12Outputs
$started=[DateTime]::UtcNow
$deadline=$started.AddMinutes($Minutes)
$reads=[Collections.Generic.List[object]]::new()
$passed=$false
$lastStatus=''
if ($RefreshPolicy) {
    # Keep evaluation within this fixture; never toggle shared security plans to chase freshness.
    [void](Invoke-L12Az @('policy','state','trigger-scan','--resource-group',$cfg.resourceGroup,'--no-wait'))
    Write-Host "Policy evaluation requested for $($cfg.resourceGroup); Defender ingestion is a separate step."
}
try {
    do {
        $assessment=Invoke-L12Rest -AllowNotFound -Path "$($lab.storageId)/providers/Microsoft.Security/assessments/$($cfg.posture.sharedKeyAssessment)?api-version=2021-06-01"
        $status=[string](Get-L12Value $assessment 'properties.status.code')
        if (-not $status) { $status='NOT ASSESSED' }
        $reads.Add([ordered]@{observedUtc=[DateTime]::UtcNow.ToString('o');status=$status;assessment=$assessment})
        if ($status -ne $lastStatus) { Write-Host "$([DateTime]::UtcNow.ToString('HH:mm:ss')) UTC: $status"; $lastStatus=$status }
        $passed=(Get-L12AssessmentGate $status $true) -eq 'PASS'
        if ($passed -or [DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Seconds ([Math]::Min(30,[Math]::Max(1,[int]($deadline-[DateTime]::UtcNow).TotalSeconds)))
    } while ($true)
} finally {
    [void](Write-L12Evidence 'assessment-wait' ([ordered]@{startedUtc=$started.ToString('o');finishedUtc=[DateTime]::UtcNow.ToString('o');resourceId=$lab.storageId;policyRefreshRequested=[bool]$RefreshPolicy;assessmentGatePassed=$passed;observations=$reads}))
}
if (-not $passed) { Write-Host 'Assessment gate remains open. Do not assign or substitute policy compliance for a Defender finding.'; exit 1 }
Write-Host 'Defender reports the actual Shared Key finding as Unhealthy. The assignment demonstration can proceed.'
