<#
.SYNOPSIS
Shared context, CLI, and evidence helpers for the retained SC-500 demo environment.
.DESCRIPTION
Pins the intended subscription and avoids cmd.exe argument corruption for Graph URLs and JSON.
No access token, password, or private key is written to evidence.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Sc500Root = Split-Path $PSScriptRoot -Parent
$script:Sc500Config = Get-Content -Raw -LiteralPath (Join-Path $script:Sc500Root 'infra/sc500.config.json') | ConvertFrom-Json

function Invoke-Sc500Az {
    <# .SYNOPSIS Runs Azure CLI with preserved argument boundaries and mandatory exit-code checking. #>
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$Raw)
    # Callers guard remote mutations with ShouldProcess; local error capture must still work during previews.
    $WhatIfPreference = $false
    # az.cmd can split Graph query strings at ampersands; invoke the installed CLI Python directly on Windows.
    $cliPython = Join-Path $env:ProgramFiles 'Microsoft SDKs/Azure/CLI2/python.exe'
    if (-not (Test-Path -LiteralPath $cliPython)) { throw "Azure CLI Python runtime not found: $cliPython" }
    $stderr = [IO.Path]::GetTempFileName()
    try {
        $lines = & $cliPython -Im azure.cli @Arguments --only-show-errors --output json 2> $stderr
        if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed ($LASTEXITCODE): $([IO.File]::ReadAllText($stderr))" }
        $body = $lines -join "`n"
        if ($Raw) { return $body }
        if (-not [string]::IsNullOrWhiteSpace($body)) { return $body | ConvertFrom-Json -Depth 100 }
    }
    finally { Remove-Item -LiteralPath $stderr -ErrorAction SilentlyContinue }
}

function Assert-Sc500Context {
    <# .SYNOPSIS Rejects a tenant or subscription mismatch without changing the user's global CLI default. #>
    $account = Invoke-Sc500Az -Arguments @('account','show','--subscription',$script:Sc500Config.subscriptionId)
    if ($account.tenantId -ne $script:Sc500Config.tenantId -or $account.state -ne 'Enabled') {
        throw 'The configured subscription is not enabled in the expected tenant. Reauthenticate before continuing.'
    }
    Write-Host "Subscription: $($account.name) [$($account.id)]"
    Write-Host "Tenant: $($account.tenantId)"
    return $account
}

function Write-Sc500Evidence {
    <# .SYNOPSIS Preserves timestamped local observations without replacing earlier evidence. #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    $directory = Join-Path $script:Sc500Root '.azure/evidence'
    New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false | Out-Null
    $path = Join-Path $directory (('{0}-{1}.json' -f (Get-Date -AsUTC -Format 'yyyyMMddTHHmmssfffZ'),$Name))
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding utf8 -WhatIf:$false
    return $path
}

function Assert-Sc500OwnedGroup {
    <# .SYNOPSIS Refuses to change a group that does not carry this course's ownership tag. #>
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -notin $script:Sc500Config.resourceGroups) { throw "Group is outside the course allowlist: $Name" }
    $group = Invoke-Sc500Az -Arguments @('group','show','--name',$Name,'--subscription',$script:Sc500Config.subscriptionId)
    if (-not $group.tags -or $group.tags.managedBy -ne $script:Sc500Config.ownershipTag -or $group.tags.course -ne 'SC500') {
        throw "Group ownership is not established: $Name"
    }
    return $group
}

function Invoke-Sc500Graph {
    <# .SYNOPSIS Calls Graph with the current administrator context, keeping tokens and request secrets in memory. #>
    param([Parameter(Mandatory)][string]$Path, [ValidateSet('GET','POST','PATCH','DELETE')][string]$Method='GET', $Body)
    $token = Invoke-Sc500Az -Arguments @('account','get-access-token','--resource-type','ms-graph','--subscription',$script:Sc500Config.subscriptionId)
    $request = @{Uri=('https://graph.microsoft.com/v1.0/'+$Path.TrimStart('/'));Method=$Method;Headers=@{Authorization=('Bearer '+$token.accessToken)};ErrorAction='Stop'}
    if ($null -ne $Body) { $request.Body=$Body | ConvertTo-Json -Depth 30 -Compress; $request.ContentType='application/json' }
    try { Invoke-RestMethod @request }
    finally { $token=$null; $request=$null }
}

function Invoke-Sc500Arm {
    <# .SYNOPSIS Uses ARM REST for documented PIM and role APIs not exposed directly by the CLI. #>
    param([Parameter(Mandatory)][string]$Path, [ValidateSet('GET','POST','PUT','PATCH','DELETE')][string]$Method='GET', $Body)
    if (-not $Path.StartsWith('/subscriptions/'+$script:Sc500Config.subscriptionId+'/')) { throw 'ARM path is outside the lab subscription.' }
    # Match Azure CLI's ARM audience so REST calls reuse the operation-specific MFA session.
    $token=Invoke-Sc500Az -Arguments @('account','get-access-token','--resource','https://management.core.windows.net/','--subscription',$script:Sc500Config.subscriptionId)
    $request=@{Uri=('https://management.azure.com'+$Path);Method=$Method;Headers=@{Authorization=('Bearer '+$token.accessToken)};ErrorAction='Stop'}
    if ($null -ne $Body) { $request.Body=$Body | ConvertTo-Json -Depth 30 -Compress; $request.ContentType='application/json' }
    try { Invoke-RestMethod @request }
    finally { $token=$null; $request=$null }
}
