<#
.SYNOPSIS
    Deletes the whole Lesson 7 lab (retained and bounded) when the course no longer needs it.

.DESCRIPTION
    Deletes the lesson resource group (config.json; rg-perimeter-shared-eastus2) after checking
    its managedby tag, then purges the soft-deleted Key Vault so its global name is free, then
    deletes this subscription's saved public CA certificates, SSH public key, and image version,
    so the next Deploy-L07Lab.ps1 -Deploy mints a fresh CA pair. The budget lives in the group and
    goes with it. Evidence files stay. Asks for confirmation unless -Force is passed.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Remove-L07Lab.ps1
#>
[CmdletBinding()]
param([switch]$Force)
. (Join-Path $PSScriptRoot 'L07.Common.ps1')
[void](Assert-L07Context)
$cfg = $script:L07Config
$rg = $cfg.resourceGroup
if (-not (Invoke-L07Az @('group', 'exists', '--name', $rg))) { Write-Host "$rg doesn't exist." }
else {
    $group = Invoke-L07Az @('group', 'show', '--name', $rg)
    if ("$(Get-L07Value $group 'tags.managedby')" -ne $cfg.managedBy) { throw "$rg isn't tagged managedby=$($cfg.managedBy). Nothing was deleted." }
    $vaults = @(Invoke-L07Az @('keyvault', 'list', '--resource-group', $rg, '--query', '[].name'))
    if (-not $Force) {
        $answer = Read-Host "Delete $rg and purge $($vaults -join ', ')? Type the resource group name to confirm"
        if ($answer -ne $rg) { Write-Host 'Cancelled.'; return }
    }
    Write-Host "Deleting $rg. The firewall, if present, takes the longest."
    [void](Invoke-L07Az -Raw @('group', 'delete', '--name', $rg, '--yes'))
    foreach ($v in $vaults) { [void](Invoke-L07Az -Raw -AllowFailure @('keyvault', 'purge', '--name', $v, '--location', $cfg.location)) }
}
foreach ($f in 'inspection-ca-public.json', 'ssh-public-key.txt', 'image-version.txt') {
    $p = Join-Path $script:L07State $f
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}
$gone = -not (Invoke-L07Az @('group', 'exists', '--name', $rg))
[void](Write-L07Evidence 'remove-lab' ([ordered]@{ resourceGroupGone = $gone }))
if (-not $gone) { throw "$rg still exists." }
Write-Host 'Lesson 7 lab removed.'
