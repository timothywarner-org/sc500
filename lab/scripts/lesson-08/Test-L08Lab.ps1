<#
.SYNOPSIS
    Read-only readiness check for the Lesson 8 lab at CTSO-L08-BASELINE.

.DESCRIPTION
    PASS means the check matches the baseline the demos start from. WARN means something costs
    money or needs attention before the demo but doesn't break the baseline (a running VM, the
    legacy VM or its JIT policy still present, the Arc machine not connected yet). FAIL means a
    demo would start from the wrong state; run Reset-L08Lab.ps1 (or Deploy-L08Lab.ps1 -Deploy)
    and check again. Changes nothing.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Test-L08Lab.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L08.Common.ps1')
[void](Assert-L08Context)
$cfg = $script:L08Config
$rg = $cfg.resourceGroup
$n = $cfg.names
$sub = $cfg.subscriptionId
$checks = [Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, $Expected, $Actual, [switch]$WarnOnly) {
    $ok = "$Expected" -eq "$Actual"
    $checks.Add([pscustomobject]@{ Result = if ($ok) { 'PASS' } elseif ($WarnOnly) { 'WARN' } else { 'FAIL' }; Check = $Name; Expected = "$Expected"; Actual = "$Actual" })
}

# Subscription prerequisites (read only; the lab never changes them).
Add-Check 'EncryptionAtHost feature' 'Registered' (Invoke-L08Az @('feature', 'show', '--namespace', 'Microsoft.Compute', '--name', 'EncryptionAtHost')).properties.state
$plan = Invoke-L08Arm -Path "/subscriptions/$sub/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
Add-Check 'Defender for Servers plan (subscription)' 'Standard P2' "$($plan.properties.pricingTier) $(Get-L08Value $plan 'properties.subPlan')"
$agentless = @(Get-L08Value $plan 'properties.extensions' | Where-Object name -eq 'AgentlessVmScanning')
Add-Check 'Agentless scanning for machines' 'True' $(if ($agentless.Count) { $agentless[0].isEnabled } else { 'missing' })
$va = Invoke-L08Arm -Path "/subscriptions/$sub/providers/Microsoft.Security/serverVulnerabilityAssessmentsSettings/AzureServersSetting?api-version=2023-05-01"
Add-Check 'Vulnerability assessment provider' 'MdeTvm' (Get-L08Value $va 'properties.selectedProvider')

$group = Invoke-L08Az @('group', 'show', '--name', $rg)
Add-Check 'Resource group tag managedby' $cfg.managedBy (Get-L08Value $group 'tags.managedby')

# The deployment standard's read back (docs/CONTOSO-AZURE-DEPLOYMENT.md, step 5): every resource
# carries the CAF tag set, the budget exists, and each VM has its shutdown schedule.
# The ARM list, not az resource list: on November 1, 2026, Azure CLI 2.85.0's az resource list returned [] for this
# group while ARM and Resource Graph both listed 21 resources, which would have made this check pass on nothing.
$all = @((Invoke-L08Arm -Path "/subscriptions/$sub/resourceGroups/$rg/resources?api-version=2021-04-01").value)
Add-Check 'Resources listed in the group (an empty list proves nothing)' 'more than 0' $(if ($all.Count) { 'more than 0' } else { '0' })
$untagged = @($all | Where-Object { $_.type -notlike 'Microsoft.Security/*' -and $_.type -notlike 'Microsoft.Compute/virtualMachines/extensions' } | Where-Object {
        $t = Get-L08Value $_ 'tags'; $null -eq $t -or @($cfg.tags.PSObject.Properties.Name + 'workload', 'env' | Where-Object { $null -eq $t.PSObject.Properties[$_] }).Count })
Add-Check "Resources missing a CAF tag (of $($all.Count))" 'none' $(if ($untagged.Count) { ($untagged | ForEach-Object name) -join ', ' } else { 'none' })
$budget = Invoke-L08Az -AllowFailure @('consumption', 'budget', 'show', '--budget-name', $n.budget, '--resource-group', $rg)
Add-Check "Budget $($n.budget)" "$($cfg.budget.monthlyAmountUsd)" $(if ($budget.ExitCode -eq 0) { [int]($budget.Stdout | ConvertFrom-Json).amount } else { 'missing' })
foreach ($vmName in @($n.appVm, $n.onpremVm)) {
    $s = Invoke-L08Arm -Path "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.DevTestLab/schedules/shutdown-computevm-$vmName`?api-version=2018-09-15" -AllowNotFound
    Add-Check "Shutdown schedule for $vmName" 'present' $(if ($s) { 'present' } else { 'missing' })
    # Disabled is the pre-demo soak (Deploy-L08Lab.ps1 -Soak): a warning, because it costs money.
    if ($s) { Add-Check "Shutdown schedule for $vmName status" 'Enabled' $s.properties.status -WarnOnly }
}

# Network and Bastion.
$vnet = Invoke-L08Az @('network', 'vnet', 'show', '--resource-group', $rg, '--name', $n.vnet)
$servers = @($vnet.subnets | Where-Object name -eq $n.serversSubnet)[0]
Add-Check "$($n.serversSubnet) NSG" $n.serversNsg ((Get-L08Value $servers 'networkSecurityGroup.id') -split '/')[-1]
$nsg = Invoke-L08Az @('network', 'nsg', 'show', '--resource-group', $rg, '--name', $n.serversNsg)
Add-Check "$($n.serversNsg) custom rules" 'allow-ssh-from-vnet' ((@($nsg.securityRules | Sort-Object priority | ForEach-Object name)) -join ' ')
$bastion = Invoke-L08Az @('resource', 'show', '--resource-group', $rg, '--resource-type', 'Microsoft.Network/bastionHosts', '--name', $n.bastion)
Add-Check 'Bastion SKU and state' 'Developer Succeeded' "$($bastion.sku.name) $($bastion.properties.provisioningState)"

# The ServiceHub app server: the modern one.
$app = Invoke-L08Az @('vm', 'show', '--resource-group', $rg, '--name', $n.appVm, '--show-details')
Add-Check "$($n.appVm) security type" 'TrustedLaunch' (Get-L08Value $app 'securityProfile.securityType')
Add-Check "$($n.appVm) Secure Boot and vTPM" 'True True' "$(Get-L08Value $app 'securityProfile.uefiSettings.secureBootEnabled') $(Get-L08Value $app 'securityProfile.uefiSettings.vTpmEnabled')"
Add-Check "$($n.appVm) encryption at host" 'True' (Get-L08Value $app 'securityProfile.encryptionAtHost')
Add-Check "$($n.appVm) public IP" '' "$(Get-L08Value $app 'publicIps')"
Add-Check "$($n.appVm) identity" 'SystemAssigned' (Get-L08Value $app 'identity.type')
Add-Check "$($n.appVm) power state" 'VM deallocated' $app.powerState -WarnOnly
$ext = @(Invoke-L08Az @('vm', 'extension', 'list', '--resource-group', $rg, '--vm-name', $n.appVm))
foreach ($e in 'GuestAttestation', 'AzurePolicyforLinux', 'MDE.Linux') {
    $x = @($ext | Where-Object name -eq $e)
    Add-Check "$($n.appVm) extension $e" 'Succeeded' $(if ($x.Count) { $x[0].provisioningState } else { 'missing' })
}

# The datacenter server: the Azure VM behind the Arc machine.
$onprem = Invoke-L08Az @('vm', 'show', '--resource-group', $rg, '--name', $n.onpremVm, '--show-details')
Add-Check "$($n.onpremVm) public IP" '' "$(Get-L08Value $onprem 'publicIps')"
Add-Check "$($n.onpremVm) Azure VM extensions (must be none)" 0 @(Invoke-L08Az @('vm', 'extension', 'list', '--resource-group', $rg, '--vm-name', $n.onpremVm)).Count
$onpremPlan = Invoke-L08Arm -Path "$(Get-L08VmId $n.onpremVm)/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
Add-Check "$($n.onpremVm) Defender for Servers (off for the VM resource)" 'Free' $onpremPlan.properties.pricingTier
Add-Check "$($n.onpremVm) power state" 'VM deallocated' $onprem.powerState -WarnOnly
$arc = Invoke-L08Arm -Path "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.HybridCompute/machines/$($n.arcMachine)?api-version=2024-07-10" -AllowNotFound
Add-Check "Arc machine $($n.arcMachine) (your device-code step)" 'present' $(if ($arc) { 'present' } else { 'not connected yet' }) -WarnOnly

# Policy assignments.
foreach ($a in @(@{ name = $n.baselineAssignment; def = $cfg.policyDefinitions.linuxBaseline }, @{ name = $n.encryptionAtHostAssignment; def = $cfg.policyDefinitions.encryptionAtHost })) {
    $pa = Invoke-L08Az -AllowFailure @('policy', 'assignment', 'show', '--name', $a.name, '--scope', $group.id)
    Add-Check "Policy assignment $($a.name)" $a.def $(if ($pa.ExitCode -eq 0) { (($pa.Stdout | ConvertFrom-Json).policyDefinitionId -split '/')[-1] } else { 'missing' })
}

# Bounded part and JIT: absent at baseline.
$legacy = Invoke-L08Az -AllowFailure @('vm', 'show', '--resource-group', $rg, '--name', $n.legacyVm)
Add-Check "$($n.legacyVm) (bounded, about 0.016 USD an hour)" 'absent' $(if ($legacy.ExitCode -eq 0) { 'present' } else { 'absent' }) -WarnOnly
$jit = Invoke-L08Arm -Path ((Get-L08JitPath) + '?api-version=2020-01-01') -AllowNotFound
Add-Check 'Lesson JIT policy' 'absent' $(if ($jit) { 'present' } else { 'absent' }) -WarnOnly

# Your Bastion key file: present, never read. It lives under the user profile, outside AppData.
Add-Check 'Bastion key file (SC500-keys under the user profile)' 'True' (Test-Path -LiteralPath (Get-L08AdminKeyPath))

[void](Write-L08Evidence 'readiness' $checks)
$fails = @($checks | Where-Object Result -eq 'FAIL').Count
$warns = @($checks | Where-Object Result -eq 'WARN').Count
if ($fails) { "NOT READY: $fails check(s) failed. Reset-L08Lab.ps1 removes the bounded part; Deploy-L08Lab.ps1 -Deploy restores the retained part." }
else { "BASELINE CHECK PASSED: $($cfg.baseline) ($warns warning(s)). This doesn't prove Defender's findings; run the demos for that." }
$checks | Format-Table -AutoSize | Out-String -Width 220
if ($fails) { exit 1 }
