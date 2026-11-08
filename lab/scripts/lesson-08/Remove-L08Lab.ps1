<#
.SYNOPSIS
    Deletes the whole Lesson 8 lab when the course no longer needs it. Your call, not a
    routine step.

.DESCRIPTION
    Deletes rg-servers-prod-eastus2 after checking its managedBy tag. That removes the VMs, Bastion,
    the policy assignments, the Arc machine resource, and any JIT policy in the group. Then it
    deletes the saved SSH public key and image version so the next Deploy-L08Lab.ps1 -Deploy
    starts fresh. The private key file in local app data is left for you to delete; this script
    never touches it. Evidence files stay. Asks for the resource group name unless -Force.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Remove-L08Lab.ps1
#>
[CmdletBinding()]
param([switch]$Force)
. (Join-Path $PSScriptRoot 'L08.Common.ps1')
[void](Assert-L08Context)
$cfg = $script:L08Config
$rg = $cfg.resourceGroup
if (-not (Invoke-L08Az @('group', 'exists', '--name', $rg))) { Write-Host "$rg doesn't exist." }
else {
    $group = Invoke-L08Az @('group', 'show', '--name', $rg)
    if ((Get-L08Value $group 'tags.managedBy') -ne $cfg.managedBy) { throw "$rg isn't tagged managedBy=$($cfg.managedBy). Nothing was deleted." }
    if (-not $Force) {
        $answer = Read-Host "Delete $rg and everything in it? Type the resource group name to confirm"
        if ($answer -ne $rg) { Write-Host 'Cancelled.'; return }
    }
    Write-Host "Deleting $rg."
    [void](Invoke-L08Az -Raw @('group', 'delete', '--name', $rg, '--yes'))
}
foreach ($f in 'ssh-public-key.txt', 'image-version.txt') {
    $p = Join-Path $script:L08State $f
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}
$gone = -not (Invoke-L08Az @('group', 'exists', '--name', $rg))
[void](Write-L08Evidence 'remove-lab' ([ordered]@{ resourceGroupGone = $gone }))
if (-not $gone) { throw "$rg still exists." }
Write-Host "Lesson 8 lab removed. The Bastion key file is still at $(Get-L08AdminKeyPath); delete it when you no longer need it."
