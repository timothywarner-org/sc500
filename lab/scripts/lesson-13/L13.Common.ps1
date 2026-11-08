<#
.SYNOPSIS
    Shared helpers for the SC-500 Lesson 13 lab: pin the subscription and tenant, call Azure CLI
    safely, save private evidence, call ARM and Azure Resource Graph, query the Sentinel workspace,
    run commands inside the collector VMs, and read the lab's outputs.
.DESCRIPTION
    Dot-source this file from the other Lesson 13 scripts. Same design as L12.Common.ps1.
    Nothing here prints or writes a token, a key, or a password, and no script signs in as anyone:
    every call uses your current Azure CLI session. Nothing here changes a Defender plan or a
    tenant setting.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:L13Lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L13Infra = Join-Path $script:L13Lab 'infra/lesson-13'
$script:L13Config = Get-Content (Join-Path $script:L13Infra 'config.json') -Raw | ConvertFrom-Json
$script:L13State = Join-Path $script:L13Lab '.azure/lesson-13'
$script:L13Evidence = Join-Path $script:L13State 'evidence'
# Write-L13Verdict: the "What this run proves" table every proving mode ends with.
. (Join-Path $PSScriptRoot 'L13.Verdict.ps1')

# Call the CLI's own Python instead of az.cmd: cmd.exe mangles &, %, |, and quotes, which OData
# filters, KQL, and JSON bodies are full of. -I ignores PYTHON* variables, so UTF-8 goes on as -X utf8.
$script:L13Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $script:L13Python)) { throw "Azure CLI Python not found at $script:L13Python. Install Azure CLI 2.85 or later." }

function Invoke-L13Az {
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
    $start = [Diagnostics.ProcessStartInfo]::new($script:L13Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $all = @('-X', 'utf8', '-Im', 'azure.cli') + $Arguments + @('--only-show-errors')
    if (-not $NoSubscription) { $all += @('--subscription', $script:L13Config.subscriptionId) }
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

function Assert-L13Context {
    # Refuse to run against any subscription, tenant, or operator but the course's.
    $account = Invoke-L13Az @('account', 'show')
    if ($account.id -ne $script:L13Config.subscriptionId -or $account.tenantId -ne $script:L13Config.tenantId) {
        throw 'The signed-in Azure CLI context is not the course subscription and tenant.'
    }
    if ($account.user.name -ne $script:L13Config.operatorUpn) { throw "Sign in as $($script:L13Config.operatorUpn) first." }
    Write-Host "Lesson 13: $($account.name), signed in as $($account.user.name)."
    return $account
}

function Write-L13Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L13Evidence)
    $file = Join-Path $script:L13Evidence ('{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $file -Encoding utf8
    Write-Host "Evidence: $file"
    return $file
}

function Get-L13Value {
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

function Test-L13RoleAction {
    <# .SYNOPSIS Evaluates grants per permission block; NotActions never denies another role's grant. #>
    param([object[]]$Roles, [Parameter(Mandatory)][string]$Operation)
    # Azure RBAC adds grants. Flattening NotActions across roles invents a deny assignment.
    foreach ($role in $Roles) {
        foreach ($permission in $role.permissions) {
            $allowed = @($permission.actions | Where-Object { $Operation -like $_ }).Count -gt 0
            $excluded = @($permission.notActions | Where-Object { $Operation -like $_ }).Count -gt 0
            if ($allowed -and -not $excluded) { return $true }
        }
    }
    return $false
}

function Invoke-L13Rest {
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
    $r = Invoke-L13Az -NoSubscription -AllowFailure $cli
    if ($r.ExitCode -ne 0) {
        if ($AllowNotFound -and $r.Stderr -match '(Not Found|NotFound|ResourceNotFound|404)') { return $null }
        throw "$Method $Path failed: $($r.Stderr.Trim())"
    }
    $text = $r.Stdout.Trim().TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 100
}

function Get-L13Token {
    <# .SYNOPSIS Returns an access token for a resource from your CLI session, in memory only. #>
    param([Parameter(Mandatory)][string]$Resource)
    return (Invoke-L13Az -NoSubscription @('account', 'get-access-token', '--resource', $Resource, '--query', 'accessToken', '--output', 'tsv') -Raw)
}

function Get-L13Outputs {
    # Read names from the deployment record in ARM, not a local file.
    $d = Invoke-L13Az -AllowFailure @('deployment', 'sub', 'show', '--name', $script:L13Config.deploymentName)
    if ($d.ExitCode -ne 0) { throw 'No Lesson 13 deployment found. Run Deploy-L13Lab.ps1 -Deploy first.' }
    $d = $d.Stdout | ConvertFrom-Json -Depth 100
    if ($d.properties.provisioningState -ne 'Succeeded') { throw "The Lesson 13 deployment is $($d.properties.provisioningState), not Succeeded." }
    return $d.properties.outputs.lab.value
}

function Invoke-L13Graph {
    <#
    .SYNOPSIS Runs one Azure Resource Graph query against the course subscription and returns rows.
    .DESCRIPTION The body goes through a temporary file because KQL is full of quotes and pipes.
    #>
    param([Parameter(Mandatory)][string]$Query)
    $body = @{ subscriptions = @($script:L13Config.subscriptionId); query = $Query; options = @{ resultFormat = 'objectArray'; '$top' = 1000 } }
    $f = New-TemporaryFile
    try {
        $body | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $f -Encoding utf8
        $r = Invoke-L13Az -NoSubscription -AllowFailure @('rest', '--method', 'post', '--url',
            'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01', '--body', "@$f")
        if ($r.ExitCode -ne 0) { throw "Resource Graph query failed: $($r.Stderr.Trim())" }
        return @(($r.Stdout | ConvertFrom-Json -Depth 100).data)
    }
    finally { Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue }
}

function Invoke-L13Query {
    <#
    .SYNOPSIS Runs one KQL query against the lesson workspace and returns the rows as objects.
    .DESCRIPTION Uses the Log Analytics query API (the same one the portal's Logs blade uses). The query
                 goes through a temporary file for the same quoting reason as Invoke-L13Graph.
    .PARAMETER Timespan ISO 8601 duration the query may look back over; KQL filters narrow it further.
    #>
    param([Parameter(Mandatory)]$Lab, [Parameter(Mandatory)][string]$Kql, [string]$Timespan = 'P7D')
    $f = New-TemporaryFile
    try {
        @{ query = $Kql; timespan = $Timespan } | ConvertTo-Json -Compress | Set-Content -LiteralPath $f -Encoding utf8
        $azArgs = @('rest', '--method', 'post', '--resource', 'https://api.loganalytics.io',
            '--url', "https://api.loganalytics.io/v1/workspaces/$($Lab.workspaceCustomerId)/query", '--body', "@$f")
        $r = Invoke-L13Az -NoSubscription -AllowFailure $azArgs
        # One retry after 3 s on a refused or reset connection. In testing, the
        # first call got "actively refused" from api.loganalytics.io and the next one connected; a retry keeps a
        # card alive. A real query error (bad KQL, no access) still throws on the second answer.
        if ($r.ExitCode -ne 0 -and $r.Stderr -match 'refused|reset|timed out|ConnectionError|Max retries') {
            Start-Sleep -Seconds 3
            $r = Invoke-L13Az -NoSubscription -AllowFailure $azArgs
        }
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

function Invoke-L13Guest {
    <#
    .SYNOPSIS Runs a guest script inside one of the collector VMs with Run Command and returns its output.
    .DESCRIPTION The VMs have no public IP and no inbound rule, so Run Command (through the Azure VM
                 agent) is the only way in. The VM must be running; Start-L13Lab.ps1 starts it.
                 Values are substituted into a temporary copy of the script (tokens like __MARKER__),
                 because Linux and Windows Run Command pass parameters differently. The copy is deleted.
    .PARAMETER Vm The VM name.
    .PARAMETER Name A file in scripts/lesson-13/guest: .sh for Linux, .ps1 for Windows.
    .PARAMETER Values Token-to-value map, for example @{ MARKER = 'SC500-L13-...' }.
    #>
    param([Parameter(Mandatory)][string]$Vm, [Parameter(Mandatory)][string]$Name, [hashtable]$Values = @{})
    $source = Get-L13Guest -Name $Name
    $text = Get-Content -LiteralPath $source -Raw
    foreach ($k in $Values.Keys) { $text = $text.Replace("__$($k)__", [string]$Values[$k]) }
    if ($text -match '__[A-Z]+__') { throw "Guest script $Name still has an unfilled token: $($Matches[0])" }
    $ext = [IO.Path]::GetExtension($Name)
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("sc500-l13-" + [guid]::NewGuid().ToString('N') + $ext)
    # Linux scripts need LF line endings; Windows scripts are fine either way.
    if ($ext -eq '.sh') { $text = $text -replace "`r`n", "`n" }
    [IO.File]::WriteAllText($tmp, $text, [Text.UTF8Encoding]::new($false))
    try {
        $cmd = if ($ext -eq '.ps1') { 'RunPowerShellScript' } else { 'RunShellScript' }
        $r = Invoke-L13Az @('vm', 'run-command', 'invoke', '--resource-group', $script:L13Config.resourceGroup, '--name', $Vm,
            '--command-id', $cmd, '--scripts', "@$tmp")
        return ((@($r.value | ForEach-Object { $_.message }) -join "`n").Trim())
    }
    finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
}

function Get-L13PowerState {
    param([Parameter(Mandatory)][string]$Vm)
    $v = Invoke-L13Az @('vm', 'get-instance-view', '--resource-group', $script:L13Config.resourceGroup, '--name', $Vm,
        '--query', "instanceView.statuses[?starts_with(code,'PowerState/')].code | [0]", '--output', 'tsv') -Raw
    return ($v -replace '^PowerState/', '')
}

function Assert-L13Running {
    param([Parameter(Mandatory)][string]$Vm)
    $state = Get-L13PowerState -Vm $Vm
    if ($state -ne 'running') { throw "$Vm is $state. Run Start-L13Lab.ps1 first." }
}

function Get-L13Guest {
    <# .SYNOPSIS Full path of a guest script in scripts/lesson-13/guest. #>
    param([Parameter(Mandatory)][string]$Name)
    return (Join-Path (Join-Path $PSScriptRoot 'guest') $Name)
}
