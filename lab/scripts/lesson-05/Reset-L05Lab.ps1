<#
.SYNOPSIS
    Returns the retained Lesson 5 lab to CTSO-L05-BASELINE after a take.

.DESCRIPTION
    Undoes what demos 5.1 and 5.2 change, in the order that avoids a window with less
    protection than the baseline intends:
      1. Removes the AVNM security admin deployment from eastus2 (the configuration itself
         stays defined, ready for the next take).
      2. Removes every custom rule from nsg-servicehub, leaving only the default rules. That's
         the demo 5.1 starting fault, by design.
    If the bounded VPN lab exists, it also puts the legacy policy back on the branch
    connection (the demo 5.4 starting fault). It doesn't start, stop, or delete anything else,
    and it never touches the bounded Virtual WAN; remove that with Remove-L05Bounded.ps1.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-05\Reset-L05Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L05.Common.ps1')
[void](Assert-L05Context)
$cfg = $script:L05Config
$rg = $cfg.resourceGroup
$record = [ordered]@{}

Write-Host 'Removing the AVNM security admin deployment, if any.'
& (Join-Path $PSScriptRoot 'Invoke-L05AvnmDemo.ps1') -Mode Undeploy | Out-Host
$record.avnm = 'undeployed'

$rules = @(Invoke-L05Az @('network', 'nsg', 'rule', 'list', '--resource-group', $rg, '--nsg-name', 'nsg-servicehub'))
foreach ($r in $rules) {
    Write-Host "Removing NSG rule $($r.name)."
    [void](Invoke-L05Az -Raw @('network', 'nsg', 'rule', 'delete', '--resource-group', $rg, '--nsg-name', 'nsg-servicehub', '--name', $r.name))
}
$record.nsgRulesRemoved = @($rules.name)

if (Invoke-L05Az @('group', 'exists', '--name', $cfg.vpnResourceGroup)) {
    Write-Host 'Putting the legacy policy back on the branch VPN connection.'
    & (Join-Path $PSScriptRoot 'Invoke-L05VpnDemo.ps1') -Mode Break | Out-Host
    $record.vpnBranchPolicy = 'legacy'
}
[void](Write-L05Evidence 'reset' $record)
Write-Host 'Reset complete. Run Test-L05Lab.ps1 to confirm the baseline.'
