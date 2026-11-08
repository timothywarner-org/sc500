<#
.SYNOPSIS
    Uploads the official harmless EICAR fixture directly from memory to the Lesson 4 intake.
.DESCRIPTION
    Uses the existing Entra sign-in. No local test file, antivirus exclusion, new role, or
    subscription-plan change is required. Checks the intake scan configuration first.
    ScanResults reads the resulting tags and real Defender alert separately.
.EXAMPLE
    ./Invoke-L04EicarTest.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L04.Common.ps1')
[void](Assert-L04Context)
$lab = Get-L04Outputs
$setting = Invoke-L04Arm -Path "$($lab.intakeId)/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2025-06-01"
if (-not (Get-L04Value $setting 'properties.isEnabled') -or -not (Get-L04Value $setting 'properties.malwareScanning.onUpload.isEnabled')) {
    throw 'Intake malware scanning is not enabled. Run the OverrideIntake demo first.'
}
# A byte stream tests cloud scanning without putting the antivirus fixture on this workstation.
& $script:L04Python (Join-Path $PSScriptRoot 'upload_eicar.py')
if ($LASTEXITCODE -ne 0) { throw 'EICAR upload did not finish. No detection is claimed.' }
