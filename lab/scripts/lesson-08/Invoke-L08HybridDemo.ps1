<#
.SYNOPSIS
    Demo 8.3 for SC-500 Lesson 8: bring a non-Azure server under Azure Arc and Defender for
    Servers, then read what Defender does for it: EDR, vulnerability assessment, agentless scanning.

.DESCRIPTION
    Read-only. Connecting the server is your step: -Mode Command prints the exact azcmagent
    command to paste into the Bastion session on the datacenter server (vm-datacenter-prod-001), and he signs in with a device code.
    No script here signs in as anyone or holds a credential.
      Readiness  the datacenter server (vm-datacenter-prod-001)'s own report from its serial log: guest agent off, IMDS blocked,
                 Connected Machine agent installed, Arc endpoints reachable, agent status.
      Command    The azcmagent connect command for you.
      Arc        The Arc machine: status, agent version, OS, and its extensions.
      Coverage   Defender for Servers at each scope: the subscription plan, the Azure VM that plays
                 the on-premises server (off), the ServiceHub app server (vm-servicehub-prod-001), and the Arc machine.
      Scanning   The subscription's EDR, vulnerability assessment, and agentless scanning settings,
                 and the Defender for Endpoint extension on each machine.
      All        Readiness, Arc, Coverage, and Scanning.

.PARAMETER Mode
    One of the modes above.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Invoke-L08HybridDemo.ps1 -Mode Readiness
#>
[CmdletBinding()]
param([ValidateSet('Readiness', 'Command', 'Arc', 'Coverage', 'Scanning', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L08.Common.ps1')
[void](Assert-L08Context)
$cfg = $script:L08Config
$rg = $cfg.resourceGroup
$n = $cfg.names
$sub = $cfg.subscriptionId
$arcPath = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.HybridCompute/machines/$($n.arcMachine)"

if ($Mode -in 'Readiness', 'All') {
    Write-Host "== $($n.onpremVm), from the guest (serial log)"
    $lines = @(Get-L08BootLog -VmName $n.onpremVm -Prefix 'CONTOSO-ARC')
    [void](Write-L08Evidence 'hybrid-readiness' ([pscustomobject]@{ lines = $lines }))
    if ($lines.Count) { $lines | ForEach-Object { $_ -replace '^CONTOSO-ARC ', '' } | Out-Host } else { Write-Host '(nothing yet; preparation takes a few minutes after first boot)' }
}

if ($Mode -eq 'Command') {
    # The same CAF tag set the template gives every resource, so the Arc machine answers to the
    # group's owner, workload and env tags like everything else (the remove script relies on it).
    $tags = (@((Get-L08TagSet -Workload 'datacenter' -Env 'prod').GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value })) -join ','
    Write-Host "In the Azure portal, open $($n.onpremVm) > Connect > Bastion, sign in as $($cfg.adminUsername) with the key file"
    Write-Host "$(Get-L08AdminKeyPath), and run this. It prints a code; enter it at https://microsoft.com/devicelogin as yourself."
    Write-Host ''
    # sudo resets the environment, so pass MSFT_ARC_TEST explicitly (evaluation on an Azure VM only).
    Write-Host ("sudo MSFT_ARC_TEST=true azcmagent connect --resource-group $rg --tenant-id $($cfg.tenantId) --subscription-id $sub " +
        "--location $($cfg.location) --resource-name $($n.arcMachine) --cloud AzureCloud --tags `"$tags`" --use-device-code")
}

if ($Mode -in 'Arc', 'All') {
    Write-Host "== Arc machine $($n.arcMachine)"
    $m = Invoke-L08Arm -Path "$arcPath`?api-version=2024-07-10" -AllowNotFound
    if (-not $m) { Write-Host '(not connected yet; run -Mode Command and connect it from the Bastion session)' }
    else {
        $p = $m.properties
        $row = [pscustomobject]@{
            Status          = Get-L08Value $p 'status'
            AgentVersion    = Get-L08Value $p 'agentVersion'
            OS              = "$(Get-L08Value $p 'osName') $(Get-L08Value $p 'osSku')"
            LastStatusChange = Get-L08Value $p 'lastStatusChange'
            CloudProvider   = Get-L08Value $p 'detectedProperties.cloudprovider'
        }
        $ext = @((Invoke-L08Arm -Path "$arcPath/extensions?api-version=2024-07-10").value | ForEach-Object {
                [pscustomobject]@{ Extension = $_.name; Publisher = $_.properties.publisher; State = $_.properties.provisioningState }
            })
        [void](Write-L08Evidence 'hybrid-arc' ([pscustomobject]@{ machine = $row; extensions = $ext }))
        $row | Format-List | Out-String -Width 160 | Out-Host
        if ($ext.Count) { $ext | Format-Table -AutoSize | Out-String -Width 160 | Out-Host } else { Write-Host '(no extensions yet)' }
    }
}

if ($Mode -in 'Coverage', 'All') {
    Write-Host '== Defender for Servers coverage'
    $scopes = [ordered]@{
        'Subscription'              = "/subscriptions/$sub"
        "$($n.appVm) (Azure VM)"    = Get-L08VmId $n.appVm
        "$($n.onpremVm) (Azure VM)" = Get-L08VmId $n.onpremVm
        "$($n.arcMachine) (Arc)"    = $arcPath
    }
    $rows = foreach ($k in $scopes.Keys) {
        $pr = Invoke-L08Arm -Path "$($scopes[$k])/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01" -AllowNotFound
        [pscustomobject]@{
            Scope     = $k
            Tier      = $(if ($pr) { $pr.properties.pricingTier } else { 'n/a (not connected)' })
            SubPlan   = $(if ($pr) { Get-L08Value $pr 'properties.subPlan' } else { '' })
            Inherited = $(if ($pr) { Get-L08Value $pr 'properties.inherited' } else { '' })
        }
    }
    [void](Write-L08Evidence 'hybrid-coverage' $rows)
    $rows | Format-Table -AutoSize | Out-String -Width 160 | Out-Host
}

if ($Mode -in 'Scanning', 'All') {
    Write-Host '== EDR, vulnerability assessment, and agentless scanning settings (subscription)'
    $plan = Invoke-L08Arm -Path "/subscriptions/$sub/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
    $agentless = @(Get-L08Value $plan 'properties.extensions' | Where-Object name -eq 'AgentlessVmScanning')
    $wdatp = Invoke-L08Arm -Path "/subscriptions/$sub/providers/Microsoft.Security/settings/WDATP?api-version=2022-05-01"
    $va = Invoke-L08Arm -Path "/subscriptions/$sub/providers/Microsoft.Security/serverVulnerabilityAssessmentsSettings/AzureServersSetting?api-version=2023-05-01"
    $settings = [pscustomobject]@{
        'Endpoint protection (WDATP)'        = Get-L08Value $wdatp 'properties.enabled'
        'Vulnerability assessment provider'  = Get-L08Value $va 'properties.selectedProvider'
        'Agentless scanning for machines'    = $(if ($agentless.Count) { $agentless[0].isEnabled } else { 'not listed' })
    }
    $settings | Format-List | Out-String -Width 160 | Out-Host
    Write-Host '== Defender for Endpoint extension on each machine'
    $mde = @()
    $appExt = @(Invoke-L08Az @('vm', 'extension', 'list', '--resource-group', $rg, '--vm-name', $n.appVm) | Where-Object { $_.name -like 'MDE.*' })
    $mde += [pscustomobject]@{ Machine = $n.appVm; Extension = $(if ($appExt.Count) { $appExt[0].name } else { 'none yet' }); State = $(if ($appExt.Count) { $appExt[0].provisioningState } else { '' }) }
    $arcExt = Invoke-L08Arm -Path "$arcPath/extensions?api-version=2024-07-10" -AllowNotFound
    $arcMde = @(if ($arcExt) { @($arcExt.value) | Where-Object { $_.name -like 'MDE.*' } })
    $mde += [pscustomobject]@{ Machine = $n.arcMachine; Extension = $(if ($arcMde.Count) { $arcMde[0].name } elseif ($arcExt) { 'none yet' } else { 'not connected' }); State = $(if ($arcMde.Count) { $arcMde[0].properties.provisioningState } else { '' }) }
    [void](Write-L08Evidence 'hybrid-scanning' ([pscustomobject]@{ settings = $settings; mde = $mde }))
    $mde | Format-Table -AutoSize | Out-String -Width 160 | Out-Host
}
