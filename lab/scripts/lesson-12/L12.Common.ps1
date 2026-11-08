<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 12 lab: pin the subscription and tenant, call Azure CLI
    safely, save private evidence, call ARM, Azure Resource Graph, and the Defender EASM data plane,
    and read the lab's outputs.
.DESCRIPTION
    Dot-source this file from the other Lesson 12 scripts. Same design as L11.Common.ps1.
    Nothing here prints or writes a token or a key, and no script signs in as anyone: every call
    uses your current Azure CLI session. Nothing here changes a Defender plan.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L12Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L12Infra = Join-Path $script:L12Lab 'infra/lesson-12'
$script:L12Config = Get-Content (Join-Path $script:L12Infra 'config.json') -Raw | ConvertFrom-Json
$script:L12State = Join-Path $script:L12Lab '.azure/lesson-12'
$script:L12Evidence = Join-Path $script:L12State 'evidence'

# Call the CLI's own Python instead of az.cmd: cmd.exe mangles &, %, |, and quotes, which OData
# filters, KQL, and JSON bodies are full of. -I ignores PYTHON* variables, so UTF-8 goes on as -X utf8.
$script:L12Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L12Python)) { throw "Azure CLI Python not found at $script:L12Python. Install Azure CLI 2.85 or later." }

function Invoke-L12Az {
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
    $start = [Diagnostics.ProcessStartInfo]::new($script:L12Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $all = @('-X', 'utf8', '-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L12Config.subscriptionId) }
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

function Assert-L12Context {
    # Refuse to run against any subscription, tenant, or operator but the course's.
    $account = Invoke-L12Az @('account', 'show')
    if ($account.id -ne $script:L12Config.subscriptionId -or $account.tenantId -ne $script:L12Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    if ($account.user.name -ne $script:L12Config.operatorUpn) { throw "Sign in as $($script:L12Config.operatorUpn) first." }
    Write-Host "Lesson 12: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L12Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L12Evidence)
    $file = Join-Path $script:L12Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    Write-Host "Evidence: $file"
    return $file
}

function Get-L12Value {
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

function Invoke-L12Rest {
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
    $r = Invoke-L12Az -NoSubscription -AllowFailure $cli
    if ($r.ExitCode -ne 0) {
        if ($AllowNotFound -and $r.Stderr -match '(Not Found|NotFound|ResourceNotFound|404)') { return $null }
        throw "$Method $Path failed: $($r.Stderr.Trim())"
    }
    $text = $r.Stdout.Trim().TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 100
}

function Get-L12Token {
    <# .SYNOPSIS Returns an access token for a resource from your CLI session, in memory only. #>
    param([Parameter(Mandatory)][string]$Resource)
    return (Invoke-L12Az -NoSubscription @('account', 'get-access-token', '--resource', $Resource, '--query', 'accessToken', '--output', 'tsv') -Raw)
}

function Get-L12Outputs {
    # Read names from the deployment record in ARM, not a local file.
    $d = Invoke-L12Az -AllowFailure @('deployment', 'sub', 'show', '--name', $script:L12Config.deploymentName)
    if ($d.ExitCode -ne 0) { throw 'No Lesson 12 deployment found. Run Deploy-L12Lab.ps1 -Deploy first.' }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The Lesson 12 deployment is $($d.properties.provisioningState), not Succeeded." }
    return $d.properties.outputs.lab.value
}

function Invoke-L12Graph {
    <#
    .SYNOPSIS Runs one Azure Resource Graph query against the course subscription and returns rows.
    .DESCRIPTION Defender for Cloud publishes assessments, attack paths, and secure scores to the
                 securityresources table, so one query can read posture across every lesson's groups.
                 The body goes through a temporary file because KQL is full of quotes and pipes.
    #>
    param([Parameter(Mandatory)][string]$Query)
    $body = @{ subscriptions = @($script:L12Config.subscriptionId); query = $Query; options = @{ resultFormat = 'objectArray'; '$top' = 1000 } }
    $f = New-TemporaryFile
    try {
        $body | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $f -Encoding utf8
        $r = Invoke-L12Az -NoSubscription -AllowFailure @('rest', '--method', 'post', '--url',
            'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01', '--body', "@$f")
        if ($r.ExitCode -ne 0) { throw "Resource Graph query failed: $($r.Stderr.Trim())" }
        return @(($r.Stdout | ConvertFrom-Json -Depth 100).data)
    }
    finally { Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue }
}

function Invoke-L12Easm {
    <#
    .SYNOPSIS Calls the Defender EASM data plane for the lab workspace (discovery groups, assets).
    .DESCRIPTION Discovery groups and inventory aren't ARM resources; they live behind
                 https://<region>.easm.defender.microsoft.com and take a token for that audience.
                 The token stays in memory for this one request.
    .PARAMETER Path The part after /workspaces/<name>/, for example discoGroups/servicehub-external.
    #>
    param(
        [ValidateSet('GET', 'PUT', 'POST')][string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Path,
        [string]$Query = '',
        $Body
    )
    $cfg = $script:L12Config
    $base = "https://$($cfg.easmLocation).easm.defender.microsoft.com/subscriptions/$($cfg.subscriptionId)/resourceGroups/$($cfg.easmResourceGroup)/workspaces/$($cfg.names.easmWorkspace)"
    $uri = "$base/$Path`?api-version=$($cfg.easm.dataPlaneApiVersion)$Query"
    $token = Get-L12Token -Resource 'https://easm.defender.microsoft.com/'
    $req = @{ Uri = $uri; Method = $Method; Headers = @{ Authorization = "Bearer $token" }; SkipHttpErrorCheck = $true; TimeoutSec = 120 }
    if ($null -ne $Body) { $req.Body = ($Body | ConvertTo-Json -Depth 20 -Compress); $req.ContentType = 'application/json' }
    $resp = Invoke-WebRequest @req
    $json = $null
    try { $json = $resp.Content | ConvertFrom-Json -Depth 100 } catch { }
    return [pscustomobject]@{ Status = [int]$resp.StatusCode; Body = $json; Text = [string]$resp.Content }
}

function Get-L12Fixture {
    <# .SYNOPSIS Reads the export store's security-relevant properties straight from ARM. #>
    param([Parameter(Mandatory)]$Lab)
    $s = Invoke-L12Rest -Path "$($Lab.storageId)?api-version=2023-05-01"
    return [pscustomobject][ordered]@{
        storage = $s.name
        allowSharedKeyAccess = Get-L12Value $s 'properties.allowSharedKeyAccess'
        publicNetworkAccess = Get-L12Value $s 'properties.publicNetworkAccess'
        networkDefaultAction = Get-L12Value $s 'properties.networkAcls.defaultAction'
        allowBlobPublicAccess = Get-L12Value $s 'properties.allowBlobPublicAccess'
        minimumTlsVersion = Get-L12Value $s 'properties.minimumTlsVersion'
    }
}
