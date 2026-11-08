<#
.SYNOPSIS
Adds, reads, or removes the named CanNotDelete lock on the empty SC500 lock-demo group.
.DESCRIPTION
Never issues a group DELETE. The guarded deletion attempt belongs to the separately rehearsed recording step.
Refuses a nonempty or incorrectly tagged group and leaves the empty group available for another run.
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Status','Lock','Unlock')][string]$State='Status')
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
$null=Assert-Sc500Context
$group='rg-sc500-lock-lab'
$null=Assert-Sc500OwnedGroup -Name $group
$resources=@(Invoke-Sc500Az -Arguments @('resource','list','--resource-group',$group,'--subscription',$script:Sc500Config.subscriptionId))
if ($resources.Count) { throw 'Lock demo group is not empty. Do not use it as a deletion fixture.' }
$locks=@(Invoke-Sc500Az -Arguments @('lock','list','--resource-group',$group,'--subscription',$script:Sc500Config.subscriptionId))
$named=@($locks | Where-Object name -eq 'sc500-demo-delete-protection')
if ($State -eq 'Lock' -and $PSCmdlet.ShouldProcess($group,'Set the SC500 CanNotDelete lock')) {
    if ($named.Count -and $named[0].level -ne 'CanNotDelete') { throw 'Existing named lock has a different level. Inspect it rather than changing it silently.' }
    if (-not $named.Count) { $null=Invoke-Sc500Az -Arguments @('lock','create','--name','sc500-demo-delete-protection','--lock-type','CanNotDelete','--resource-group',$group,'--notes','SC500 Lesson 1 disposable lock demonstration','--subscription',$script:Sc500Config.subscriptionId) }
}
if ($State -eq 'Unlock' -and $named.Count -and $PSCmdlet.ShouldProcess($named[0].id,'Remove only the SC500 demonstration lock')) {
    $null=Invoke-Sc500Az -Arguments @('lock','delete','--ids',$named[0].id,'--subscription',$script:Sc500Config.subscriptionId)
}
$current=@(Invoke-Sc500Az -Arguments @('lock','list','--resource-group',$group,'--subscription',$script:Sc500Config.subscriptionId))
Write-Sc500Evidence -Name 'lock-state' -Value @{resourceGroup=$group;locks=$current;deleteAttempted=$false;whatIf=[bool]$WhatIfPreference} | Write-Host
$current | ConvertTo-Json -Depth 10
