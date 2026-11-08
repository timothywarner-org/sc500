<#
.SYNOPSIS
    Returns the Lesson 13 lab to its idle baseline: deallocates both collectors and deletes the
    temporary NAT gateway and its public IP.
.DESCRIPTION
    The workspace, tables, data collection rules, disks, and collected data are kept, because Lesson 14
    builds on them. Only resources tagged lifecycle=rehearsal-only and managedBy=sc500-l13-iac are
    deleted, and the script reads the result back.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Stop-L13Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L13.Common.ps1')
$cfg = $script:L13Config
[void](Assert-L13Context)
$rg = $cfg.resourceGroup
$n = $cfg.names
foreach ($vm in @($n.forwarderVm, $n.collectorVm)) {
    if ((Get-L13PowerState -Vm $vm) -ne 'deallocated') {
        [void](Invoke-L13Az -Raw @('vm', 'deallocate', '--resource-group', $rg, '--name', $vm))
        Write-Host "Deallocated $vm."
    }
}
$subnet = Invoke-L13Az @('network', 'vnet', 'subnet', 'show', '--resource-group', $rg, '--vnet-name', $n.vnet, '--name', $n.subnet)
if (Get-L13Value $subnet 'natGateway.id') {
    [void](Invoke-L13Az @('network', 'vnet', 'subnet', 'update', '--resource-group', $rg, '--vnet-name', $n.vnet, '--name', $n.subnet, '--remove', 'natGateway'))
    Write-Host "Detached the NAT gateway from $($n.subnet)."
}
foreach ($t in @(@{ name = $n.nat; cmd = @('network', 'nat', 'gateway') }, @{ name = $n.natIp; cmd = @('network', 'public-ip') })) {
    $item = @(Invoke-L13Az ($t.cmd + @('list', '--resource-group', $rg)) | Where-Object name -EQ $t.name)
    if ($item.Count -eq 0) { continue }
    if ($item[0].tags.managedBy -ne $cfg.managedBy -or $item[0].tags.lifecycle -ne 'rehearsal-only') { throw "$($t.name) is not owned by this lab. Refusing to delete it." }
    [void](Invoke-L13Az -Raw ($t.cmd + @('delete', '--resource-group', $rg, '--name', $t.name)))
    Write-Host "Deleted $($t.name)."
}
$state = [ordered]@{
    stoppedUtc = [DateTime]::UtcNow.ToString('o')
    forwarder = (Get-L13PowerState -Vm $n.forwarderVm); collector = (Get-L13PowerState -Vm $n.collectorVm)
    natRemaining = @(Invoke-L13Az @('network', 'nat', 'gateway', 'list', '--resource-group', $rg) | Where-Object name -EQ $n.nat).Count
    publicIpRemaining = @(Invoke-L13Az @('network', 'public-ip', 'list', '--resource-group', $rg) | Where-Object name -EQ $n.natIp).Count
}
[void](Write-L13Evidence 'stop' $state)
if ($state.forwarder -ne 'deallocated' -or $state.collector -ne 'deallocated' -or $state.natRemaining -or $state.publicIpRemaining) {
    throw 'The lab did not reach its idle baseline. Read the evidence file.'
}
Write-Host 'Idle baseline: both VMs deallocated, no NAT gateway, no public IP. Disks and the workspace remain.'
