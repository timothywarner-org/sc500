<#
.SYNOPSIS
    Adds or removes explicit outbound-only NAT for Lesson 6 Linux VM maintenance.
.DESCRIPTION
    Defender installation and cloud protection need outbound connectivity. Keep this route
    for warmup and recording, then remove it after deallocating the VMs. NAT adds no inbound
    listener. This is a lab convenience, not a production egress filtering design.
    Only tagged Lesson 6 resource groups and VM subnets are eligible. Existing NAT is never
    replaced. Each created NAT/public IP is tagged and checked before removal.
.EXAMPLE
    ./Set-L06MaintenanceEgress.ps1 -Lab Private -Enable
.EXAMPLE
    ./Set-L06MaintenanceEgress.ps1 -Lab Private
#>
[CmdletBinding()]
param([ValidateSet('Private','Pls','Dns')][string]$Lab = 'Private', [switch]$Enable)
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$cfg = $script:L06Config
$rg = switch ($Lab) { 'Private' {$cfg.resourceGroup} 'Pls' {$cfg.plsResourceGroup} 'Dns' {$cfg.dnsResourceGroup} }
$group = Invoke-L06Az @('group','show','--name',$rg)
if ($group.tags.managedBy -ne $cfg.managedBy) { throw 'Refusing an unowned resource group.' }
if(-not $Enable){
    # Removing the only egress path from a running guest would strand Defender again.
    $running=@(Invoke-L06Az @('vm','list','-g',$rg,'--show-details') | Where-Object {$_.storageProfile.osDisk.osType -eq 'Linux' -and $_.powerState -ne 'VM deallocated'})
    if($running.Count){throw 'Deallocate the Linux guests before removing maintenance egress.'}
}
$prefix = "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$rg/providers/Microsoft.Network/virtualNetworks/"
$subnets = @(
    foreach ($vm in @(Invoke-L06Az @('vm','list','--resource-group',$rg))) {
        if ($vm.storageProfile.osDisk.osType -ne 'Linux') { continue }
        foreach ($nicRef in $vm.networkProfile.networkInterfaces) {
            $nic = Invoke-L06Az @('network','nic','show','--ids',$nicRef.id)
            foreach ($ip in $nic.ipConfigurations) { $ip.subnet.id }
        }
    }
) | Sort-Object -Unique
if (-not @($subnets).Count) { throw "No Linux VM subnets found in $rg." }
$changes = @()
foreach ($set in ($subnets | Group-Object { ($_ -split '/subnets/')[0] })) {
    if (-not $set.Name.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Subnet outside the lesson resource group.' }
    $vnetName = ($set.Name -split '/')[-1]
    # vnet-{workload}-{env}-{region}-{###}: the second token is the workload (Cloud Adoption Framework naming guidance, https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming).
    $workload = ($vnetName -split '-')[1]
    $natName = Get-L06NatName $workload
    $pipName = "pip-$natName"
    $natId = "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$rg/providers/Microsoft.Network/natGateways/$natName"
    $pipId = "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$rg/providers/Microsoft.Network/publicIPAddresses/$pipName"
    # Preflight the complete VNet group before changing any attachment.
    foreach ($subnetId in $set.Group) {
        $subnet = Invoke-L06Az @('network','vnet','subnet','show','--ids',$subnetId)
        $current = Get-L06Value $subnet 'natGateway.id'
        if ($current -and $current -ne $natId) { throw "Refusing to replace another NAT on $subnetId." }
    }
    foreach ($id in @($natId,$pipId)) {
        # Pin the API version: without it the CLI asks for the provider's newest one, and on October 30, 2026 that was
        # 2026-07-01, which natGateways didn't serve in eastus2 yet (NoRegisteredProviderFound). Both types serve 2024-05-01.
        $found = Invoke-L06Az -AllowFailure @('resource','show','--ids',$id,'--api-version','2024-05-01')
        if ($found.ExitCode -eq 0) {
            $resource = $found.Stdout | ConvertFrom-Json
            if ($resource.tags.managedBy -ne $cfg.managedBy -or $resource.tags.purpose -ne 'lesson06-maintenance-egress') { throw "Unowned resource: $id" }
        } elseif ($found.Stderr -notmatch 'ResourceNotFound|NotFound') { throw $found.Stderr }
    }
    if ($Enable) {
        [void](Invoke-L06Az @('network','public-ip','create','--resource-group',$rg,'--name',$pipName,'--location',$cfg.location,'--sku','Standard','--allocation-method','Static','--tags',"managedBy=$($cfg.managedBy)",'purpose=lesson06-maintenance-egress'))
        [void](Invoke-L06Az @('network','nat','gateway','create','--resource-group',$rg,'--name',$natName,'--location',$cfg.location,'--sku','Standard','--public-ip-addresses',$pipId,'--idle-timeout','4','--tags',"managedBy=$($cfg.managedBy)",'purpose=lesson06-maintenance-egress'))
        foreach ($id in $set.Group) { [void](Invoke-L06Az @('network','vnet','subnet','update','--ids',$id,'--nat-gateway',$natId)) }
    } else {
        # Remove only the attachment created here; defaultOutboundAccess remains false.
        foreach ($id in $set.Group) {
            $subnet = Invoke-L06Az @('network','vnet','subnet','show','--ids',$id)
            if ((Get-L06Value $subnet 'natGateway.id') -eq $natId) {
                [void](Invoke-L06Az @('network','vnet','subnet','update','--ids',$id,'--remove','natGateway'))
            }
        }
        [void](Invoke-L06Az @('network','nat','gateway','delete','--resource-group',$rg,'--name',$natName))
        [void](Invoke-L06Az @('network','public-ip','delete','--resource-group',$rg,'--name',$pipName))
    }
    $changes += [pscustomobject]@{Vnet=$vnetName;Enabled=[bool]$Enable;Nat=$natName;Subnets=$set.Group}
}
[void](Write-L06Evidence 'maintenance-egress' $changes)
$changes | Format-Table Vnet,Enabled,Nat
