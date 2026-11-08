<#
.SYNOPSIS
Deletes only the three owned Lesson 1 resource groups after recording is complete.
.DESCRIPTION
Deletion is separate from deployment and ordinary demo reset. Requires -RecordingComplete and confirmation.
Checks the exact subscription, group allowlist, ownership tags, current inventory, and resource locks.
Keeps Debra, the directory app fixtures, role definitions, and local evidence for later course lessons.
.EXAMPLE
./scripts/Remove-Sc500Lesson01.ps1 -RecordingComplete -WhatIf
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([switch]$RecordingComplete)
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
if (-not $RecordingComplete) { throw 'Baseline retention is the default. Supply -RecordingComplete only after the recording is accepted.' }
$null=Assert-Sc500Context
# Validate every target before deleting the first group; this prevents partial cleanup after an ownership mismatch.
foreach ($name in $script:Sc500Config.resourceGroups) {
    $exists=Invoke-Sc500Az -Arguments @('group','exists','--name',$name,'--subscription',$script:Sc500Config.subscriptionId)
    if ($exists) {
        $null=Assert-Sc500OwnedGroup -Name $name
        $locks=@(Invoke-Sc500Az -Arguments @('lock','list','--resource-group',$name,'--subscription',$script:Sc500Config.subscriptionId))
        if ($locks.Count) { throw "Remove the intended demonstration lock explicitly before cleanup: $name" }
    }
}
$inventory=@()
$targets=@()
foreach ($name in $script:Sc500Config.resourceGroups) {
    $exists=Invoke-Sc500Az -Arguments @('group','exists','--name',$name,'--subscription',$script:Sc500Config.subscriptionId)
    if ($exists) {
        $inventory+=@(Invoke-Sc500Az -Arguments @('resource','list','--resource-group',$name,'--subscription',$script:Sc500Config.subscriptionId))
        $targets+=$name
    }
}
# Preserve the full target inventory even if a later deletion fails partway through.
Write-Sc500Evidence -Name 'cleanup-target-inventory' -Value @{resources=$inventory;whatIf=[bool]$WhatIfPreference;recordingComplete=$true} | Write-Host
foreach ($name in $targets) {
    if ($PSCmdlet.ShouldProcess($name,'Permanently delete this SC500 resource group and its contained resources')) {
        $null=Invoke-Sc500Az -Arguments @('group','delete','--name',$name,'--yes','--subscription',$script:Sc500Config.subscriptionId)
    }
}
