<#
.SYNOPSIS
Provides pinned Azure context and private evidence helpers for Lesson 2 only.
.DESCRIPTION
The CLI Python entry point and ArgumentList preserve URLs without cmd.exe parsing.
No function changes the user's default subscription or imports another lesson.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:L02Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L02Config = Get-Content -LiteralPath (Join-Path $script:L02Root 'infra/lesson-02/config.json') -Raw | ConvertFrom-Json
$script:L02Evidence = Join-Path $script:L02Root '.azure/lesson-02/evidence'
$script:L02Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'

function Invoke-L02Az {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$Raw)
    if (-not (Test-Path -LiteralPath $script:L02Python)) { throw 'Azure CLI Python runtime was not found.' }
    # ArgumentList prevents ampersands in ARM and Graph URLs from becoming shell operators.
    $start = [Diagnostics.ProcessStartInfo]::new($script:L02Python)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($item in @('-Im','azure.cli') + $Arguments + @('--only-show-errors')) { $start.ArgumentList.Add($item) }
    if (-not $Raw) { $start.ArgumentList.Add('--output'); $start.ArgumentList.Add('json') }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Azure CLI exited $($process.ExitCode): $stderr" }
        if ($Raw) { return $stdout }
        if (-not [string]::IsNullOrWhiteSpace($stdout)) { return $stdout | ConvertFrom-Json -Depth 100 }
    } finally { $process.Dispose() }
}

function Assert-L02Context {
    $account = Invoke-L02Az @('account','show','--subscription',$script:L02Config.subscriptionId)
    if ($account.id -ne $script:L02Config.subscriptionId -or $account.tenantId -ne $script:L02Config.tenantId -or $account.state -ne 'Enabled') {
        throw 'Lesson 2 requires the configured enabled lab subscription and tenant.'
    }
    Write-Host "Lesson 2 context: $($account.name), $($account.id), tenant $($account.tenantId)."
}

function Write-L02Evidence {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L02Evidence)
    $path = Join-Path $script:L02Evidence ("{0}-{1}.json" -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), $Name)
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding utf8
}

function Assert-L02OwnedGroup {
    param([Parameter(Mandatory)][string]$Name, [switch]$AllowAbsent)
    if ($Name -notin @($script:L02Config.identityGroup,$script:L02Config.targetGroup)) { throw 'Group is outside the Lesson 2 allowlist.' }
    $exists = Invoke-L02Az @('group','exists','--name',$Name,'--subscription',$script:L02Config.subscriptionId)
    if (-not $exists) { if ($AllowAbsent) { return $false }; throw "Group does not exist: $Name" }
    $group = Invoke-L02Az @('group','show','--name',$Name,'--subscription',$script:L02Config.subscriptionId)
    $groupMap = $group | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
    if ($groupMap.tags.managedBy -ne $script:L02Config.managedBy -or $groupMap.tags.lesson -ne '02' -or $groupMap.tags.course -ne 'SC500') {
        throw "Refusing to modify $Name because the Lesson 2 ownership tags do not match."
    }
    return $true
}

function Get-L02Container {
    [void](Assert-L02OwnedGroup -Name $script:L02Config.identityGroup)
    $containers = @(Invoke-L02Az @('container','list','--resource-group',$script:L02Config.identityGroup,'--subscription',$script:L02Config.subscriptionId))
    return $containers | Where-Object name -EQ $script:L02Config.containerName
}
