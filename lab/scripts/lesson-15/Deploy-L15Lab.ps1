<#
.SYNOPSIS
    Deploys the SC-500 Lesson 15 cost guardrail: the guarded resource group, a least-privilege custom
    role, and the Security Copilot capacity reaper. It never creates a capacity.
.DESCRIPTION
    Design goal: minimal or no cost, and deploy the paid piece only when he's ready
    to record. Security Copilot's provisioned capacity is the paid piece, billed every hour it exists,
    so this lab deploys only what keeps that bill bounded:
      (no switch)  ARM what-if. Changes nothing.
      -Deploy      main.bicep creates rg-secopscopilot-shared-eastus2, the custom role "Contoso Security
                   Copilot capacity reaper" (list the group's resources, read and delete Microsoft.SecurityCopilot/capacities,
                   assignable only in that group), and the reaper logic app with that role.
      -TestReaper  Proves the reaper's logic live at no cost: deploys a second copy in its own group that
                   targets user-assigned managed identities (free), creates one expired and one unexpired
                   identity, runs the reaper, checks that only the expired one is gone, then removes
                   the test group and its role. Evidence goes to lab/.azure/lesson-15/evidence.
    Nothing here is tenant scoped: no Security Copilot setting, no Microsoft Graph consent, no tenant
    setting. Creating the capacity, the first-run choices, roles, plugins, and agents are your steps in
    the Security Copilot portal. Costs: the reaper runs every 30 minutes; with nothing to delete, each
    run is a trigger and two actions, well under a dollar a month on the Consumption plan.
.PARAMETER Deploy Create or update the guardrail.
.PARAMETER TestReaper Run the reaper's live test (creates and removes only free resources).
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Deploy-L15Lab.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Deploy-L15Lab.ps1 -Deploy
#>
[CmdletBinding(DefaultParameterSetName = 'WhatIf')]
param(
    [Parameter(ParameterSetName = 'Deploy')][switch]$Deploy,
    [Parameter(ParameterSetName = 'Test')][switch]$TestReaper
)
. (Join-Path $PSScriptRoot 'L15.Common.ps1')
$cfg = $script:L15Config
$started = Get-Date
[void](Assert-L15Context)
[void][IO.Directory]::CreateDirectory($script:L15State)

function New-L15Params {
    <# .SYNOPSIS Deployment parameters for the real guardrail or for the reaper test copy. #>
    param([switch]$Test)
    $p = [ordered]@{
        location = @{ value = $cfg.location }; resourceGroupName = @{ value = $cfg.resourceGroup }
        tags = @{ value = $cfg.tags }; baseline = @{ value = $cfg.baseline }
        reaperName = @{ value = $cfg.reaper.name }; roleName = @{ value = $cfg.reaper.roleName }
        targetResourceType = @{ value = $cfg.copilot.capacityResourceType }; targetApiVersion = @{ value = $cfg.copilot.capacityApiVersion }
        expiryTag = @{ value = $cfg.reaper.expiryTag }; defaultMaxHours = @{ value = [int]$cfg.reaper.defaultMaxHours }
        recurrenceMinutes = @{ value = [int]$cfg.reaper.recurrenceMinutes }
    }
    if ($Test) {
        # Same template and workflow; only the target type, the group, and the clock change.
        $p.resourceGroupName = @{ value = $cfg.names.reaperTestGroup }
        $p.reaperName = @{ value = "$($cfg.reaper.name)-test" }
        $p.targetResourceType = @{ value = 'Microsoft.ManagedIdentity/userAssignedIdentities' }
        $p.targetApiVersion = @{ value = '2023-01-31' }
        $p.defaultMaxHours = @{ value = 0 }
        $p.recurrenceMinutes = @{ value = 60 }
    }
    return $p
}

function Invoke-L15Deployment {
    <# .SYNOPSIS Runs what-if or create for main.bicep with a temporary parameters file (no secrets in it). #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Params, [switch]$WhatIf)
    $paramFile = Join-Path ([IO.Path]::GetTempPath()) ("sc500-l15-" + [guid]::NewGuid().ToString('N') + '.parameters.json')
    try {
        @{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $Params } |
            ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $paramFile -Encoding utf8
        $common = @('--name', $Name, '--location', $cfg.location, '--template-file', (Join-Path $script:L15Infra 'main.bicep'), '--parameters', "@$paramFile")
        if ($WhatIf) {
            return (Invoke-L15Az -Raw (@('deployment', 'sub', 'what-if') + $common + @('--result-format', 'ResourceIdOnly', '--no-pretty-print')))
        }
        $d = Invoke-L15Az (@('deployment', 'sub', 'create') + $common)
        if ($d.properties.provisioningState -ne 'Succeeded') { throw "Deployment $Name ended $($d.properties.provisioningState)." }
        return $d.properties.outputs.lab.value
    }
    finally { Remove-Item -LiteralPath $paramFile -ErrorAction SilentlyContinue }
}

function Invoke-L15ReaperRun {
    <#
    .SYNOPSIS Starts one reaper run now and waits for it to finish; returns the run.
    .DESCRIPTION A new role assignment can take a few minutes to reach ARM, so a run that fails on
                 authorization is retried after a pause. The recurrence trigger can be run on demand.
    #>
    param([Parameter(Mandatory)][string]$ReaperId, [int]$Attempts = 5)
    foreach ($attempt in 1..$Attempts) {
        $before = [DateTime]::UtcNow.AddSeconds(-5)
        [void](Invoke-L15Rest -Method post -Path "$ReaperId/triggers/Every_interval/run?api-version=2019-05-01")
        $run = $null
        foreach ($i in 1..30) {
            Start-Sleep -Seconds 6
            $runs = Invoke-L15Rest -Path "$ReaperId/runs?api-version=2019-05-01&`$top=5"
            $run = @($runs.value | Where-Object { ([DateTime]$_.properties.startTime).ToUniversalTime() -ge $before } | Select-Object -First 1)
            $run = if ($run) { $run[0] } else { $null }
            if ($run -and $run.properties.status -notin @('Running', 'Waiting')) { break }
        }
        if (-not $run) { throw 'The reaper run did not start within 3 minutes.' }
        if ($run.properties.status -eq 'Succeeded') { return $run }
        $list = Invoke-L15Rest -AllowNotFound -Path "$ReaperId/runs/$($run.name)/actions/List_targets?api-version=2019-05-01"
        $code = Get-L15Value $list 'properties.code'
        Write-Host "  Run $($run.name) ended $($run.properties.status) (list action: $code)."
        if ($attempt -lt $Attempts) { Write-Host '  Waiting 60 seconds for the role assignment to propagate.'; Start-Sleep -Seconds 60; continue }
        return $run
    }
}

if ($PSCmdlet.ParameterSetName -eq 'WhatIf') {
    Write-Host '== ARM what-if (nothing changes)'
    Invoke-L15Deployment -Name $cfg.deploymentName -Params (New-L15Params) -WhatIf | Out-Host
    return
}

if ($Deploy) {
    Write-Host "Deploying $($cfg.resourceGroup), the reaper's custom role, and $($cfg.reaper.name)."
    $lab = Invoke-L15Deployment -Name $cfg.deploymentName -Params (New-L15Params)
    [void](Write-L15Evidence 'deploy' ([ordered]@{ deployedUtc = [DateTime]::UtcNow.ToString('o')
        minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1); lab = $lab }))
    Write-Host ("Done in {0:N1} minutes. The reaper checks {1} every {2} minutes." -f ((Get-Date) - $started).TotalMinutes, $lab.resourceGroup, $lab.recurrenceMinutes)
    return
}

# -TestReaper: prove the delete logic on free resources, then remove everything the test made.
$testRg = $cfg.names.reaperTestGroup
$testName = "$($cfg.deploymentName)-reapertest"
$result = [ordered]@{ startedUtc = [DateTime]::UtcNow.ToString('o'); group = $testRg }
try {
    Write-Host "Deploying the reaper test copy in $testRg (targets user-assigned managed identities, which are free)."
    $lab = Invoke-L15Deployment -Name $testName -Params (New-L15Params -Test)
    $result.reaperId = $lab.reaperId
    $future = [DateTime]::UtcNow.AddHours(2).ToString('yyyy-MM-ddTHH:mm:ssZ')
    # An untagged identity: deadline = createdTime + 0 hours, so it must be deleted.
    # A tagged identity: deadline two hours out, so it must survive.
    [void](Invoke-L15Az @('identity', 'create', '--resource-group', $testRg, '--name', $cfg.names.probeExpired, '--location', $cfg.location, '--tags', "managedby=$($cfg.managedBy)"))
    [void](Invoke-L15Az @('identity', 'create', '--resource-group', $testRg, '--name', $cfg.names.probeKept, '--location', $cfg.location, '--tags', "managedby=$($cfg.managedBy)", "$($cfg.reaper.expiryTag)=$future"))
    Write-Host "  Created $($cfg.names.probeExpired) (no expiry tag) and $($cfg.names.probeKept) (expires in 2 hours). Running the reaper."
    $run = Invoke-L15ReaperRun -ReaperId $lab.reaperId
    $result.run = [ordered]@{ name = $run.name; status = $run.properties.status; startUtc = $run.properties.startTime; endUtc = $run.properties.endTime }
    $idBase = "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$testRg/providers/Microsoft.ManagedIdentity/userAssignedIdentities"
    $expired = $null; $kept = $null
    foreach ($i in 1..10) {
        $expired = Invoke-L15Rest -AllowNotFound -Path "$idBase/$($cfg.names.probeExpired)?api-version=2023-01-31"
        if (-not $expired) { break }
        Start-Sleep -Seconds 6
    }
    $kept = Invoke-L15Rest -AllowNotFound -Path "$idBase/$($cfg.names.probeKept)?api-version=2023-01-31"
    $result.expiredDeleted = ($null -eq $expired)
    $result.keptSurvived = ($null -ne $kept)
    $result.passed = [bool]($run.properties.status -eq 'Succeeded' -and $result.expiredDeleted -and $result.keptSurvived)
    Write-Host ("  Run {0}: {1}. Expired identity deleted: {2}. Unexpired identity kept: {3}." -f $run.name, $run.properties.status, $result.expiredDeleted, $result.keptSurvived)
}
finally {
    # Remove the test group (and its reaper and identities), then its custom role. The real guardrail is untouched.
    Write-Host "Removing $testRg and the test role."
    $g = Invoke-L15Az -AllowFailure @('group', 'show', '--name', $testRg)
    if ($g.ExitCode -eq 0) {
        $gObj = $g.Stdout | ConvertFrom-Json
        if ($gObj.tags.managedby -ne $cfg.managedBy) { throw "$testRg isn't tagged managedby=$($cfg.managedBy); refusing to delete it." }
        [void](Invoke-L15Az @('group', 'delete', '--name', $testRg, '--yes'))
    }
    $roles = @(Invoke-L15Az @('role', 'definition', 'list', '--custom-role-only', 'true', '--query', "[?starts_with(roleName, '$($cfg.reaper.roleName) (Microsoft.ManagedIdentity')]"))
    foreach ($r in $roles) { [void](Invoke-L15Az @('role', 'definition', 'delete', '--name', $r.name, '--scope', "/subscriptions/$($cfg.subscriptionId)")) }
    [void](Invoke-L15Az -AllowFailure @('deployment', 'sub', 'delete', '--name', $testName))
    $result.cleanedUp = ((Invoke-L15Az -AllowFailure @('group', 'show', '--name', $testRg)).ExitCode -ne 0)
    $result.finishedUtc = [DateTime]::UtcNow.ToString('o')
    [void](Write-L15Evidence 'reaper-test' $result)
}
if (-not $result.passed) { throw 'The reaper test failed. See the evidence file.' }
Write-Host 'Reaper test PASSED: the expired target was deleted, the unexpired one was kept, and the test resources are gone.'
