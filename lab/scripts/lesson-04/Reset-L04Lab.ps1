<#
.SYNOPSIS
    Returns the Lesson 4 lab to CTSO-L04-BASELINE so any demo can be recorded again.

.DESCRIPTION
    Restores what the demos change and nothing else:
      records account  Shared Key allowed again, synthetic blobs re-uploaded, stored access
                       policy recreated, and the workstation's firewall rule removed.
      intake account   Test uploads deleted, and the per-account Defender for Storage
                       override removed so the account inherits the subscription plan again.
      SQL              Synthetic rows restored (idempotent). Settings are declared in Bicep
                       and aren't changed by the demos.
    Nothing is deleted from Azure except the lab's own test blobs, and no subscription-wide
    Defender plan is touched.

    Parked (the StorageAccounts plan Free): the account-protection step is skipped with a
    message, because there is no plan to inherit and enabling an account on its own would
    bill it. Everything else resets. Set-L04DefenderWindow.ps1 -State Open runs this script
    again with the plan on, which applies protection to both accounts.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Reset-L04Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L04.Common.ps1')
[void](Assert-L04Context)
$lab = Get-L04Outputs

# Preserve scan tags and alert IDs before resetting this lesson's disposable test blobs.
& (Join-Path $PSScriptRoot 'Invoke-L04DefenderDemo.ps1') -Mode ScanResults

Write-Host 'Records account: restoring the demo 4.1 starting state.'
& (Join-Path $PSScriptRoot 'Set-L04SharedKeyGuardrail.ps1') -Mode Audit
# Policy changes propagate asynchronously. Retry only this course assignment's denial.
$ready=$false
for($attempt=0;$attempt -lt 20;$attempt++) {
    try { Initialize-L04StorageBaseline -Lab $lab; $ready=$true; break }
    catch {
        $failure=$_.ToString()+' '+$_.ErrorDetails.Message
        if($failure -notmatch 'RequestDisallowedByPolicy' -or $failure -notmatch 'sc500-l04-no-sharedkey'){throw}
        Write-Host 'The old Deny effect is still propagating. Retrying the course baseline in 30 seconds.'
        Start-Sleep -Seconds 30
    }
}
if(-not $ready){throw 'Audit has not propagated. Leave the account protected and retry Reset-L04Lab.ps1 later.'}

Write-Host 'Intake account: removing test uploads.'
$blobs = Invoke-L04Az -NoSubscription @('storage', 'blob', 'list', '--account-name', $lab.intakeAccount, '--container-name', $script:L04Config.intakeContainer, '--auth-mode', 'login', '--query', '[].name')
$fixtures = @('CTSO-UPLOAD-7731-site-photo-notes.txt', 'CTSO-UPLOAD-7732-eicar-test.txt', 'eicar-test.txt')
if (@($blobs | Where-Object { $_ -and $_ -notin $fixtures }).Count) { throw 'Unexpected intake blob found. Reset only removes the named Lesson 4 fixtures.' }
foreach ($b in @($blobs)) {
    if ($b) { [void](Invoke-L04Az -NoSubscription @('storage', 'blob', 'delete', '--account-name', $lab.intakeAccount, '--container-name', $script:L04Config.intakeContainer, '--name', $b, '--auth-mode', 'login')); Write-Host "  deleted $b" }
}

if ((Get-L04PlanTier StorageAccounts) -eq 'Standard') {
    Write-Host 'Storage accounts: apply the existing subscription settings, with account overrides off.'
    Set-L04StorageInheritance -Lab $lab
}
else { Write-Host 'SKIP account protection: the StorageAccounts plan is Free (parked). The Defender window applies it.' }

Write-Host 'SQL: restoring synthetic rows.'
$rows = Initialize-L04SqlBaseline -Lab $lab
Write-Host "  $rows service records."

[void](Write-L04Evidence 'reset' @{ lab = $lab.resourceGroup; intakeBlobsRemoved = @($blobs).Count; sqlRows = $rows })
Write-Host 'Lesson 4 is at CTSO-L04-BASELINE. Run Test-L04Lab.ps1 to confirm.'
