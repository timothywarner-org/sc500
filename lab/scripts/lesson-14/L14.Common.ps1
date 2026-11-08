<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 14 lab: pin the subscription and tenant, call Azure CLI
    safely, save private evidence, call ARM, query the Lesson 13 Sentinel workspace, and read both
    lessons' deployment outputs.
.DESCRIPTION
    Dot-source this file from the other Lesson 14 scripts. Same design as L13.Common.ps1, without the
    VM helpers: Lesson 14 runs no VMs. Nothing here prints or writes a token, a key, or a password,
    and these helpers use your current Azure CLI session. The separately authorized Audit setup
    helper uses delegated Exchange sign-in. Nothing in these common helpers
    changes a Defender plan, a tenant setting, or a Microsoft Graph consent.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L14Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L14Infra = Join-Path $script:L14Lab 'infra/lesson-14'
$script:L14Config = Get-Content (Join-Path $script:L14Infra 'config.json') -Raw | ConvertFrom-Json
$script:L14State = Join-Path $script:L14Lab '.azure/lesson-14'
$script:L14Evidence = Join-Path $script:L14State 'evidence'

# Call the CLI's own Python instead of az.cmd: cmd.exe mangles &, %, |, and quotes, which OData
# filters, KQL, and JSON bodies are full of. -I ignores PYTHON* variables, so UTF-8 goes on as -X utf8.
$script:L14Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L14Python)) { throw "Azure CLI Python not found at $script:L14Python. Install Azure CLI 2.85 or later." }

function Invoke-L14Az {
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
    $start = [Diagnostics.ProcessStartInfo]::new($script:L14Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $all = @('-X', 'utf8', '-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L14Config.subscriptionId) }
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

function Assert-L14Context {
    # Refuse to run against any subscription, tenant, or operator but the course's.
    $account = Invoke-L14Az @('account', 'show')
    if ($account.id -ne $script:L14Config.subscriptionId -or $account.tenantId -ne $script:L14Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    if ($account.user.name -ne $script:L14Config.operatorUpn) { throw "Sign in as $($script:L14Config.operatorUpn) first." }
    Write-Host "Lesson 14: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L14Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L14Evidence)
    $file = Join-Path $script:L14Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    Write-Host "Evidence: $file"
    return $file
}

function Get-L14Value {
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

function Invoke-L14Rest {
    <#
    .SYNOPSIS Calls ARM (a path starting with /subscriptions or /providers) through az rest.
    .PARAMETER Body An object; sent as compact JSON.
    .PARAMETER AllowNotFound Return $null on 404 instead of throwing.
    #>
    param(
        [ValidateSet('get', 'put', 'post', 'delete', 'patch')][string]$Method = 'get',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [switch]$AllowNotFound
    )
    $url = if ($Path -like 'https://*') { $Path } else { "https://management.azure.com$Path" }
    $cli = @('rest', '--method', $Method, '--url', $url)
    if ($null -ne $Body) { $cli += @('--headers', 'Content-Type=application/json', '--body', ($Body | ConvertTo-Json -Depth 30 -Compress)) }
    $r = Invoke-L14Az -NoSubscription -AllowFailure $cli
    if ($r.ExitCode -ne 0) {
        if ($AllowNotFound -and $r.Stderr -match '(Not Found|NotFound|ResourceNotFound|404)') { return $null }
        throw "$Method $Path failed: $($r.Stderr.Trim())"
    }
    $text = $r.Stdout.Trim().TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 100
}

function Get-L14Token {
    <# .SYNOPSIS Returns an access token for a resource from your CLI session, in memory only. #>
    param([Parameter(Mandatory)][string]$Resource)
    return (Invoke-L14Az -NoSubscription @('account', 'get-access-token', '--resource', $Resource, '--query', 'accessToken', '--output', 'tsv') -Raw)
}

function Get-L14Outputs {
    # Read names from the deployment record in ARM, not a local file.
    $d = Invoke-L14Az -AllowFailure @('deployment', 'sub', 'show', '--name', $script:L14Config.deploymentName)
    if ($d.ExitCode -ne 0) { throw 'No Lesson 14 deployment found. Run Deploy-L14Lab.ps1 -Deploy first.' }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The Lesson 14 deployment is $($d.properties.provisioningState), not Succeeded." }
    return $d.properties.outputs.lab.value
}

function Invoke-L14Graph {
    <#
    .SYNOPSIS Runs one Azure Resource Graph query against the course subscription and returns rows.
    .DESCRIPTION The body goes through a temporary file because KQL is full of quotes and pipes.
    #>
    param([Parameter(Mandatory)][string]$Query)
    $body = @{ subscriptions = @($script:L14Config.subscriptionId); query = $Query; options = @{ resultFormat = 'objectArray'; '$top' = 1000 } }
    $f = New-TemporaryFile
    try {
        $body | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $f -Encoding utf8
        $r = Invoke-L14Az -NoSubscription -AllowFailure @('rest', '--method', 'post', '--url',
            'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01', '--body', "@$f")
        if ($r.ExitCode -ne 0) { throw "Resource Graph query failed: $($r.Stderr.Trim())" }
        return @(($r.Stdout | ConvertFrom-Json -Depth 100).data)
    }
    finally { Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue }
}

function Invoke-L14Query {
    <#
    .SYNOPSIS Runs one KQL query against the lesson workspace and returns the rows as objects.
    .DESCRIPTION Uses the Log Analytics query API (the same one the portal's Logs blade uses). The query
                 goes through a temporary file for the same quoting reason as Invoke-L14Graph.
    .PARAMETER Timespan ISO 8601 duration the query may look back over; KQL filters narrow it further.
    #>
    param([Parameter(Mandatory)]$Lab, [Parameter(Mandatory)][string]$Kql, [string]$Timespan = 'P7D')
    $f = New-TemporaryFile
    try {
        @{ query = $Kql; timespan = $Timespan } | ConvertTo-Json -Compress | Set-Content -LiteralPath $f -Encoding utf8
        $r = Invoke-L14Az -NoSubscription -AllowFailure @('rest', '--method', 'post', '--resource', 'https://api.loganalytics.io',
            '--url', "https://api.loganalytics.io/v1/workspaces/$($Lab.workspaceCustomerId)/query", '--body', "@$f")
        if ($r.ExitCode -ne 0) { throw "Log Analytics query failed: $($r.Stderr.Trim())" }
        $t = ($r.Stdout | ConvertFrom-Json -Depth 100).tables[0]
        $cols = @($t.columns | ForEach-Object name)
        return @(foreach ($row in $t.rows) {
            $o = [ordered]@{}
            for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
            [pscustomobject]$o
        })
    }
    finally { Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue }
}

function Get-L14L13Lab {
    <# .SYNOPSIS Lesson 13's outputs (workspace IDs, the ServiceHub DCR and its ingestion endpoint). #>
    $d = Invoke-L14Az -AllowFailure @('deployment', 'sub', 'show', '--name', $script:L14Config.l13.deploymentName)
    if ($d.ExitCode -ne 0) { throw 'No Lesson 13 deployment found. Lesson 14 needs Lesson 13''s workspace first.' }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The Lesson 13 deployment is $($d.properties.provisioningState), not Succeeded." }
    return $d.properties.outputs.lab.value
}

function Get-L14Kql {
    <# .SYNOPSIS Text of a KQL file in infra/lesson-14/kql, the same file Bicep deploys. #>
    param([Parameter(Mandatory)][string]$Name)
    return Get-Content -LiteralPath (Join-Path (Join-Path $script:L14Infra 'kql') $Name) -Raw
}

function Get-L14Incidents {
    <#
    .SYNOPSIS Incidents created from the Lesson 14 analytics rule, newest first.
    .DESCRIPTION Reads the Sentinel incidents API and keeps the ones whose related rule is ours.
    #>
    param([Parameter(Mandatory)]$L13Lab, [int]$Top = 20)
    $path = "$($L13Lab.workspaceId)/providers/Microsoft.SecurityInsights/incidents?api-version=2025-09-01&`$orderby=properties/createdTimeUtc%20desc&`$top=$Top"
    $r = Invoke-L14Rest -Path $path
    $rule = $script:L14Config.names.analyticsRuleId
    return @($r.value | Where-Object { @($_.properties.relatedAnalyticRuleIds) -match $rule })
}

function Get-L14IncidentAlerts {
    <# .SYNOPSIS The alerts inside one incident (the API lists them with POST). #>
    param([Parameter(Mandatory)]$L13Lab, [Parameter(Mandatory)][string]$IncidentName)
    $r = Invoke-L14Rest -Method post -Path "$($L13Lab.workspaceId)/providers/Microsoft.SecurityInsights/incidents/$IncidentName/alerts?api-version=2025-09-01"
    return @($r.value)
}

function Get-L14IncidentComments {
    param([Parameter(Mandatory)]$L13Lab, [Parameter(Mandatory)][string]$IncidentName)
    $r = Invoke-L14Rest -Path "$($L13Lab.workspaceId)/providers/Microsoft.SecurityInsights/incidents/$IncidentName/comments?api-version=2025-09-01"
    return @($r.value)
}

function Get-L14LastFixture {
    <# .SYNOPSIS The fixture record written by Invoke-L14DetectionDemo.ps1 -Mode Send. #>
    $pin = Get-L14PinnedCase
    if ($pin) { return $pin.fixture }
    $f = Join-Path $script:L14State 'last-fixture.json'
    if (-not (Test-Path -LiteralPath $f)) { throw 'No Lesson 14 fixture yet. Run Invoke-L14DetectionDemo.ps1 -Mode Send first.' }
    return Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
}

. (Join-Path $PSScriptRoot 'L14.ReviewChecks.ps1')
