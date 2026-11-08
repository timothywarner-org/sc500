<#
.SYNOPSIS
    Opens or closes the Lesson 9 Defender window: Defender for Containers and Defender for App
    Service on the subscription.

.DESCRIPTION
    Lesson 9 shows the Defender sensor on the AKS cluster, registry image findings, Kubernetes
    posture, and Defender for App Service on the web origin. Those need two plans on the
    subscription: Containers (with the sensor, agentless discovery for Kubernetes and registry
    vulnerability assessment) and AppServices. Image findings arrived about 16 minutes after
    import in the September build, but Microsoft documents a few hours, so Open goes at least
    24 hours before the take.
    https://learn.microsoft.com/azure/defender-for-cloud/defender-for-containers-enable-plan

      Status  Reads both plans, their trial time and the Containers extensions. Changes nothing.
              (Default.)
      Open    Saves the current state as private evidence, sets Containers to Standard with
              ContainerSensor, AgentlessDiscoveryForKubernetes and
              ContainerRegistriesVulnerabilityAssessments on, sets AppServices to Standard, and
              reads both back. A mismatch stops the script.
      Close   Saves the current state, then sets both plans to Free. Run it after the lesson ships.

    Only the Containers and AppServices plans are written. Every other plan is left as it is.
    Containers extensions this lesson doesn't need (AgentlessVmScanning,
    ContainerIntegrityContribution) keep the setting they had.

.PARAMETER State
    Status, Open or Close.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Set-L09DefenderWindow.ps1 -State Open

.NOTES
    Cost at retail: Defender for Containers about 7 USD per vCore a month (the one 4-vCPU AKS
    node, only while it runs), and Defender for App Service about 15 USD per instance a month (the
    B1 origin, only while the bounded edge exists). The trial state is printed on every run.
#>
[CmdletBinding()]
param([ValidateSet('Status', 'Open', 'Close')][string]$State = 'Status')
. (Join-Path $PSScriptRoot 'L09.Common.ps1')

[void](Assert-L09Context)
$sub = "/subscriptions/$($script:L09Config.subscriptionId)"
$containersPath = "$sub/providers/Microsoft.Security/pricings/Containers?api-version=2024-01-01"
$appServicesPath = "$sub/providers/Microsoft.Security/pricings/AppServices?api-version=2024-01-01"
$needed = @('ContainerSensor', 'AgentlessDiscoveryForKubernetes', 'ContainerRegistriesVulnerabilityAssessments')

function Get-Extension($Plan, [string]$Name) {
    # A Free plan may have no extensions list, and StrictMode won't read .name off a null.
    $hit = @(@(Get-L09Value $Plan 'properties.extensions') | Where-Object { $null -ne $_ -and $_.name -eq $Name })
    if ($hit.Count) { return $hit[0] }
    return $null
}

function Get-WindowState {
    # One object that says, in words, what the two plans are doing on this subscription.
    $c = Invoke-L09Rest -Path $containersPath
    $a = Invoke-L09Rest -Path $appServicesPath
    $ext = [ordered]@{}
    foreach ($e in @(@(Get-L09Value $c 'properties.extensions') | Where-Object { $null -ne $_ })) { $ext[$e.name] = "$($e.isEnabled)" }
    [pscustomobject]@{
        ContainersTier           = "$(Get-L09Value $c 'properties.pricingTier')"
        ContainersTrialRemaining = "$(Get-L09Value $c 'properties.freeTrialRemainingTime')"
        ContainersEnabledSince   = "$(Get-L09Value $c 'properties.enablementTime')"
        ContainersExtensions     = [pscustomobject]$ext
        AppServicesTier          = "$(Get-L09Value $a 'properties.pricingTier')"
        AppServicesTrialRemaining = "$(Get-L09Value $a 'properties.freeTrialRemainingTime')"
        AppServicesEnabledSince  = "$(Get-L09Value $a 'properties.enablementTime')"
        Raw                      = @{ Containers = $c }
    }
}

function Show-State($S) {
    $S | Select-Object ContainersTier, ContainersTrialRemaining, ContainersEnabledSince, AppServicesTier, AppServicesTrialRemaining, AppServicesEnabledSince | Format-List | Out-Host
    Write-Host 'Containers extensions:'
    $S.ContainersExtensions | Format-List | Out-Host
}

$before = Get-WindowState
Show-State $before
if ($State -eq 'Status') { return }
[void](Write-L09Evidence "defender-window-before-$($State.ToLower())" ($before | Select-Object -ExcludeProperty Raw))

if ($State -eq 'Open') {
    # Keep every listed extension, turn on the three this lesson needs, and carry any additional
    # properties (the sensor's provisioning settings) over unchanged.
    $extensions = [Collections.Generic.List[object]]::new()
    foreach ($e in @(@(Get-L09Value $before.Raw.Containers 'properties.extensions') | Where-Object { $null -ne $_ })) {
        $x = [ordered]@{ name = $e.name; isEnabled = $(if ($needed -contains $e.name) { 'True' } else { "$($e.isEnabled)" }) }
        $props = Get-L09Value $e 'additionalExtensionProperties'
        if ($null -ne $props -and @($props.PSObject.Properties).Count) { $x.additionalExtensionProperties = $props }
        $extensions.Add($x)
    }
    foreach ($n in $needed) { if (-not (@($extensions | Where-Object { $_.name -eq $n }).Count)) { $extensions.Add([ordered]@{ name = $n; isEnabled = 'True' }) } }
    [void](Invoke-L09Rest -Method put -Path $containersPath -Body @{ properties = @{ pricingTier = 'Standard'; extensions = @($extensions) } })
    [void](Invoke-L09Rest -Method put -Path $appServicesPath -Body @{ properties = @{ pricingTier = 'Standard' } })
}
else {
    [void](Invoke-L09Rest -Method put -Path $containersPath -Body @{ properties = @{ pricingTier = 'Free' } })
    [void](Invoke-L09Rest -Method put -Path $appServicesPath -Body @{ properties = @{ pricingTier = 'Free' } })
}

# Read back: a configured plan isn't a working plan, but a plan that didn't take is certainly broken.
$after = Get-WindowState
[void](Write-L09Evidence "defender-window-after-$($State.ToLower())" ($after | Select-Object -ExcludeProperty Raw))
Show-State $after
$ok = if ($State -eq 'Open') {
    $extOk = @($needed | Where-Object { "$(Get-L09Value $after.ContainersExtensions $_)" -ne 'True' }).Count -eq 0
    $after.ContainersTier -eq 'Standard' -and $extOk -and $after.AppServicesTier -eq 'Standard'
}
else { $after.ContainersTier -eq 'Free' -and $after.AppServicesTier -eq 'Free' }
if (-not $ok) { throw "Defender window $State did not read back as expected. See the evidence files." }
Write-Host "Defender window $State`: PASS, read back at $((Get-Date).ToString('yyyy-MM-dd HH:mm zzz'))."
