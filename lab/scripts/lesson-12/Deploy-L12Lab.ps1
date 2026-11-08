<#
.SYNOPSIS
    Deploys the SC-500 Lesson 12 lab: ServiceHub's parts-export store (the posture fixture) and a
    Defender EASM workspace seeded with your own domain.
.DESCRIPTION
    Design goal: keep idle cost at or near zero until you need it. So the lab has two
    states, and this script builds each one:
      -Deploy  Idle baseline. main.bicep creates rg-servicehub-prod-eastus2 with the export store
               stservicehubexports<your-name-suffix> (Shared Key allowed on purpose, public network access on, no
               containers, Defender for Storage excluded at the resource level, your Storage Blob Data
               Owner role on the store) and the archive store stservicehubarchive<your-name-suffix> (the same Shared
               Key fault, public network access disabled), and rg-attacksurface-shared-eastus with the
               EASM workspace easmattacksurface001. Then the EASM discovery group gets its seed and one
               run starts, unless a run is already pending, running, or completed (use -RunDiscovery to
               force one). Names come from config.json (CAF applied to Contoso, 2026-11-05 move).
      -Stage   Prep, the day before the demo: creates the parts-exports container and uploads
               one fictional CSV with your Entra identity (never a key). That makes the store look
               like the real thing. From then on Defender CSPM counts it as a billable resource, so
               Reset-L12Lab.ps1 removes the container after the demo.
    With neither switch it runs an ARM what-if and changes nothing. Nothing here changes a Defender
    plan or a tenant setting.
    Costs: an empty store with Defender for Storage excluded costs effectively nothing. Defender EASM
    gives a customer's first EASM resource a 30-day trial; this tenant's first workspace was the
    September 28 build, so this one may bill from day one, and only Approved domains, hosts and IP
    addresses bill (cents a day for one domain). Remove-L12Lab.ps1 -Easm (your step) deletes it.
    The subscription's Defender plans belong to Set-L12DefenderWindow.ps1, not to this script.
.PARAMETER Deploy Create or update the idle baseline and the EASM discovery.
.PARAMETER Stage Add the container and the fictional export for a recording.
.PARAMETER RunDiscovery Start a new EASM discovery run even if one already ran.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Deploy-L12Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Deploy-L12Lab.ps1 -Deploy
#>
[CmdletBinding()]
param([switch]$Deploy, [switch]$Stage, [switch]$RunDiscovery)
. (Join-Path $PSScriptRoot 'L12.Common.ps1')
$cfg = $script:L12Config
$started = Get-Date
[void](Assert-L12Context)
$me = Invoke-L12Az -NoSubscription @('ad', 'signed-in-user', 'show', '--query', '{id:id,upn:userPrincipalName}')
[void][IO.Directory]::CreateDirectory($script:L12State)

# Defender EASM is its own resource provider; register it once (idempotent, no cost).
$rp = Invoke-L12Az @('provider', 'show', '--namespace', 'Microsoft.Easm', '--query', 'registrationState', '--output', 'tsv') -Raw
if ($rp -ne 'Registered') {
    Write-Host "Registering the Microsoft.Easm resource provider (was $rp)."
    [void](Invoke-L12Az -Raw @('provider', 'register', '--namespace', 'Microsoft.Easm', '--wait'))
}

$params = @{
    location = @{ value = $cfg.location }; easmLocation = @{ value = $cfg.easmLocation }
    resourceGroupName = @{ value = $cfg.resourceGroup }; easmResourceGroupName = @{ value = $cfg.easmResourceGroup }
    names = @{ value = $cfg.names }; operatorObjectId = @{ value = $me.id }; roles = @{ value = $cfg.roles }
    tags = @{ value = $cfg.tags }; baseline = @{ value = $cfg.baseline }
}

# Storage account names are global. Before the first build, make sure each one is free or already ours,
# so a collision fails here with a clear message instead of halfway through a deployment.
foreach ($storeName in @($cfg.names.exportStorage, $cfg.names.archiveStorage)) {
    $mine = Invoke-L12Az -AllowFailure @('storage', 'account', 'show', '--name', $storeName, '--resource-group', $cfg.resourceGroup, '--query', 'id', '--output', 'tsv')
    if ($mine.ExitCode -eq 0 -and $mine.Stdout.Trim()) { Write-Host "  $storeName already exists in $($cfg.resourceGroup)."; continue }
    $free = Invoke-L12Az @('storage', 'account', 'check-name', '--name', $storeName)
    if (-not $free.nameAvailable) { throw "Storage account name $storeName is taken ($($free.reason)). Pick the next instance number in config.json." }
    Write-Host "  $storeName is available."
}
$paramFile = Join-Path $script:L12State 'main.parameters.json'
@{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $params } |
    ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $paramFile -Encoding utf8
$common = @('--name', $cfg.deploymentName, '--location', $cfg.location, '--template-file', (Join-Path $script:L12Infra 'main.bicep'), '--parameters', "@$paramFile")

if (-not $Deploy -and -not $Stage) {
    Write-Host '== ARM what-if (nothing changes)'
    Invoke-L12Az -Raw (@('deployment', 'sub', 'what-if') + $common + @('--result-format', 'ResourceIdOnly', '--no-pretty-print')) | Out-Host
    return
}

if ($Deploy) {
    Write-Host 'Deploying the export store and the EASM workspace.'
    $d = Invoke-L12Az (@('deployment', 'sub', 'create') + $common)
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "Deployment ended $($d.properties.provisioningState)." }
    $lab = $d.properties.outputs.lab.value
    Write-Host "Export store $($lab.storage); archive store $($lab.archiveStorage); EASM workspace $($lab.easmWorkspace) in $($lab.easmLocation)."
    # The first build gave you Storage Blob Data Contributor; the template now grants Owner (tag reads
    # need it). Remove the retired assignment so exactly one data role remains. Idempotent.
    $old = @(Invoke-L12Az @('role', 'assignment', 'list', '--assignee', $me.id, '--scope', $lab.storageId, '--role', $cfg.roles.retiredStorageBlobDataContributor, '--query', '[].id'))
    foreach ($id in $old) { [void](Invoke-L12Az -Raw @('role', 'assignment', 'delete', '--ids', $id)); Write-Host '  Removed the retired Storage Blob Data Contributor assignment.' }

    # ---- EASM discovery group ---------------------------------------------------------------------
    $group = $cfg.names.discoveryGroup
    $existing = Invoke-L12Easm -Path "discoGroups/$group"
    $state = if ($existing.Status -eq 200) { Get-L12Value $existing.Body 'latestRun.state' } else { $null }
    $body = @{
        description = 'ServiceHub external attack surface: your own domain, approved as the SC-500 Lesson 12 discovery seed.'
        seeds = @($cfg.easm.seeds | ForEach-Object { @{ kind = $_.kind; name = $_.name } })
        frequencyMilliseconds = [long]$cfg.easm.frequencyMilliseconds
    }
    $put = Invoke-L12Easm -Method PUT -Path "discoGroups/$group" -Body $body
    if ($put.Status -ge 300) { throw "Creating discovery group $group returned $($put.Status): $($put.Text)" }
    Write-Host "Discovery group $group is in place (HTTP $($put.Status)); latest run state before this call: $(if ($state) { $state } else { 'none' })."
    $run = $null
    if ($RunDiscovery -or -not $state -or $state -eq 'failed') {
        $run = Invoke-L12Easm -Method POST -Path "discoGroups/$group`:run"
        if ($run.Status -ge 300) { throw "Starting a discovery run returned $($run.Status): $($run.Text)" }
        Write-Host "Discovery run requested (HTTP $($run.Status)). It finishes in the background; allow hours, not minutes."
    }
    $after = Invoke-L12Easm -Path "discoGroups/$group"
    $wsCreated = Invoke-L12Rest -Path "$($lab.easmWorkspaceId)?api-version=2023-04-01-preview"
    [void](Write-L12Evidence 'deploy' ([ordered]@{
        deployedUtc = [DateTime]::UtcNow.ToString('o'); minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1); lab = $lab
        fixture = (Get-L12Fixture -Lab $lab); exportBlob = $cfg.names.exportBlob
        easmWorkspaceCreatedUtc = (Get-L12Value $wsCreated 'systemData.createdAt')
        discoveryGroup = [ordered]@{ name = $group; seeds = $body.seeds; runRequested = [bool]$run; latestRun = (Get-L12Value $after.Body 'latestRun') }
    }))
}

if ($Stage) {
    $lab = Get-L12Outputs
    # The container is created through ARM, so it needs no data-plane role and no key.
    [void](Invoke-L12Az @('storage', 'container-rm', 'create', '--resource-group', $lab.resourceGroup, '--storage-account', $lab.storage,
        '--name', $lab.container, '--public-access', 'off'))
    # ---- Fictional export, uploaded with your Entra identity -------------------------------------
    # Customer IDs use the fictional CTSO-CUST-###### format from Lesson 11; every row is invented.
    $csv = @(
        'exportDate,customerId,site,partNumber,description,quantity'
        '2026-11-05,CTSO-CUST-104233,Nashville,C-200,Pump pressure valve 2-inch,4'
        '2026-11-05,CTSO-CUST-118902,Memphis,X-900,Compressor seal kit,1'
        '2026-11-05,CTSO-CUST-120417,Knoxville,C-310,Filter housing,12'
    ) -join "`n"
    $local = Join-Path $script:L12State $cfg.names.exportBlob
    Set-Content -LiteralPath $local -Value $csv -Encoding utf8 -NoNewline
    $uploaded = $false
    foreach ($attempt in 1..10) {
        $u = Invoke-L12Az -AllowFailure -Raw @('storage', 'blob', 'upload', '--auth-mode', 'login', '--account-name', $lab.storage,
            '--container-name', $lab.container, '--name', $cfg.names.exportBlob, '--file', $local, '--overwrite', 'true')
        if ($u.ExitCode -eq 0) { $uploaded = $true; break }
        Write-Host "  upload attempt $attempt refused (role still propagating); waiting 30 seconds"
        Start-Sleep -Seconds 30
    }
    if (-not $uploaded) { throw 'The fictional export could not be uploaded with Entra auth. Check the Storage Blob Data Owner assignment.' }
    Write-Host "Uploaded $($cfg.names.exportBlob) with Entra auth."
    [void](Write-L12Evidence 'stage' ([ordered]@{ stagedUtc = [DateTime]::UtcNow.ToString('o'); storage = $lab.storage; container = $lab.container; exportBlob = $cfg.names.exportBlob; fixture = (Get-L12Fixture -Lab $lab) }))
}
Write-Host ("Done in {0:N1} minutes." -f ((Get-Date) - $started).TotalMinutes)
