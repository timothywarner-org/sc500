<#
.SYNOPSIS
Starts or deallocates only the two tagged SC-500 Lesson 1 VMs.
.DESCRIPTION
Deallocate preserves both VMs, disks, networking, identities, and evidence while stopping compute charges.
Start is an explicit rehearsal/recording action and incurs compute charges.
.EXAMPLE
./scripts/Set-Sc500PowerState.ps1 -State Deallocate
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Start','Deallocate')][string]$State='Deallocate')
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
$null = Assert-Sc500Context
foreach ($fixture in $script:Sc500Config.virtualMachines) {
    $null = Assert-Sc500OwnedGroup -Name $fixture.group
    if ($PSCmdlet.ShouldProcess($fixture.name,$State)) {
        $null = Invoke-Sc500Az -Arguments @('vm',$State.ToLowerInvariant(),'--subscription',$script:Sc500Config.subscriptionId,'--resource-group',$fixture.group,'--name',$fixture.name)
        Write-Host "$($fixture.name): $State completed."
    }
}
