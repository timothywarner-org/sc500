<#
.SYNOPSIS
    Opens or closes the Lesson 12 Defender window: Defender CSPM and Defender for Storage on the subscription.
.DESCRIPTION
    WHY: Lesson 12 ranks findings by risk level, assigns one to an owner, and overrides Defender for Storage
    on one account. Risk levels and governance need the Defender CSPM plan, and the override needs the
    subscription's Defender for Storage plan to override. Defender needs time after a plan turns on (up to
    24 hours for Defender for Storage at subscription scope, and assessment cycles for new resources), so the
    project rule is to open the window at least 24 hours before the demo.

      Status  Reads both plans: tier, subplan, components, and free-trial time left. Changes nothing. (Default.)
      Open    Saves the current plan payloads as private evidence, then sets CloudPosture to Standard and
              StorageAccounts to Standard (DefenderForStorageV2) with on-upload malware scanning capped per
              account (config.json defenderWindow) and sensitive data threat detection on. Reads both back;
              a mismatch stops the script.
      Close   Saves the payloads, then sets both plans to Free and reads them back. Run it after the last
              lesson that needs them and before the trials end. It doesn't touch the AI services plan
              (Lesson 11) or any other plan.

    Cost (checked 2026-11-05 on Microsoft Learn, Check the status of your free trial and the Defender for
    Storage FAQ): Azure gives a 30-day trial the first time each plan is activated on a subscription. On
    the lab subscription both plans read Free with 30 days of trial unused, so the first Open starts both
    trials. Malware scanning isn't in the trial and bills per GB scanned from day one; a demo run scans a few KB.
    After the trial, Defender CSPM bills per billable resource and Defender for Storage per storage account.

    Grounding:
      https://learn.microsoft.com/azure/defender-for-cloud/free-trial
      https://learn.microsoft.com/azure/defender-for-cloud/faq-defender-for-storage
      https://learn.microsoft.com/azure/defender-for-cloud/tutorial-enable-cspm-plan

    With -WhatIf, the script prints the payloads it would send and changes nothing.
.PARAMETER State
    Status, Open or Close.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Set-L12DefenderWindow.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Set-L12DefenderWindow.ps1 -State Open
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Status', 'Open', 'Close')][string]$State = 'Status')
. (Join-Path $PSScriptRoot 'L12.Common.ps1')
$cfg = $script:L12Config
[void](Assert-L12Context)
$sub = "/subscriptions/$($cfg.subscriptionId)"
$api = 'api-version=2024-01-01'
$planNames = @('CloudPosture', 'StorageAccounts')

function Get-L12Plan([string]$Name) {
    $p = Invoke-L12Rest -Path "$sub/providers/Microsoft.Security/pricings/$Name`?$api"
    $ext = @(@(Get-L12Value $p 'properties.extensions') | Where-Object { $_ })
    [pscustomobject]@{
        plan      = $Name
        tier      = Get-L12Value $p 'properties.pricingTier'
        subPlan   = Get-L12Value $p 'properties.subPlan'
        trialLeft = Get-L12Value $p 'properties.freeTrialRemainingTime'
        enabled   = Get-L12Value $p 'properties.enablementTime'
        on        = @($ext | Where-Object { "$($_.isEnabled)" -eq 'True' } | ForEach-Object name)
        off       = @($ext | Where-Object { "$($_.isEnabled)" -ne 'True' } | ForEach-Object name)
        raw       = $p
    }
}

function Show-L12Plans($plans) {
    foreach ($p in $plans) {
        Write-Host ('  {0,-16} {1,-9} subPlan={2}  trial left={3}  enabled={4}' -f $p.plan, $p.tier, $(if ($p.subPlan) { $p.subPlan } else { '-' }), $p.trialLeft, $(if ($p.enabled) { $p.enabled } else { '-' }))
        if ($p.on) { Write-Host ('      components on:  {0}' -f ($p.on -join ', ')) }
        if ($p.off) { Write-Host ('      components off: {0}' -f ($p.off -join ', ')) }
    }
}

function Get-L12PlanBody([string]$Name, [ValidateSet('Open', 'Close')][string]$Want) {
    if ($Want -eq 'Close') { return @{ properties = @{ pricingTier = 'Free' } } }
    if ($Name -eq 'CloudPosture') {
        # The portal's toggle turns Defender CSPM on with its default components; sending only the tier does
        # the same, and the read-back records exactly which components the platform switched on.
        return @{ properties = @{ pricingTier = 'Standard' } }
    }
    $w = $cfg.defenderWindow.plans.StorageAccounts
    return @{ properties = @{
        pricingTier = 'Standard'; subPlan = $w.subPlan
        extensions  = @(
            @{ name = 'OnUploadMalwareScanning'; isEnabled = 'True'; additionalExtensionProperties = @{ CapGBPerMonthPerStorageAccount = "$($w.malwareScanningCapGBPerMonthPerAccount)" } }
            @{ name = 'SensitiveDataDiscovery'; isEnabled = 'True' }
        ) } }
}

$before = @($planNames | ForEach-Object { Get-L12Plan $_ })
Write-Host "BEFORE ($State)"
Show-L12Plans $before
if ($State -eq 'Status') { return }

if (-not $WhatIfPreference) {
    # Keep the exact prior payloads so the change can be compared or reversed by hand.
    [void](Write-L12Evidence "defender-window-before-$($State.ToLower())" @($before | ForEach-Object { $_.raw }))
}
$wantTier = if ($State -eq 'Open') { 'Standard' } else { 'Free' }
foreach ($name in $planNames) {
    $body = Get-L12PlanBody $name $State
    if (-not $PSCmdlet.ShouldProcess("$name on $($cfg.subscriptionId)", "Set $wantTier")) {
        Write-Host "  would PUT $name : $($body | ConvertTo-Json -Depth 10 -Compress)"
        continue
    }
    [void](Invoke-L12Rest -Method put -Path "$sub/providers/Microsoft.Security/pricings/$name`?$api" -Body $body)
}
if ($WhatIfPreference) { return }

$after = @($planNames | ForEach-Object { Get-L12Plan $_ })
Write-Host "`nAFTER"
Show-L12Plans $after
[void](Write-L12Evidence "defender-window-after-$($State.ToLower())" @($after | ForEach-Object { $_.raw }))
$bad = @($after | Where-Object { $_.tier -ne $wantTier })
if ($State -eq 'Open') {
    $st = $after | Where-Object plan -eq 'StorageAccounts'
    if ($st.subPlan -ne $cfg.defenderWindow.plans.StorageAccounts.subPlan -or 'OnUploadMalwareScanning' -notin $st.on) { $bad += $st }
}
if ($bad) { throw "Read-back mismatch: $(($bad | ForEach-Object { "$($_.plan) reads $($_.tier)" }) -join '; '). Check Environment settings before you continue." }
Write-Host ("`nDefender window {0}. {1}" -f $(if ($State -eq 'Open') { 'OPEN' } else { 'CLOSED' }),
    $(if ($State -eq 'Open') { 'Defender needs time: run Test-L12Lab.ps1 tomorrow, and Wait-L12Assessment.ps1 if the stores are not assessed yet.' } else { 'Both plans read Free.' }))
