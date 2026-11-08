<#
.SYNOPSIS
    Puts the legacy app server back at the access demo's starting point WITHOUT changing its public IP.

.DESCRIPTION
    The access demo (demo 2) enables JIT, deletes the standing SSH rule and requests access. A JIT request
    can't be withdrawn, and Remove-L08Bounded.ps1 deletes the public IP. This reset keeps the IP:
      1. Deletes the lesson's JIT policy if it exists (Defender stops managing port 22).
      2. Redeploys legacy.bicep through Deploy-L08Bounded.ps1 -Deploy. The NSG's rule list is replaced by the
         template's, which removes Defender's deny rule and any request's allow rule and restores
         allow-ssh-admin-standing for this workstation's current public IP. The VM, NIC, disk and public IP are
         unchanged (what-if reports Modify or NoChange, never Delete).
      3. Starts the VM if a shutdown schedule deallocated it. A redeploy doesn't start a stopped VM.
      4. Reads the NSG rules back and probes TCP 22 without signing in.
    Changes only the legacy server's JIT policy, NSG rules, shutdown schedule status and power state.
    Demo step 2.2 reads the IP from Azure, so an IP change wouldn't break the demo, but this reset
    still warns about one because nothing here should change it.

.PARAMETER Soak
    Passed to Deploy-L08Bounded.ps1: keeps the legacy server's shutdown schedule Disabled until the demo ends.
    Use it for every reset between the night before and the last take.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Reset-L08Access.ps1 -Soak
#>
[CmdletBinding()]
param([switch]$Soak)
. (Join-Path $PSScriptRoot 'L08.Common.ps1')
[void](Assert-L08Context)
$cfg = $script:L08Config
$jit = (Get-L08JitPath) + '?api-version=2020-01-01'
$ipArgs = @('network', 'public-ip', 'show', '--resource-group', $cfg.resourceGroup, '--name', $cfg.names.legacyPublicIp, '--query', 'ipAddress', '--output', 'tsv')
$ipBefore = Invoke-L08Az -Raw $ipArgs
if (Invoke-L08Arm -Path $jit -AllowNotFound) {
    [void](Invoke-L08Arm -Method delete -Path $jit)
    Write-Host 'Deleted the lesson JIT policy.'
}
else { Write-Host 'No JIT policy to delete.' }

# Splatting a hashtable passes -Soak only when this script got it.
$deployArgs = @{ Deploy = $true }
if ($Soak) { $deployArgs.Soak = $true }
& (Join-Path $PSScriptRoot 'Deploy-L08Bounded.ps1') @deployArgs

# A shutdown schedule may have deallocated the VM overnight. ARM redeploys never start it.
$power = Invoke-L08Az -Raw @('vm', 'get-instance-view', '--resource-group', $cfg.resourceGroup, '--name', $cfg.names.legacyVm, '--query', "instanceView.statuses[?starts_with(code,'PowerState/')].code | [0]", '--output', 'tsv')
if ($power -ne 'PowerState/running') {
    Write-Host "The legacy VM is $power. Starting it."
    [void](Invoke-L08Az -Raw @('vm', 'start', '--resource-group', $cfg.resourceGroup, '--name', $cfg.names.legacyVm))
}

$ipAfter = Invoke-L08Az -Raw $ipArgs
if ($ipAfter -ne $ipBefore) { Write-Warning "The legacy public IP changed from $ipBefore to $ipAfter. Demo step 2.2 reads it live, so the demo still works." }
$nsg = Invoke-L08Az @('network', 'nsg', 'show', '--resource-group', $cfg.resourceGroup, '--name', $cfg.names.legacyNsg)
$rules = @($nsg.securityRules | Sort-Object priority | ForEach-Object { '{0} {1} {2}' -f $_.priority, $_.access, $_.name })
$rules | Out-Host
if ($rules.Count -ne 1 -or $rules[0] -notlike '1000 Allow allow-ssh-admin-standing') { throw 'The NSG is not back to the single standing rule.' }
$probe = Test-L08Tcp -Address $ipAfter -Port 22
"Probe $ipAfter`:22 -> $($probe.Result) ($($probe.Detail))"
if ($probe.Result -ne 'Open') { throw 'Port 22 does not answer from this workstation.' }
[void](Write-L08Evidence 'access-reset' ([ordered]@{ ip = $ipAfter; rules = $rules; probe = $probe.Result; soak = [bool]$Soak }))
Write-Host "Access demo reset: standing rule only, IP $ipAfter, port 22 answers."
