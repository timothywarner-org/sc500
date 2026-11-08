<#
.SYNOPSIS
Checks or registers the Azure providers and encryption-at-host feature required by Lesson 1.
.DESCRIPTION
Registration is explicit through -Register. It creates no billable VM or networking resource.
The deployment remains blocked until registration completes; do not silently turn encryption off.
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Register)
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
$null=Assert-Sc500Context
foreach ($namespace in @('Microsoft.Compute','Microsoft.Network')) {
    $provider=Invoke-Sc500Az -Arguments @('provider','show','--namespace',$namespace,'--subscription',$script:Sc500Config.subscriptionId)
    if ($provider.registrationState -ne 'Registered') {
        if (-not $Register) { throw "Provider $namespace is not registered. Run with -Register." }
        if ($PSCmdlet.ShouldProcess($namespace,'Register provider')) { $null=Invoke-Sc500Az -Arguments @('provider','register','--namespace',$namespace,'--wait','--subscription',$script:Sc500Config.subscriptionId) }
    }
}
$feature=Invoke-Sc500Az -Arguments @('feature','show','--namespace','Microsoft.Compute','--name','EncryptionAtHost','--subscription',$script:Sc500Config.subscriptionId)
if ($feature.properties.state -ne 'Registered') {
    if (-not $Register) { throw 'EncryptionAtHost is not registered. Run with -Register, then recheck after Azure completes registration.' }
    if ($PSCmdlet.ShouldProcess('Microsoft.Compute/EncryptionAtHost','Register feature')) {
        $feature=Invoke-Sc500Az -Arguments @('feature','register','--namespace','Microsoft.Compute','--name','EncryptionAtHost','--subscription',$script:Sc500Config.subscriptionId)
    }
}
Write-Sc500Evidence -Name 'feature-registration' -Value $feature | Write-Host
Write-Host "EncryptionAtHost: $($feature.properties.state)"
if ($feature.properties.state -ne 'Registered') { Write-Warning 'Registration is pending. Recheck before deploying; no resources were deployed by this script.' }
