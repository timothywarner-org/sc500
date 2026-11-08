<#
.SYNOPSIS
    Offline regression tests for L14 case selection and evidence rejection, with no Azure calls.
.DESCRIPTION
    Uses an isolated private fixture directory. Synthetic contract rows are never written to the
    real lab evidence directory or treated as service observations.
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L14.Common.ps1')
$script:L14State = Join-Path $script:L14Lab ('.azure/authoring/lesson-14-v02/contracts-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($script:L14State)
$count=0
function Check([bool]$Condition,[string]$Name) { if (-not $Condition) { throw "FAIL: $Name" }; $script:count++; Write-Host "PASS: $Name" }
foreach ($status in 'Failed','Running','Cancelled','TimedOut') {
    Check (-not (Test-L14SucceededRun @{name='contract-run';properties=@{status=$status}} 'contract-run')) "Reject $status run"
}
Check (Test-L14SucceededRun @{name='contract-run';properties=@{status='Succeeded'}} 'contract-run') 'Accept exact succeeded run'
Check (-not (Test-L14SucceededRun @{name='other-run';properties=@{status='Succeeded'}} 'contract-run')) 'Reject another succeeded run'
Check (-not (Test-L14SucceededRun $null 'contract-run')) 'Reject missing run'
@{incident=@{incidentName='pinned';incidentNumber=3};fixture=@{fixtureId='00000000-0000-0000-0000-000000000000';fileName='contract-only.csv'}} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $script:L14State 'handoff-case.json')
@{incidentName='newer';incidentNumber=99} | ConvertTo-Json | Set-Content (Join-Path $script:L14State 'last-incident.json')
Check ((Get-L14RecordingIncident).incidentName -eq 'pinned') 'Newer incident does not displace pinned case'
Check ((Get-L14LastFixture).fileName -eq 'contract-only.csv') 'Read pinned fixture'
function Get-L14IncidentComments { param($L13Lab,$IncidentName) return @(@{properties=@{message='Purview Audit: synthetic-record contract-only.csv'}}) }
Check (-not (Test-L14AuditCapture @{}).passed) 'Comment without export fails Audit'
$export=Join-Path $script:L14State 'audit-export.csv'
function Make-Export([string]$User,[string]$File,[string]$Operation='FileUploaded',[string]$Id='synthetic-record') {
    @{AuditData=(@{Id=$Id;CreationTime='2026-09-28T00:00:00Z';UserId=$User;Operation=$Operation;ObjectId="https://example.invalid/$File"}|ConvertTo-Json -Compress)} | Export-Csv -LiteralPath $export -NoTypeInformation
}
Make-Export 'wrong@example.invalid' 'contract-only.csv'
Check (-not (Test-L14AuditCapture @{}).passed) 'Wrong user fails'
Make-Export $script:L14Config.operatorUpn 'other.csv'
Check (-not (Test-L14AuditCapture @{}).passed) 'Wrong file fails'
Make-Export $script:L14Config.operatorUpn 'contract-only.csv' 'FileModified'
Check (-not (Test-L14AuditCapture @{}).passed) 'Wrong operation fails'
Make-Export $script:L14Config.operatorUpn 'contract-only.csv' 'FileUploaded' 'unattached-record'
Check (-not (Test-L14AuditCapture @{}).passed) 'Unattached record fails'
Make-Export $script:L14Config.operatorUpn 'contract-only.csv'
Check (Test-L14AuditCapture @{}).passed 'Matching test export and comment satisfy contract'
foreach ($p in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($p.FullName,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Parse $($p.Name)"
}
@{contractTests=$count;syntheticOnly=$true;azureCalls=0;passed=$true} | ConvertTo-Json | Set-Content (Join-Path $script:L14Lab '.azure/authoring/lesson-14-v02/lab-contracts.json')
Write-Host "$count offline contracts passed. No live evidence was created."
