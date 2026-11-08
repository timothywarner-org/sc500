<#
.SYNOPSIS
    Run offline regression cases for the L12 evidence and cleanup contracts.
.DESCRIPTION
    These cases prove classifiers and gates, not Azure service behavior or a human recording.
#>
[CmdletBinding()]param()
. (Join-Path $PSScriptRoot 'L12.Common.ps1')
. (Join-Path $PSScriptRoot 'L12.Checks.ps1')
$passed=0
function Check([string]$Name,[bool]$Ok) { if (-not $Ok) { throw "FAIL $Name" }; $script:passed++; Write-Host "PASS $Name" }
Check 'UTC string preserved' ((ConvertTo-L12UtcTime '2026-09-28T16:35:10Z').UtcDateTime.Hour -eq 16)
Check 'JSON DateTime preserved' ((ConvertTo-L12UtcTime ('{"t":"2026-09-28T16:35:10Z"}' | ConvertFrom-Json).t).UtcDateTime.Hour -eq 16)
Check 'Allowed request' ((Get-L12KeyProbeOutcome 0 '') -eq 'ALLOWED')
Check 'Specific key denial' ((Get-L12KeyProbeOutcome 1 'ErrorCode:KeyBasedAuthenticationNotPermitted') -eq 'KEY AUTH DISABLED')
Check 'Network failure is not proof' ((Get-L12KeyProbeOutcome 1 'Name resolution failed') -like 'ERROR*')
Check 'Permission failure is not proof' ((Get-L12KeyProbeOutcome 1 'AuthorizationPermissionMismatch') -like 'ERROR*')
$before=@{outcome='ALLOWED'}; $after=@{outcome='KEY AUTH DISABLED'}
Check 'Complete access comparison' (Test-L12RemediationProof $before $after $true 0)
Check 'Entra failure rejected' (-not (Test-L12RemediationProof $before $after $true 1))
Check 'Missing before proof rejected' (-not (Test-L12RemediationProof @{outcome='ERROR'} $after $true 0))
$setting=@{isEnabled=$true;overrideSubscription=$true;malwareScanningOnUpload=$true;capGBPerMonth=5;sensitiveDataDiscovery=$true}
Check 'Complete override accepted' (Test-L12StorageOverride $setting 5)
$setting.capGBPerMonth=10000
Check 'Wrong cap rejected' (-not (Test-L12StorageOverride $setting 5))
$setting.capGBPerMonth=5; $setting.malwareScanningOnUpload=$false
Check 'Scanning disabled rejected' (-not (Test-L12StorageOverride $setting 5))
$time=[DateTimeOffset]::Parse('2026-09-28T16:37:52Z')
$tags=@{'Malware Scanning scan result'='No threats found';'Malware Scanning scan time UTC'='2026-09-28T16:37:54Z'}
Check 'Fresh clean scan accepted' (Test-L12FreshCleanScan $tags $time)
$tags['Malware Scanning scan time UTC']='2026-09-28T16:37:20Z'
Check 'Old clean tag rejected' (-not (Test-L12FreshCleanScan $tags $time))
$tags['Malware Scanning scan time UTC']='2026-09-28T16:37:54Z'; $tags['Malware Scanning scan result']='Not scanned'
Check 'Not scanned rejected' (-not (Test-L12FreshCleanScan $tags $time))
Check 'No tags rejected' (-not (Test-L12FreshCleanScan @{} $time))
Check 'Known reset scope accepted' (Test-L12ResetScope @('parts-exports') @(@{name='lesson'}) 'parts-exports' 'lesson')
Check 'Other container prevents reset' (-not (Test-L12ResetScope @('parts-exports','records') @() 'parts-exports' 'lesson'))
Check 'Other assignment prevents reset' (-not (Test-L12ResetScope @() @(@{name='external'}) 'parts-exports' 'lesson'))
Check 'Missing assessment fails Recording' ((Get-L12AssessmentGate '' $true) -eq 'FAIL')
Check 'Healthy assessment fails fault setup' ((Get-L12AssessmentGate 'Healthy' $true) -eq 'FAIL')
Check 'Missing assessment warns Baseline' ((Get-L12AssessmentGate '' $false) -eq 'WARN')
Check 'Assessed fault passes' ((Get-L12AssessmentGate 'Unhealthy' $true) -eq 'PASS')
$due=[DateTimeOffset]::Parse('2026-10-12T00:00:00Z')
$assignment=@{id='/fixture/assessment/governanceAssignments/lesson';properties=@{owner='<your-admin-upn>';remediationDueDate='2026-10-12T00:00:00Z';isGracePeriod=$true;governanceEmailNotification=@{disableManagerEmailNotification=$true;disableOwnerEmailNotification=$true}}}
Check 'Exact governance assignment accepted' (Test-L12AssignmentProof $assignment $assignment.id '<your-admin-upn>' $due)
Check 'Wrong finding rejected' (-not (Test-L12AssignmentProof $assignment '/different/assessment' '<your-admin-upn>' $due))
Check 'Wrong owner rejected' (-not (Test-L12AssignmentProof $assignment $assignment.id 'sc500.debra@<your-domain>' $due))
Check 'Wrong deadline rejected' (-not (Test-L12AssignmentProof $assignment $assignment.id '<your-admin-upn>' $due.AddDays(1)))
$assignment.properties.isGracePeriod=$false
Check 'Missing grace period rejected' (-not (Test-L12AssignmentProof $assignment $assignment.id '<your-admin-upn>' $due))
$assignment.properties.isGracePeriod=$true; $assignment.properties.governanceEmailNotification.disableOwnerEmailNotification=$false
Check 'Unexpected email notifications rejected' (-not (Test-L12AssignmentProof $assignment $assignment.id '<your-admin-upn>' $due))
Check 'Missing assignment rejected' (-not (Test-L12AssignmentProof $null '/fixture/assessment/governanceAssignments/lesson' '<your-admin-upn>' $due))
Write-Host "$passed offline regression cases passed. No live behavior is implied."
