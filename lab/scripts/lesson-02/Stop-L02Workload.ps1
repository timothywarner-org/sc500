<#
.SYNOPSIS
Stops Lesson 2 container compute while retaining the group and both identities.
.DESCRIPTION
Only the tagged Lesson 2 group is eligible. Container state is ephemeral; the
probe controller saves logs before stopping. This command never deletes resources.
.EXAMPLE
.\scripts\lesson-02\Stop-L02Workload.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param()
. (Join-Path $PSScriptRoot 'L02.Cloud.Common.ps1')
Assert-L02Context
if (-not (Assert-L02OwnedGroup -Name $script:L02Config.identityGroup -AllowAbsent)) { Write-Host 'Lesson 2 has no deployed container group.'; return }
$container = Get-L02Container
if (-not $container) { Write-Host 'Lesson 2 has no deployed container.'; return }
if ($PSCmdlet.ShouldProcess($container.id,'Stop container compute and retain resources')) {
    [void](Invoke-L02Az @('container','stop','--name',$script:L02Config.containerName,'--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId))
    $state = Invoke-L02Az @('container','show','--name',$script:L02Config.containerName,'--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId)
    Write-L02Evidence -Name 'stopped-container' -Value $state
    $groupState = $state.instanceView.state
    if ($groupState -notin @('Stopped','Succeeded','Failed')) { throw "Container compute did not reach a non-running state: $groupState" }
    Write-Host "Lesson 2 compute state: $groupState. Resource group and identities retained."
}
