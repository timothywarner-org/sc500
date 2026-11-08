<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 11 lab: pin the subscription and tenant, call Azure CLI
    safely, save private evidence, call ARM, Foundry, and the gateway, and read the lab's outputs.
.DESCRIPTION
    Dot-source this file from the other Lesson 11 scripts. Same design as L10.Common.ps1.
    Nothing here prints or writes a token or a key. The gateway subscription key is read with
    listSecrets into memory for one run and never leaves the process. No script signs in as
    anyone; ARM, Foundry, and Log Analytics calls use your current Azure CLI session.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L11Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L11Infra = Join-Path $script:L11Lab 'infra/lesson-11'
$script:L11Config = Get-Content (Join-Path $script:L11Infra 'config.json') -Raw | ConvertFrom-Json
$script:L11State = Join-Path $script:L11Lab '.azure/lesson-11'
$script:L11Evidence = Join-Path $script:L11State 'evidence'
$script:L11ChatApiVersion = '2024-10-21'

# Call the CLI's own Python instead of az.cmd: cmd.exe mangles &, %, |, and quotes, which OData
# filters, KQL, and JSON bodies are full of. -I ignores PYTHON* variables, so UTF-8 goes on as -X utf8.
$script:L11Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L11Python)) { throw "Azure CLI Python not found at $script:L11Python. Install Azure CLI 2.85 or later." }

function Invoke-L11Az {
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
    $start = [Diagnostics.ProcessStartInfo]::new($script:L11Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $all = @('-X', 'utf8', '-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L11Config.subscriptionId) }
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

function Assert-L11Context {
    # Refuse to run against any subscription, tenant, or operator but the course's.
    $account = Invoke-L11Az @('account', 'show')
    if ($account.id -ne $script:L11Config.subscriptionId -or $account.tenantId -ne $script:L11Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    if ($account.user.name -ne $script:L11Config.operatorUpn) { throw "Sign in as $($script:L11Config.operatorUpn) first." }
    Write-Host "Lesson 11: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L11Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L11Evidence)
    $file = Join-Path $script:L11Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    Write-Host "Evidence: $file"
    return $file
}

function Get-L11Value {
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

function Invoke-L11Rest {
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
    # APIM policy GET also offers XML. This helper parses JSON, so request that media type.
    $headers = @('Accept=application/json')
    if ($null -ne $Body) { $headers += 'Content-Type=application/json' }
    $cli = @('rest', '--method', $Method, '--url', $url, '--headers') + $headers
    if ($null -ne $Body) { $cli += @('--body', ($Body | ConvertTo-Json -Depth 30 -Compress)) }
    $r = Invoke-L11Az -NoSubscription -AllowFailure $cli
    if ($r.ExitCode -ne 0) {
        if ($AllowNotFound -and $r.Stderr -match '(Not Found|NotFound|ResourceNotFound|404)') { return $null }
        throw "$Method $Path failed: $($r.Stderr.Trim())"
    }
    $text = $r.Stdout.Trim().TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 100
}

function Get-L11Token {
    <# .SYNOPSIS Returns an access token for a resource from your CLI session, in memory only. #>
    param([Parameter(Mandatory)][string]$Resource)
    return (Invoke-L11Az -NoSubscription @('account', 'get-access-token', '--resource', $Resource, '--query', 'accessToken', '--output', 'tsv') -Raw)
}

function Get-L11Outputs {
    # Read names from the deployment record in ARM, not a local file.
    $d = Invoke-L11Az -AllowFailure @('deployment', 'sub', 'show', '--name', $script:L11Config.deploymentName)
    if ($d.ExitCode -ne 0) { throw 'No Lesson 11 deployment found. Run Deploy-L11Lab.ps1 -Deploy first.' }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The Lesson 11 deployment is $($d.properties.provisioningState), not Succeeded." }
    return $d.properties.outputs.lab.value
}

function Get-L11GatewayOutputs {
    # The gateway deployment is resource-group scoped. $null when it isn't deployed right now.
    $d = Invoke-L11Az -AllowFailure @('deployment', 'group', 'show', '--resource-group', $script:L11Config.resourceGroup, '--name', $script:L11Config.gatewayDeploymentName)
    if ($d.ExitCode -ne 0) { return $null }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { return $null }
    $g = $d.properties.outputs.gateway.value
    # A deployment record outlives the instance it created; confirm the instance is still there.
    $live = Invoke-L11Az -AllowFailure @('apim', 'show', '--resource-group', $script:L11Config.resourceGroup, '--name', $g.apim, '--query', 'provisioningState')
    if ($live.ExitCode -ne 0) { return $null }
    return $g
}

function Get-L11SubscriptionKey {
    <# .SYNOPSIS Reads the servicehub-assistant subscription's primary key into memory. Never printed. #>
    param([Parameter(Mandatory)]$Gateway)
    $path = "/subscriptions/$($script:L11Config.subscriptionId)/resourceGroups/$($script:L11Config.resourceGroup)/providers/Microsoft.ApiManagement/service/$($Gateway.apim)/subscriptions/$($Gateway.subscription)/listSecrets?api-version=2024-05-01"
    return (Invoke-L11Rest -Method post -Path $path).primaryKey
}

function Invoke-L11Http {
    <#
    .SYNOPSIS Sends one HTTP request and returns status, selected headers, and the parsed body.
             Never throws on an HTTP error status; the status is the result the demo shows.
    .PARAMETER Headers Request headers. Values are never echoed.
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('GET', 'POST')][string]$Method = 'POST',
        [hashtable]$Headers = @{},
        $Body,
        [int]$TimeoutSec = 120
    )
    # Not $args: that's PowerShell's automatic variable.
    $req = @{ Uri = $Uri; Method = $Method; Headers = $Headers; SkipHttpErrorCheck = $true; TimeoutSec = $TimeoutSec }
    if ($null -ne $Body) { $req.Body = ($Body | ConvertTo-Json -Depth 30 -Compress); $req.ContentType = 'application/json' }
    $started = [DateTime]::UtcNow
    $resp = Invoke-WebRequest @req
    $json = $null
    try { $json = $resp.Content | ConvertFrom-Json -Depth 100 } catch { }
    $keep = @{}
    foreach ($h in 'apim-request-id', 'x-ctso-gateway-request-id', 'x-ms-request-id', 'x-request-id', 'Retry-After', $script:L11Config.gateway.remainingTokensHeader, 'x-ctso-tokens-consumed', 'x-ms-region') {
        if ($resp.Headers.ContainsKey($h)) { $keep[$h] = ($resp.Headers[$h] -join ',') }
    }
    return [pscustomobject]@{ Status = [int]$resp.StatusCode; Headers = $keep; Body = $json; Text = [string]$resp.Content
                              AtUtc = $started.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
}

function Get-L11FilterSummary {
    <#
    .SYNOPSIS Reduces a Foundry content filter result to the fields that decide the lesson's point:
             which control fired, whether it was detected, and whether it blocked.
    #>
    param($Result)
    if ($null -eq $Result) { return $null }
    $out = [ordered]@{}
    foreach ($p in $Result.PSObject.Properties) {
        $v = $p.Value
        if ($p.Name -eq 'custom_blocklists') {
            $det = Get-L11Value $v 'details'
            $items = if ($det) { $det } else { $v }
            $out['custom_blocklists'] = @($items | ForEach-Object { if ($_ -and $_.PSObject.Properties['id']) { "$($_.id) filtered=$($_.filtered)" } }) -join '; '
            continue
        }
        if ($v -is [pscustomobject]) {
            $f = Get-L11Value $v 'filtered'; $d = Get-L11Value $v 'detected'; $s = Get-L11Value $v 'severity'
            $bits = @()
            if ($null -ne $d) { $bits += "detected=$d" }
            if ($null -ne $s) { $bits += "severity=$s" }
            if ($null -ne $f) { $bits += "filtered=$f" }
            if ($bits) { $out[$p.Name] = $bits -join ' ' }
        }
    }
    return [pscustomobject]$out
}
