<#
.SYNOPSIS
    Starts the Lesson 13 collectors for a session: recreates the temporary NAT gateway, attaches it
    to the collectors' subnet, and starts both VMs.
.DESCRIPTION
    The subnet has no default outbound access and the VMs have no public IP, so the Azure Monitor
    Agent can't reach Azure Monitor until the NAT gateway exists. The NAT gateway and its public IP
    are tagged lifecycle=rehearsal-only; Stop-L13Lab.ps1 removes them. Allow a few minutes after the
    VMs start before the agents upload.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Start-L13Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L13.Common.ps1')
$cfg = $script:L13Config
[void](Assert-L13Context)
$rg = $cfg.resourceGroup
$n = $cfg.names
$nat = @(Invoke-L13Az @('network', 'nat', 'gateway', 'list', '--resource-group', $rg) | Where-Object name -EQ $n.nat)
if ($nat.Count -eq 1) {
    if ($nat[0].tags.managedBy -ne $cfg.managedBy -or $nat[0].tags.lifecycle -ne 'rehearsal-only') { throw 'The existing NAT gateway is not owned by this lab.' }
    $natId = $nat[0].id
}
else {
    # The CAF tag set from config.json; egress.bicep overrides lifecycle with rehearsal-only.
    $tags = $cfg.tags
    $p = @{ location = @{ value = $cfg.location }; names = @{ value = $n }; tags = @{ value = $tags } }
    $f = Join-Path $script:L13State 'egress.parameters.json'
    [void][IO.Directory]::CreateDirectory($script:L13State)
    @{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $p } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $f -Encoding utf8
    $d = Invoke-L13Az @('deployment', 'group', 'create', '--resource-group', $rg, '--name', 'sc500-lesson13-egress',
        '--template-file', (Join-Path $script:L13Infra 'egress.bicep'), '--parameters', "@$f")
    $natId = $d.properties.outputs.natId.value
    Write-Host "Created $($n.nat)."
}
$subnet = Invoke-L13Az @('network', 'vnet', 'subnet', 'show', '--resource-group', $rg, '--vnet-name', $n.vnet, '--name', $n.subnet)
if (-not (Get-L13Value $subnet 'natGateway.id') -or $subnet.natGateway.id -ne $natId) {
    [void](Invoke-L13Az @('network', 'vnet', 'subnet', 'update', '--resource-group', $rg, '--vnet-name', $n.vnet, '--name', $n.subnet, '--nat-gateway', $natId))
    Write-Host "Attached $($n.nat) to $($n.subnet)."
}
foreach ($vm in @($n.forwarderVm, $n.collectorVm)) {
    if ((Get-L13PowerState -Vm $vm) -ne 'running') {
        [void](Invoke-L13Az -Raw @('vm', 'start', '--resource-group', $rg, '--name', $vm))
        Write-Host "Started $vm."
    }
    else { Write-Host "$vm is already running." }
}
# A running VM did not imply a running collector after deallocation in the September 28 rehearsal.
$wecStart = Invoke-L13Guest -Vm $n.collectorVm -Name 'Start-L13Wec.ps1' -Values @{ SUBSCRIPTION = $n.wefSubscription }
[void](Write-L13Evidence 'start-wec' @{ guest = $wecStart })
if ($wecStart -notmatch 'L13_WEC_RUNNING') { throw 'Windows Event Collector did not confirm startup. See the start-wec receipt.' }
[void](Write-L13Evidence 'start' ([ordered]@{ startedUtc = [DateTime]::UtcNow.ToString('o'); natId = $natId;
    forwarder = (Get-L13PowerState -Vm $n.forwarderVm); collector = (Get-L13PowerState -Vm $n.collectorVm) }))
Write-Host 'Collectors running with temporary egress. Run Stop-L13Lab.ps1 when the session ends.'
