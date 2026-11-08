<#
.SYNOPSIS
    Opens or closes the Lesson 8 Defender window: Defender for Servers Plan 2 on the subscription.

.DESCRIPTION
    Lesson 8 shows just-in-time VM access, Defender for Endpoint's automatic onboarding, agentless
    scanning and the vulnerability assessment settings, and all of them need Defender for Servers
    Plan 2 on the subscription. Agentless scanning runs once every 24 hours and only scans a machine
    that's running during its cycle, so Open goes at least 24 hours before the demo, with the VMs
    running (Deploy-L08Lab.ps1 -Soak keeps them up overnight).
    https://learn.microsoft.com/azure/defender-for-cloud/enable-agentless-scanning-vms

      Status  Reads the plan, its extensions, the Defender for Endpoint integration setting (WDATP)
              and the vulnerability assessment provider. Changes nothing. (Default.)
      Open    Saves the current state as private evidence, sets the VirtualMachines plan to
              Standard with sub-plan P2 and agentless scanning on, turns the Defender for Endpoint
              integration on if it's off, names Defender Vulnerability Management (MdeTvm) as the
              vulnerability assessment provider if it isn't, and reads everything back. A mismatch
              stops the script.
      Close   Saves the current state, then sets the plan to Free. Run it after the lesson ships.

    Only the VirtualMachines plan, the WDATP setting and the vulnerability assessment provider are written. Every other plan is left as it
    is. The datacenter VM's own plan override (Free) lives in retained.bicep, not here.

.PARAMETER State
    Status, Open or Close.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-08\Set-L08DefenderWindow.ps1 -State Open

.NOTES
    Cost: about 0.02 USD an hour for each running Azure VM and connected Arc machine in the
    subscription. The lab subscription had Plan 2's 30-day trial unused on November 1, 2026, so the
    first Open starts it. Deallocated VMs and disconnected Arc machines aren't billed.
#>
[CmdletBinding()]
param([ValidateSet('Status', 'Open', 'Close')][string]$State = 'Status')
. (Join-Path $PSScriptRoot 'L08.Common.ps1')

[void](Assert-L08Context)
$sub = "/subscriptions/$($script:L08Config.subscriptionId)"
$planPath = "$sub/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
$wdatpPath = "$sub/providers/Microsoft.Security/settings/WDATP?api-version=2022-05-01"
$vaPath = "$sub/providers/Microsoft.Security/serverVulnerabilityAssessmentsSettings/AzureServersSetting?api-version=2023-05-01"

function Get-WindowState {
    # One object that says, in words, what Defender for Servers is doing on this subscription.
    $plan = Invoke-L08Arm -Path $planPath
    # A Free plan has no extensions list, and StrictMode won't read .name off a null.
    $agentless = @(@(Get-L08Value $plan 'properties.extensions') | Where-Object { $null -ne $_ -and $_.name -eq 'AgentlessVmScanning' })
    $wdatp = Invoke-L08Arm -Path $wdatpPath -AllowNotFound
    $va = Invoke-L08Arm -Path $vaPath -AllowNotFound
    [pscustomobject]@{
        Tier              = "$(Get-L08Value $plan 'properties.pricingTier')"
        SubPlan           = "$(Get-L08Value $plan 'properties.subPlan')"
        AgentlessScanning = if ($agentless.Count) { "$($agentless[0].isEnabled)" } else { 'not listed' }
        TrialRemaining    = "$(Get-L08Value $plan 'properties.freeTrialRemainingTime')"
        EndpointIntegration = "$(Get-L08Value $wdatp 'properties.enabled')"
        VulnerabilityProvider = if ($va) { "$(Get-L08Value $va 'properties.selectedProvider')" } else { 'default (not set)' }
    }
}

$before = Get-WindowState
$before | Format-List | Out-Host
if ($State -eq 'Status') { return }
[void](Write-L08Evidence "defender-window-before-$($State.ToLower())" $before)

if ($State -eq 'Open') {
    $body = @{ properties = @{ pricingTier = 'Standard'; subPlan = 'P2'; extensions = @(@{ name = 'AgentlessVmScanning'; isEnabled = 'True' }) } }
    [void](Invoke-L08Arm -Method put -Path $planPath -Body $body)
    if ($before.EndpointIntegration -ne 'True') {
        # Plan 2 onboards Defender for Endpoint only while this integration is on.
        [void](Invoke-L08Arm -Method put -Path $wdatpPath -Body @{ kind = 'DataExportSettings'; properties = @{ enabled = $true } })
    }
    if ($before.VulnerabilityProvider -ne 'MdeTvm') {
        # Name Microsoft Defender Vulnerability Management as the provider, so the setting the access
        # and hybrid demo reads isn't an unset default. MdeTvm is the API's name for it.
        [void](Invoke-L08Arm -Method put -Path $vaPath -Body @{ kind = 'AzureServersSetting'; properties = @{ selectedProvider = 'MdeTvm' } })
    }
}
else {
    [void](Invoke-L08Arm -Method put -Path $planPath -Body @{ properties = @{ pricingTier = 'Free' } })
}

# Read back: a configured plan isn't a working plan, but a plan that didn't take is certainly broken.
$after = Get-WindowState
[void](Write-L08Evidence "defender-window-after-$($State.ToLower())" $after)
$after | Format-List | Out-Host
$ok = if ($State -eq 'Open') { $after.Tier -eq 'Standard' -and $after.SubPlan -eq 'P2' -and $after.AgentlessScanning -eq 'True' -and $after.EndpointIntegration -eq 'True' -and $after.VulnerabilityProvider -eq 'MdeTvm' }
      else { $after.Tier -eq 'Free' }
if (-not $ok) { throw "Defender window $State did not read back as expected. See the evidence files." }
Write-Host "Defender window $State`: PASS, read back at $((Get-Date).ToString('yyyy-MM-dd HH:mm zzz'))."
