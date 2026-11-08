<#
.SYNOPSIS
    Your step, after you finish Lesson 14: deletes the Lesson 13 lab.
.DESCRIPTION
    Deletes the subscription Activity log setting, the rg-secops-shared-eastus2 group (workspace,
    collected data, rules, VMs, disks), and the two empty role-demo groups. Lesson 14 builds on this
    workspace, so don't run it before Lesson 14 is finished. Tenant-level connections you made by
    hand (Microsoft Entra diagnostic setting, Microsoft 365 connector, Defender portal workspace
    connection) are listed for him to remove in the portal; this script doesn't touch them.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Remove-L13Lab.ps1
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()
. (Join-Path $PSScriptRoot 'L13.Common.ps1')
$cfg = $script:L13Config
[void](Assert-L13Context)
$sub = "/subscriptions/$($cfg.subscriptionId)"
if ($PSCmdlet.ShouldProcess($cfg.names.activityDiagnosticSetting, 'Delete the subscription Activity log setting')) {
    [void](Invoke-L13Rest -Method delete -AllowNotFound -Path "$sub/providers/Microsoft.Insights/diagnosticSettings/$($cfg.names.activityDiagnosticSetting)?api-version=2021-05-01-preview")
}
if ($PSCmdlet.ShouldProcess($cfg.resourceGroup, 'Delete the resource group and everything in it')) {
    [void](Invoke-L13Az -Raw @('group', 'delete', '--name', $cfg.resourceGroup, '--yes'))
}
foreach ($g in @($cfg.names.analystGroup, $cfg.names.engineerGroup)) {
    $gid = @(Invoke-L13Az -NoSubscription @('ad', 'group', 'list', '--filter', "displayName eq '$g'", '--query', '[].id'))[0]
    if ($gid -and $PSCmdlet.ShouldProcess($g, 'Delete the empty group')) { [void](Invoke-L13Az -NoSubscription -Raw @('ad', 'group', 'delete', '--group', $gid)) }
}
Write-Host 'Removed. In the portals, remove any Microsoft Entra diagnostic setting, Microsoft 365 connector, or Defender portal workspace connection you made for Lesson 13.'
