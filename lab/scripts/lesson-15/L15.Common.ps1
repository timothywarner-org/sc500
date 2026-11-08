<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 15 lab: pin the subscription and tenant, call Azure CLI
    safely, save private evidence, call ARM and Microsoft Graph (read-only), query the Lesson 13
    Sentinel workspace, and read Lesson 14's pinned case.
.DESCRIPTION
    Dot-source this file from the other Lesson 15 scripts. It follows the Lesson 13 and Lesson 14
    helpers, and it's self-contained on purpose: Lesson 14's scripts have their own owner and
    release cycle, so Lesson 15 reads Lesson 14's config and handoff files but never dot-sources
    its scripts.

    Nothing here prints or writes a token, a key, or a password, and no script signs in as anyone:
    every call uses your current Azure CLI session. Nothing here changes a Security Copilot
    setting, a tenant setting, a Defender setting, or a Microsoft Graph consent.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L15Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L15Infra = Join-Path $script:L15Lab 'infra/lesson-15'
$script:L15Config = Get-Content (Join-Path $script:L15Infra 'config.json') -Raw | ConvertFrom-Json
$script:L15State = Join-Path $script:L15Lab '.azure/lesson-15'
$script:L15Evidence = Join-Path $script:L15State 'evidence'
$script:L14Config = Get-Content (Join-Path $script:L15Lab $script:L15Config.l14.config) -Raw | ConvertFrom-Json

# Call the CLI's own Python instead of az.cmd: cmd.exe mangles &, %, |, and quotes, which OData
# filters, KQL, and JSON bodies are full of. -I ignores PYTHON* variables, so UTF-8 goes on as -X utf8.
$script:L15Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L15Python)) { throw "Azure CLI Python not found at $script:L15Python. Install Azure CLI 2.85 or later." }

function Invoke-L15Az {
    <#
    .SYNOPSIS Runs one Azure CLI command pinned to the lesson subscription.
    .PARAMETER Arguments The CLI arguments, one element per token (no shell parsing happens).
    .PARAMETER Raw Return stdout as text instead of parsed JSON.
    .PARAMETER AllowFailure Return exit code, stdout, and stderr instead of throwing.
    .PARAMETER NoSubscription Omit --subscription (az rest and token commands reject it).
    #>
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$Raw,
        [switch]$AllowFailure,
        [switch]$NoSubscription
    )
    $start = [Diagnostics.ProcessStartInfo]::new($script:L15Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $all = @('-X', 'utf8', '-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L15Config.subscriptionId) }
    if (-not $Raw) { $all += @('--output', 'json') }
    foreach ($a in $all) { $start.ArgumentList.Add($a) }
    $p = [Diagnostics.Process]::new(); $p.StartInfo = $start
    try {
        [void]$p.Start()
        $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        $stdout = $outTask.GetAwaiter().GetResult(); $stderr = $errTask.GetAwaiter().GetResult()
        if ($AllowFailure) { return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $stdout; Stderr = $stderr } }
        if ($p.ExitCode -ne 0) { throw "Azure CLI failed ($($p.ExitCode)): $($stderr.Trim())" }
        if ($Raw) { return $stdout.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($stdout)) { return $stdout | ConvertFrom-Json -Depth 100 }
    }
    finally { $p.Dispose() }
}

function Assert-L15Context {
    # Refuse to run against any subscription, tenant, or operator but the course's.
    $account = Invoke-L15Az @('account', 'show')
    if ($account.id -ne $script:L15Config.subscriptionId -or $account.tenantId -ne $script:L15Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    if ($account.user.name -ne $script:L15Config.operatorUpn) { throw "Sign in as $($script:L15Config.operatorUpn) first." }
    Write-Host "Lesson 15: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L15Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L15Evidence)
    $file = Join-Path $script:L15Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    Write-Host "Evidence: $file"
    return $file
}

function Get-L15Value {
    <# .SYNOPSIS Reads a dotted property path, returning $null when any part is missing (StrictMode-safe). #>
    param($Object, [Parameter(Mandatory)][string]$Path)
    $cur = $Object
    foreach ($part in $Path -split '\.') {
        if ($null -eq $cur) { return $null }
        if ($cur -is [System.Collections.IDictionary]) { $cur = $cur[$part]; continue }
        $prop = $cur.PSObject.Properties[$part]
        if ($null -eq $prop) { return $null }
        $cur = $prop.Value
    }
    return $cur
}

function Invoke-L15Rest {
    <#
    .SYNOPSIS Calls ARM (a path starting with /subscriptions or /providers) or a full https URL through az rest.
    .PARAMETER Body An object; sent as compact JSON through a temporary file (no shell quoting).
    .PARAMETER AllowNotFound Return $null on 404 instead of throwing.
    .PARAMETER Resource The token audience for a non-ARM URL, for example https://graph.microsoft.com.
    #>
    param(
        [ValidateSet('get', 'put', 'post', 'delete', 'patch')][string]$Method = 'get',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [string]$Resource,
        [switch]$AllowNotFound
    )
    $url = if ($Path -like 'https://*') { $Path } else { "https://management.azure.com$Path" }
    $cli = @('rest', '--method', $Method, '--url', $url)
    if ($Resource) { $cli += @('--resource', $Resource) }
    $f = $null
    try {
        if ($null -ne $Body) {
            # Read-only POST queries still need a local request body under -WhatIf.
            # Cloud mutations are gated by the caller's ShouldProcess, not this temporary file.
            $f = New-TemporaryFile -WhatIf:$false
            $Body | ConvertTo-Json -Depth 30 -Compress | Set-Content -LiteralPath $f -Encoding utf8 -WhatIf:$false
            $cli += @('--headers', 'Content-Type=application/json', '--body', "@$f")
        }
        $r = Invoke-L15Az -NoSubscription -AllowFailure $cli
    }
    finally { if ($f) { Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue -WhatIf:$false } }
    if ($r.ExitCode -ne 0) {
        if ($AllowNotFound -and $r.Stderr -match '(Not Found|NotFound|ResourceNotFound|ResourceGroupNotFound|404)') { return $null }
        throw "$Method $Path failed: $($r.Stderr.Trim())"
    }
    $text = $r.Stdout.Trim().TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 100
}

function Invoke-L15Graph {
    <#
    .SYNOPSIS Runs one Azure Resource Graph query against the course subscription and returns rows.
    .DESCRIPTION The body goes through a temporary file because KQL is full of quotes and pipes.
    #>
    param([Parameter(Mandatory)][string]$Query)
    $r = Invoke-L15Rest -Method post -Path '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Body @{
        subscriptions = @($script:L15Config.subscriptionId); query = $Query; options = @{ resultFormat = 'objectArray'; '$top' = 1000 } }
    return @($r.data)
}

function Invoke-L15Query {
    <#
    .SYNOPSIS Runs one KQL query against the Lesson 13 workspace and returns the rows as objects.
    .DESCRIPTION Uses the Log Analytics query API, the same one the portal's Logs blade uses, with your
                 own permissions. That's the same identity Security Copilot uses for a Sentinel-target
                 KQL skill, so these rows are what the plugin should return.
    #>
    param([Parameter(Mandatory)]$L13Lab, [Parameter(Mandatory)][string]$Kql, [string]$Timespan = 'P7D')
    $r = Invoke-L15Rest -Method post -Path "https://api.loganalytics.io/v1/workspaces/$($L13Lab.workspaceCustomerId)/query" `
        -Resource 'https://api.loganalytics.io' -Body @{ query = $Kql; timespan = $Timespan }
    $t = $r.tables[0]
    $cols = @($t.columns | ForEach-Object name)
    return @(foreach ($row in $t.rows) {
        $o = [ordered]@{}
        for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
        [pscustomobject]$o
    })
}

function Get-L15L13Lab {
    <# .SYNOPSIS Lesson 13's outputs (workspace resource ID and customer ID). #>
    $d = Invoke-L15Az -AllowFailure @('deployment', 'sub', 'show', '--name', $script:L15Config.l13.deploymentName)
    if ($d.ExitCode -ne 0) { throw 'No Lesson 13 deployment found. Lesson 15 needs Lesson 13''s workspace.' }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The Lesson 13 deployment is $($d.properties.provisioningState), not Succeeded." }
    return $d.properties.outputs.lab.value
}

function Get-L15Outputs {
    <# .SYNOPSIS Lesson 15's own deployment outputs, or $null before Deploy-L15Lab.ps1 -Deploy has run. #>
    $d = Invoke-L15Az -AllowFailure @('deployment', 'sub', 'show', '--name', $script:L15Config.deploymentName)
    if ($d.ExitCode -ne 0) { return $null }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { return $null }
    return $d.properties.outputs.lab.value
}

function Get-L15Case {
    <#
    .SYNOPSIS The Lesson 14 case that Lesson 15 investigates: the pinned handoff, else Lesson 14's last incident.
    .OUTPUTS incidentName, incidentNumber, fixtureId, fileName, source (which file it came from).
    #>
    $pinFile = Join-Path $script:L15Lab $script:L15Config.l14.handoffFile
    if (Test-Path -LiteralPath $pinFile) {
        $pin = Get-Content -LiteralPath $pinFile -Raw | ConvertFrom-Json
        return [pscustomobject]@{ incidentName = $pin.incident.incidentName; incidentNumber = $pin.incident.incidentNumber
            fixtureId = $pin.fixture.fixtureId; fileName = $pin.fixture.fileName; source = 'Lesson 14 handoff pin' }
    }
    $inc = Join-Path $script:L15Lab $script:L15Config.l14.lastIncidentFile
    $fix = Join-Path $script:L15Lab $script:L15Config.l14.lastFixtureFile
    if (-not (Test-Path -LiteralPath $inc) -or -not (Test-Path -LiteralPath $fix)) {
        throw 'No Lesson 14 case found. Lesson 15 needs Lesson 14''s incident; see the Lesson 15 prep page.'
    }
    $i = Get-Content -LiteralPath $inc -Raw | ConvertFrom-Json
    $x = Get-Content -LiteralPath $fix -Raw | ConvertFrom-Json
    return [pscustomobject]@{ incidentName = $i.incidentName; incidentNumber = $i.incidentNumber
        fixtureId = $x.fixtureId; fileName = $x.fileName; source = 'Lesson 14 last incident (no pin)' }
}

function Get-L15Incident {
    param([Parameter(Mandatory)]$L13Lab, [Parameter(Mandatory)][string]$IncidentName)
    return Invoke-L15Rest -AllowNotFound -Path "$($L13Lab.workspaceId)/providers/Microsoft.SecurityInsights/incidents/$IncidentName`?api-version=2025-09-01"
}

function Get-L15IncidentPart {
    <# .SYNOPSIS alerts and entities are listed with POST; comments with GET. #>
    param([Parameter(Mandatory)]$L13Lab, [Parameter(Mandatory)][string]$IncidentName,
          [Parameter(Mandatory)][ValidateSet('alerts', 'entities', 'comments')][string]$Part)
    $method = if ($Part -eq 'comments') { 'get' } else { 'post' }
    $r = Invoke-L15Rest -Method $method -Path "$($L13Lab.workspaceId)/providers/Microsoft.SecurityInsights/incidents/$IncidentName/$Part`?api-version=2025-09-01"
    if ($Part -eq 'entities') { return @(Get-L15Value $r 'entities') }
    return @(Get-L15Value $r 'value')
}

function Get-L15PluginManifest {
    <#
    .SYNOPSIS Parses the plugin YAML with the Azure CLI's bundled PyYAML and returns it as an object.
    .DESCRIPTION PowerShell has no YAML parser, and the CLI already ships one, so there's nothing to install.
                 A parse failure here means Security Copilot would reject the upload too.
    #>
    $file = Join-Path $script:L15Lab $script:L15Config.plugin.file
    $py = 'import sys, json, yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1], encoding="utf-8"))))'
    $start = [Diagnostics.ProcessStartInfo]::new($script:L15Python)
    $start.UseShellExecute = $false; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    foreach ($a in @('-X', 'utf8', '-I', '-c', $py, $file)) { $start.ArgumentList.Add($a) }
    $p = [Diagnostics.Process]::Start($start)
    $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "The plugin manifest didn't parse: $($err.Trim())" }
    return $out | ConvertFrom-Json -Depth 50
}

function Get-L15Capacities {
    <#
    .SYNOPSIS Every Security Copilot capacity in the course subscription, with creation time and expiry.
    .DESCRIPTION Resource Graph finds capacities in any group (so one created outside the guarded group
                 still shows up); ARM's list API adds createdTime, which Resource Graph doesn't return.
    #>
    $type = $script:L15Config.copilot.capacityResourceType
    $rows = @(Invoke-L15Graph -Query "resources | where type =~ '$type' | project id, name, resourceGroup, location, tags, properties")
    $created = @{}
    foreach ($g in @($rows | ForEach-Object resourceGroup | Sort-Object -Unique)) {
        $list = Invoke-L15Rest -AllowNotFound -Path ("/subscriptions/$($script:L15Config.subscriptionId)/resourceGroups/$g/resources?api-version=2021-04-01" +
            "&`$filter=resourceType%20eq%20%27$type%27&`$expand=createdTime")
        foreach ($r in @(Get-L15Value $list 'value')) { $created[$r.id.ToLowerInvariant()] = $r.createdTime }
    }
    $tag = $script:L15Config.reaper.expiryTag
    return @(foreach ($c in $rows) {
        $createdUtc = $created[$c.id.ToLowerInvariant()]
        $expiry = Get-L15Value $c "tags.$tag"
        [pscustomobject]@{ id = $c.id; name = $c.name; resourceGroup = $c.resourceGroup; location = $c.location
            createdUtc = $createdUtc; expiresUtc = $expiry; properties = $c.properties
            guarded = ($c.resourceGroup -ieq $script:L15Config.resourceGroup) }
    })
}

function Get-L15ProvisionedEstimate {
    <#
    .SYNOPSIS Retail estimate of provisioned SCU charges so far: units x billed clock hours x the hourly price.
    .DESCRIPTION Microsoft bills provisioned capacity per clock hour, starting with the hour you create it, so a
                 capacity created at 9:55 and read has two billed hours. Overage is billed only when used and isn't visible here, so it's excluded.
                 This is an estimate before credits and tax, not a bill.
    #>
    param([Parameter(Mandatory)]$Capacity)
    $units = Get-L15Value $Capacity 'properties.numberOfUnits'
    if (-not $units -or -not $Capacity.createdUtc) { return $null }
    # WHY floor both ends to the hour: the bill counts clock hours touched, not elapsed time.
    $c = ([DateTime]$Capacity.createdUtc).ToUniversalTime(); $n = [DateTime]::UtcNow
    $c0 = [DateTime]::new($c.Year, $c.Month, $c.Day, $c.Hour, 0, 0, [DateTimeKind]::Utc)
    $n0 = [DateTime]::new($n.Year, $n.Month, $n.Day, $n.Hour, 0, 0, [DateTimeKind]::Utc)
    $hours = [int](($n0 - $c0).TotalHours) + 1
    return [pscustomobject]@{ units = [int]$units; startedHours = [int]$hours
        usd = [int]$units * [int]$hours * [double]$script:L15Config.copilot.provisionedUsdPerUnitHour }
}
