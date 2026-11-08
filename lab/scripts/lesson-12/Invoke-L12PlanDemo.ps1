<#
.SYNOPSIS
    SC-500 demo 12.2: read Defender for Cloud's workload protection plans, then configure one plan
    for one resource: Defender for Storage on ServiceHub's parts-export store.
.DESCRIPTION
    Modes (each saves a dated evidence file under lab/.azure/lesson-12/evidence/):
      Plans            Every Defender plan on the subscription: on or off, the sub-plan, and which
                       plan components (extensions) are switched on. Read-only; changes no plan.
      StorageRead      The subscription's Defender for Storage settings next to the resource-level
                       settings on each ServiceHub storage account that overrides them.
      StorageOverride  WRITE, bounded to the export store. Turns Defender for Storage on for this one
                       account with on-upload malware scanning capped at a few GB a month and
                       sensitive data threat detection on, overriding the subscription, then reads it
                       back. Defender for Storage bills per storage account per month (prorated) plus
                       scanned GB, so Reset-L12Lab.ps1 puts the store back to excluded afterwards.
      Scan             Needs the container from Deploy-L12Lab.ps1 -Stage and the override above.
                       Uploads a uniquely named fictional export with your Entra identity and waits for the
                       malware scan verdict that Defender for Storage writes to the blob's index tags.
      All              Plans and StorageRead.
.PARAMETER Mode One of the modes above.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PlanDemo.ps1 -Mode Plans
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PlanDemo.ps1 -Mode StorageOverride
#>
[CmdletBinding()]
param([ValidateSet('Plans', 'StorageRead', 'StorageOverride', 'Scan', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L12.Common.ps1')
. (Join-Path $PSScriptRoot 'L12.Checks.ps1')
. (Join-Path $PSScriptRoot 'L12.Verdict.ps1')
$cfg = $script:L12Config
[void](Assert-L12Context)
$lab = Get-L12Outputs
$sub = "/subscriptions/$($cfg.subscriptionId)"
$settingPath = "$($lab.storageId)/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2025-01-01"
$groups = ($cfg.servicehubResourceGroups | ForEach-Object { "'$($_.ToLower())'" }) -join ', '

# API names for plans differ from the portal's labels. Plans marked legacy were folded into newer
# plans and only appear because the API still returns them.
$planLabels = [ordered]@{
    CloudPosture = 'Defender CSPM'; FoundationalCspm = 'Foundational CSPM'; VirtualMachines = 'Servers'; StorageAccounts = 'Storage'
    SqlServers = 'Azure SQL Databases'; SqlServerVirtualMachines = 'SQL servers on machines'; OpenSourceRelationalDatabases = 'Open-source relational databases'
    CosmosDbs = 'Azure Cosmos DB'; AppServices = 'App Service'; KeyVaults = 'Key Vault'; Arm = 'Resource Manager'; Containers = 'Containers'
    Api = 'APIs'; AI = 'AI services'; Discovery = 'Discovery'
    KubernetesService = 'Kubernetes (legacy)'; ContainerRegistry = 'Container registries (legacy)'; Dns = 'DNS (legacy)'
}

function Get-StoreSetting {
    $s = Invoke-L12Rest -AllowNotFound -Path $settingPath
    [ordered]@{
        isEnabled = (Get-L12Value $s 'properties.isEnabled'); overrideSubscription = (Get-L12Value $s 'properties.overrideSubscriptionLevelSettings')
        malwareScanningOnUpload = (Get-L12Value $s 'properties.malwareScanning.onUpload.isEnabled'); capGBPerMonth = (Get-L12Value $s 'properties.malwareScanning.onUpload.capGBPerMonth')
        sensitiveDataDiscovery = (Get-L12Value $s 'properties.sensitiveDataDiscovery.isEnabled')
    }
}

if ($Mode -in 'Plans', 'All') {
    Write-Host '== Defender plans on the subscription'
    $p = Invoke-L12Rest -Path "$sub/providers/Microsoft.Security/pricings?api-version=2024-01-01"
    $rows = @(foreach ($name in $planLabels.Keys) {
        $x = @($p.value) | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if (-not $x) { continue }
        $ext = @(@(Get-L12Value $x 'properties.extensions') | Where-Object { $_ })
        [ordered]@{ plan = $planLabels[$name]; apiName = $name; on = ($x.properties.pricingTier -eq 'Standard'); subPlan = (Get-L12Value $x 'properties.subPlan')
                    componentsOn = @($ext | Where-Object { $_.isEnabled -eq 'True' -or $_.isEnabled -eq $true } | ForEach-Object { $_.name })
                    componentsOff = @($ext | Where-Object { -not ($_.isEnabled -eq 'True' -or $_.isEnabled -eq $true) } | ForEach-Object { $_.name })
                    enabledUtc = (Get-L12Value $x 'properties.enablementTime') }
    })
    foreach ($r in $rows) {
        Write-Host ("  {0,-34} {1,-3} {2}" -f $r.plan, $(if ($r.on) { 'On' } else { 'Off' }), $(if ($r.subPlan) { "($($r.subPlan))" } else { '' }))
        if ($r.componentsOff) { Write-Host ("      components off: {0}" -f ($r.componentsOff -join ', ')) }
    }
    [void](Write-L12Evidence 'plans' ([ordered]@{ observedUtc = [DateTime]::UtcNow.ToString('o'); plans = $rows }))
}

if ($Mode -in 'StorageRead', 'All') {
    Write-Host '== Defender for Storage: subscription setting'
    $ps = Invoke-L12Rest -Path "$sub/providers/Microsoft.Security/pricings/StorageAccounts?api-version=2024-01-01"
    $ext = @(@(Get-L12Value $ps 'properties.extensions') | Where-Object { $_ } | ForEach-Object {
        $cap = @(@(Get-L12Value $_ 'additionalExtensionProperties') | Where-Object { $_ }) | ForEach-Object { Get-L12Value $_ 'CapGBPerMonthPerStorageAccount' }
        [ordered]@{ name = $_.name; isEnabled = $_.isEnabled; capGBPerMonthPerAccount = $cap } })
    Write-Host ("  {0} ({1})" -f $ps.properties.pricingTier, (Get-L12Value $ps 'properties.subPlan'))
    $ext | ForEach-Object { Write-Host ("    {0} = {1}{2}" -f $_.name, $_.isEnabled, $(if ($_.capGBPerMonthPerAccount) { ", cap $($_.capGBPerMonthPerAccount) GB per account per month" } else { '' })) }
    Write-Host '== ServiceHub storage accounts that override the subscription'
    $ov = Invoke-L12Graph -Query @"
securityresources
| where type == 'microsoft.security/defenderforstoragesettings'
| extend rid = tolower(id)
| extend rg = tostring(split(rid, '/')[4]), account = tostring(split(rid, '/')[8])
| where rg in ($groups) and tobool(properties.overrideSubscriptionLevelSettings)
| project account, rg, state = iff(tobool(properties.isEnabled), 'ON', 'EXCLUDED'), malwareOnUpload = iff(tobool(properties.malwareScanning.onUpload.isEnabled), 'on', 'off'),
          capGB = toint(properties.malwareScanning.onUpload.capGBPerMonth), sensitiveData = iff(tobool(properties.sensitiveDataDiscovery.isEnabled), 'on', 'off')
"@
    $ov | ForEach-Object {
        $cap = if ($_.malwareOnUpload -eq 'on') { $(if ($_.capGB -lt 0) { ', no cap' } else { ", cap $($_.capGB) GB a month" }) } else { '' }
        Write-Host ("  {0,-26} {1,-8} malware scanning {2}{3}; sensitive data threat detection {4}" -f $_.account, $_.state, $_.malwareOnUpload, $cap, $_.sensitiveData) }
    if (-not $ov) { Write-Host '  none' }
    # Resource Graph can lag a change by several minutes, so read the export store from ARM too.
    $store = Get-StoreSetting
    Write-Host ("  {0} read from ARM now: enabled={1}; override={2}; malware scanning={3}; cap={4} GB" -f $lab.storage, $store.isEnabled, $store.overrideSubscription, $store.malwareScanningOnUpload, $store.capGBPerMonth)
    [void](Write-L12Evidence 'storage-read' ([ordered]@{ subscriptionPlan = [ordered]@{ tier = $ps.properties.pricingTier; subPlan = (Get-L12Value $ps 'properties.subPlan'); extensions = $ext }; overrides = $ov; exportStore = $store }))
}

if ($Mode -eq 'StorageOverride') {
    Write-Host "== Defender for Storage on $($lab.storage) only"
    $before = Get-StoreSetting
    Write-Host ("  Before: enabled={0}; override={1}; malware on upload={2}" -f $before.isEnabled, $before.overrideSubscription, $before.malwareScanningOnUpload)
    $cap = [int]$cfg.storageOverride.malwareScanningCapGBPerMonth
    $body = @{ properties = @{ isEnabled = $true; overrideSubscriptionLevelSettings = $true
        malwareScanning = @{ onUpload = @{ isEnabled = $true; capGBPerMonth = $cap } }; sensitiveDataDiscovery = @{ isEnabled = $true } } }
    [void](Invoke-L12Rest -Method put -Path $settingPath -Body $body)
    $after = $null
    foreach ($try in 1..6) { $after = Get-StoreSetting; if (Test-L12StorageOverride $after $cap) { break }; Start-Sleep -Seconds 10 }
    Write-Host ("  After:  enabled={0}; override={1}; malware on upload={2}, cap {3} GB a month; sensitive data threat detection={4}" -f $after.isEnabled, $after.overrideSubscription, $after.malwareScanningOnUpload, $after.capGBPerMonth, $after.sensitiveDataDiscovery)
    Write-L12Verdict -Rows @(
        [ordered]@{ Check = 'Defender for Storage on this account'; Expected = 'True'; Observed = "$($after.isEnabled)" }
        [ordered]@{ Check = 'Overrides the subscription setting'; Expected = 'True'; Observed = "$($after.overrideSubscription)" }
        [ordered]@{ Check = 'Malware scanning on upload'; Expected = 'True'; Observed = "$($after.malwareScanningOnUpload)" }
        [ordered]@{ Check = 'Scanning cap, GB a month'; Expected = "$cap"; Observed = "$($after.capGBPerMonth)" }
        [ordered]@{ Check = 'Sensitive data threat detection'; Expected = 'True'; Observed = "$($after.sensitiveDataDiscovery)" }
    )
    [void](Write-L12Evidence 'storage-override' ([ordered]@{ changedUtc = [DateTime]::UtcNow.ToString('o'); storage = $lab.storage; before = $before; after = $after }))
    if (-not (Test-L12StorageOverride $after $cap)) { Write-Warning 'The override, scanning cap or sensitive-data setting did not match the requested configuration.'; exit 1 }
}

if ($Mode -eq 'Scan') {
    $store = Get-StoreSetting
    if ($store.isEnabled -ne $true -or $store.malwareScanningOnUpload -ne $true) { throw 'Malware scanning is off for the export store. Run -Mode StorageOverride first.' }
    $c = Invoke-L12Az -AllowFailure @('storage', 'container-rm', 'show', '--resource-group', $lab.resourceGroup, '--storage-account', $lab.storage, '--name', $lab.container)
    if ($c.ExitCode -ne 0) { throw "No $($lab.container) container. Run Deploy-L12Lab.ps1 -Stage first." }
    $local = Join-Path $script:L12State $cfg.names.exportBlob
    if (-not (Test-Path -LiteralPath $local)) { throw "The local copy of the fictional export is missing. Run Deploy-L12Lab.ps1 -Stage again." }
    $uploadedUtc = [DateTime]::UtcNow
    # A unique blob prevents an older verdict on an overwritten export from proving this upload.
    $scanBlob = 'parts-export-proof-{0}.csv' -f $uploadedUtc.ToString('yyyyMMddTHHmmssfffZ')
    [void](Invoke-L12Az -Raw @('storage', 'blob', 'upload', '--auth-mode', 'login', '--account-name', $lab.storage, '--container-name', $lab.container,
        '--name', $scanBlob, '--file', $local, '--overwrite', 'false'))
    Write-Host "Uploaded $scanBlob at $($uploadedUtc.ToString('HH:mm:ss')) UTC. Waiting up to three minutes for this blob's verdict."
    $tags = $null
    foreach ($try in 1..18) {
        Start-Sleep -Seconds 10
        $t = Invoke-L12Az -AllowFailure @('storage', 'blob', 'tag', 'list', '--auth-mode', 'login', '--account-name', $lab.storage, '--container-name', $lab.container, '--name', $scanBlob)
        if ($t.ExitCode -ne 0) { throw "Reading the blob's index tags was refused: $((($t.Stderr -split "`n")[0]).Trim())" }
        $tags = $t.Stdout | ConvertFrom-Json
        $scanTime = Get-L12Value $tags 'Malware Scanning scan time UTC'
        # Parse as an offset so the comparison stays in UTC; a plain [DateTime] cast converts the
        # tag to local time and the comparison silently fails.
        if ($scanTime -and (ConvertTo-L12UtcTime $scanTime) -ge (ConvertTo-L12UtcTime $uploadedUtc).AddSeconds(-1)) { break }
    }
    $verdict = Get-L12Value $tags 'Malware Scanning scan result'
    Write-Host ("  Malware Scanning scan result: {0}; scan time UTC: {1}" -f $(if ($verdict) { $verdict } else { 'not written yet' }), (Get-L12Value $tags 'Malware Scanning scan time UTC'))
    $passed = Test-L12FreshCleanScan $tags (ConvertTo-L12UtcTime $uploadedUtc)
    Write-L12Verdict -Rows @(
        [ordered]@{ Check = 'Scan result for this upload'; Expected = 'No threats found'; Observed = $(if ($verdict) { "$verdict" } else { 'not written yet' }) }
        [ordered]@{ Check = 'Fresh clean scan of this upload'; Expected = 'yes'; Observed = $(if ($passed) { 'yes' } else { 'no' }) }
    )
    [void](Write-L12Evidence 'storage-scan' ([ordered]@{ uploadedUtc = $uploadedUtc.ToString('o'); blob = "$($lab.container)/$scanBlob"; tags = $tags; freshCleanScan = $passed }))
    if (-not $passed) { Write-Warning 'No fresh clean scan for this upload. Missing, stale and error results do not pass this demo.'; exit 1 }
}
