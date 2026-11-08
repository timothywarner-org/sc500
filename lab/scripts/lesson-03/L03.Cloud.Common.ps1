<#
.SYNOPSIS
Pins Lesson 3 operations to its course subscription and owned resources.
.DESCRIPTION
Use separate evidence and scope allowlists so another lesson cannot be changed accidentally.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:L03Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:L03Config = Get-Content (Join-Path $script:L03Root 'infra/lesson-03/config.json') -Raw | ConvertFrom-Json
$script:L03Evidence = Join-Path $script:L03Root '.azure/lesson-03/evidence'
$script:L03Python = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'

function Invoke-L03Az {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$Raw, [switch]$AllowFailure)
    # ArgumentList keeps URLs and JSON intact without passing them through cmd.exe.
    $start = [Diagnostics.ProcessStartInfo]::new($script:L03Python)
    $start.UseShellExecute=$false
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    # Reading account context does not select it; explicitly bind every CLI request.
    $boundArguments=if($Arguments -contains '--subscription'){$Arguments}else{$Arguments+@('--subscription',$script:L03Config.subscriptionId)}
    foreach($arg in @('-Im','azure.cli')+$boundArguments+@('--only-show-errors')){ $start.ArgumentList.Add($arg) }
    if(-not $Raw){$start.ArgumentList.Add('--output');$start.ArgumentList.Add('json')}
    $p=[Diagnostics.Process]::new(); $p.StartInfo=$start
    try {
        [void]$p.Start(); $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync()
        $p.WaitForExit(); $stdout=$outTask.GetAwaiter().GetResult();$stderr=$errTask.GetAwaiter().GetResult()
        if($AllowFailure){return [pscustomobject]@{exitCode=$p.ExitCode;stdout=$stdout;stderr=$stderr}}
        if($p.ExitCode -ne 0){throw "Azure CLI failed ($($p.ExitCode)): $stderr"}
        if($Raw){return $stdout}
        if(-not [string]::IsNullOrWhiteSpace($stdout)){return $stdout|ConvertFrom-Json -Depth 100}
    } finally {$p.Dispose()}
}

function Assert-L03Context {
    $account=Invoke-L03Az @('account','show','--subscription',$script:L03Config.subscriptionId)
    if($account.id -ne $script:L03Config.subscriptionId -or $account.tenantId -ne $script:L03Config.tenantId -or $account.state -ne 'Enabled'){throw 'The subscription and tenant in infra/lesson-03/config.json are required (the lab subscription since 2026-10-19).'}
    Write-Host "Lesson 3: $($account.name), tenant $($account.tenantId)."
}

function Write-L03Evidence {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)]$Value)
    [void][IO.Directory]::CreateDirectory($script:L03Evidence)
    $file=Join-Path $script:L03Evidence (([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))+'-'+$Name+'.json')
    $Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $file -Encoding utf8
    return $file
}

function Assert-L03Group {
    param([Parameter(Mandatory)][string]$Name,[switch]$AllowAbsent)
    if($Name -notin @($script:L03Config.resourceGroup,$script:L03Config.policyGroup)){throw 'Scope is outside the Lesson 3 allowlist.'}
    $exists=Invoke-L03Az @('group','exists','--name',$Name,'--subscription',$script:L03Config.subscriptionId)
    if(-not $exists){if($AllowAbsent){return $false};throw "Missing lesson group: $Name"}
    $rg=Invoke-L03Az @('group','show','--name',$Name,'--subscription',$script:L03Config.subscriptionId)
    $m=$rg|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
    if($m.tags.managedBy -ne 'sc500-l03-iac' -or $m.tags.course -ne 'SC500' -or $m.tags.lesson -ne '03'){throw "Ownership tags do not match: $Name"}
    return $true
}

function Get-L03Outputs {
    # Refresh from ARM so a stale local status file cannot supply a different resource binding.
    $d=Invoke-L03Az @('deployment','sub','show','--name','sc500-lesson03','--subscription',$script:L03Config.subscriptionId)
    if($d.properties.provisioningState -ne 'Succeeded'){throw 'Lesson 3 deployment has not succeeded.'}
    return $d.properties.outputs.lab.value
}

function Invoke-L03Arm {
    param([Parameter(Mandatory)][string]$Path,[string]$Method='GET',$Body,[switch]$AsHashtable)
    # Use the MFA-capable ARM audience already established for this tenant, without logging tokens.
    $token=Invoke-L03Az @('account','get-access-token','--resource','https://management.core.windows.net/','--subscription',$script:L03Config.subscriptionId)
    $params=@{Uri=('https://management.azure.com'+$Path);Method=$Method;Headers=@{Authorization='Bearer '+$token.accessToken};ContentType='application/json'}
    if($null -ne $Body){$params.Body=$Body|ConvertTo-Json -Depth 100 -Compress}
    try {
        # Defender payloads can contain case-distinct JSON keys that PSObject cannot preserve.
        if($AsHashtable){return (Invoke-WebRequest @params).Content|ConvertFrom-Json -AsHashtable -Depth 100}
        return Invoke-RestMethod @params
    } finally {$token=$null;$params.Headers.Clear()}
}
