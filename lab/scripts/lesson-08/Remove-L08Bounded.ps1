<#
.SYNOPSIS
    Deletes the bounded part of SC-500 Lesson 8: the lesson's JIT policy, the legacy app server (vm-legacyapp-prod-001), its
    public IP, and its NSG.

.DESCRIPTION
    Deletes only resources tagged managedby=sc500-l08-iac and lifecycle bounded, in that order: the JIT
    policy first (so Defender stops managing rules in an NSG that's about to go), then the VM (its
    OS disk and NIC go with it), then the public IP and the NSG. Then it removes the deployment
    record and confirms each resource is gone. Safe to re-run: missing pieces are skipped.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Remove-L08Bounded.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L08.Common.ps1')

[void](Assert-L08Context)
$cfg = $script:L08Config
$rg = $cfg.resourceGroup
$started = Get-Date

if (Invoke-L08Arm -Path ((Get-L08JitPath) + '?api-version=2020-01-01') -AllowNotFound) {
    [void](Invoke-L08Arm -Method delete -Path ((Get-L08JitPath) + '?api-version=2020-01-01'))
    Write-Host 'Deleted the Lesson 8 JIT policy.'
}

function Remove-Tagged([string]$Type, [string]$Name, [string[]]$DeleteArgs) {
    $r = Invoke-L08Az -AllowFailure @('resource', 'show', '--resource-group', $rg, '--resource-type', $Type, '--name', $Name)
    if ($r.ExitCode -ne 0) { Write-Host "$Name is already gone."; return }
    $res = $r.Stdout | ConvertFrom-Json -Depth 50
    # The CAF tag set (November 1, 2026) marks bounded resources with lifecycle 'bounded: ...', not bounded=true.
    if ((Get-L08Value $res 'tags.managedby') -ne $cfg.managedBy -or "$(Get-L08Value $res 'tags.lifecycle')" -notlike 'bounded*') { throw "$Name isn't tagged as this lesson's bounded resource. Nothing deleted." }
    Write-Host "Deleting $Name."
    [void](Invoke-L08Az $DeleteArgs)
}
Remove-Tagged 'Microsoft.Compute/virtualMachines' $cfg.names.legacyVm @('vm', 'delete', '--resource-group', $rg, '--name', $cfg.names.legacyVm, '--yes')
Remove-Tagged 'Microsoft.Network/publicIPAddresses' $cfg.names.legacyPublicIp @('network', 'public-ip', 'delete', '--resource-group', $rg, '--name', $cfg.names.legacyPublicIp)
Remove-Tagged 'Microsoft.Network/networkSecurityGroups' $cfg.names.legacyNsg @('network', 'nsg', 'delete', '--resource-group', $rg, '--name', $cfg.names.legacyNsg)
[void](Invoke-L08Az -AllowFailure @('deployment', 'group', 'delete', '--resource-group', $rg, '--name', $cfg.legacyDeploymentName))

# Read the group through ARM: Azure CLI 2.85.0's az resource list returned [] for this group on November 1, 2026,
# which would make this check pass on nothing. The OS disk carries the VM's tags (Set-L08DiskTags), so it's covered.
$left = @(@((Invoke-L08Arm -Path "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$rg/resources?api-version=2021-04-01").value) |
    Where-Object { "$(Get-L08Value $_ 'tags.lifecycle')" -like 'bounded*' })
if ($left.Count) { throw "Still present: $(($left | ForEach-Object name) -join ', ')" }
[void](Write-L08Evidence 'legacy-removed' ([ordered]@{ minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1) }))
Write-Host ("Bounded resources removed in {0:N0} minutes." -f ((Get-Date) - $started).TotalMinutes)
