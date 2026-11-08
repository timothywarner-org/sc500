<#
.SYNOPSIS
    Verifies the Lesson 7 templates and scripts without deploying anything.

.DESCRIPTION
    Offline (the default), in this order:
      1. Bicep build and lint of every template in infra/lesson-07, with that folder's bicepconfig.json,
         which raises the Bicep linter's security and hygiene rules to errors. The compiled ARM JSON
         lands in a temporary folder.
      2. The Contoso CAF compliance checker (lab/scripts/Test-Sc500CafCompliance.py) on config.json
         and the compiled JSON: names, tags, literal names, preview APIs, auto-shutdown, budget.
      3. A PowerShell parse of every Lesson 7 script, and PSScriptAnalyzer when it's installed.
         It isn't installed by this script: adding a module to the computer is your call.

    With -Azure, it then runs Deploy-L07Lab.ps1 without -Deploy, which is read-only in Azure: the
    preflight (group owner, VM SKU and quota, Key Vault name, budget API, same names elsewhere), ARM
    validation, and what-if for the retained template. Nothing is created, changed, or deleted.
    The policy and firewall templates can't be validated against Azure until the retained lab
    exists, because they deploy into its resource group; step 1 and 2 cover them offline.

    Every result prints PASS, WARN, SKIP or FAIL in words.

.PARAMETER Azure
    Also run the read-only preflight, validation and what-if in the course subscription.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Test-L07Templates.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Test-L07Templates.ps1 -Azure
#>
[CmdletBinding()]
param([switch]$Azure)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$lab = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$infra = Join-Path $lab 'infra/lesson-07'
$out = Join-Path ([IO.Path]::GetTempPath()) ("l07-arm-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
[void][IO.Directory]::CreateDirectory($out)
$rows = [Collections.Generic.List[object]]::new()
function Add-Row([string]$Result, [string]$Check, [string]$Detail) { $rows.Add([pscustomobject]@{ Result = $Result; Check = $Check; Detail = $Detail }) }

# The CLI's own Python avoids az.cmd's argument mangling, the same reason L07.Common.ps1 gives.
$azPython = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
function Invoke-Az([string[]]$Arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new($azPython)
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    foreach ($a in @('-Im', 'azure.cli') + $Arguments) { $psi.ArgumentList.Add($a) }
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync(); $p.WaitForExit()
    [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $o.Result; Stderr = $e.Result }
}

# 1. Build and lint. Linter diagnostics arrive on stderr as "file(line,col) : Error|Warning rule: text".
foreach ($f in 'main', 'retained', 'vm', 'budget', 'policy', 'firewall') {
    $src = Join-Path $infra "$f.bicep"
    $r = Invoke-Az @('bicep', 'build', '--file', $src, '--outfile', (Join-Path $out "$f.json"))
    $diag = @(($r.Stderr -split "`r?`n") | Where-Object { $_ -match '\) : (Error|Warning) ' })
    $errors = @($diag | Where-Object { $_ -match '\) : Error ' })
    $warns = @($diag | Where-Object { $_ -match '\) : Warning ' })
    if ($r.ExitCode -ne 0 -or $errors.Count) { Add-Row 'FAIL' "Bicep build and lint: $f.bicep" ((@($errors) + "exit $($r.ExitCode)" + $r.Stderr.Trim()) -join ' | ') }
    elseif ($warns.Count) { Add-Row 'WARN' "Bicep build and lint: $f.bicep" ($warns -join ' | ') }
    else { Add-Row 'PASS' "Bicep build and lint: $f.bicep" 'no linter findings' }
}

# 2. CAF compliance on config.json and the compiled templates (main.json carries its modules inline).
$checker = Join-Path $lab 'scripts/Test-Sc500CafCompliance.py'
$arm = @('main', 'policy', 'firewall' | ForEach-Object { Join-Path $out "$_.json" } | Where-Object { Test-Path -LiteralPath $_ })
$caf = & python -X utf8 $checker --config (Join-Path $infra 'config.json') --arm @arm 2>&1
$cafText = ($caf | Out-String).Trim()
$cafFails = @($caf | Where-Object { "$_" -like '`[FAIL`]*' })
Add-Row $(if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }) 'Contoso CAF compliance' (($cafText -split "`r?`n")[-1] + $(if ($cafFails.Count) { ' | ' + ($cafFails -join ' | ') } else { '' }))

# 3. PowerShell: every script parses; PSScriptAnalyzer when present.
foreach ($ps in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($ps.FullName, [ref]$tokens, [ref]$parseErrors)
    Add-Row $(if ($parseErrors.Count) { 'FAIL' } else { 'PASS' }) "PowerShell parse: $($ps.Name)" $(if ($parseErrors.Count) { ($parseErrors | ForEach-Object Message) -join ' | ' } else { 'no syntax errors' })
}
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    $found = @(Invoke-ScriptAnalyzer -Path $PSScriptRoot -Severity Error, Warning -ExcludeRule PSAvoidUsingWriteHost, PSUseShouldProcessForStateChangingFunctions)
    $err = @($found | Where-Object Severity -eq 'Error')
    Add-Row $(if ($err.Count) { 'FAIL' } elseif ($found.Count) { 'WARN' } else { 'PASS' }) 'PSScriptAnalyzer (Error and Warning)' $(if ($found.Count) { ($found | ForEach-Object { "$($_.ScriptName):$($_.Line) $($_.RuleName)" }) -join ' | ' } else { 'no findings' })
}
else { Add-Row 'SKIP' 'PSScriptAnalyzer' 'not installed; Install-Module PSScriptAnalyzer -Scope CurrentUser adds it' }

# 4. Optional: the read-only Azure preview of the retained template.
if ($Azure) {
    try {
        & (Join-Path $PSScriptRoot 'Deploy-L07Lab.ps1') | Out-Host
        Add-Row 'PASS' 'Azure preflight, validation and what-if (read-only)' 'Deploy-L07Lab.ps1 preview finished with no deletions; evidence in lab/.azure/lesson-07/<subscription>/evidence'
    }
    catch { Add-Row 'FAIL' 'Azure preflight, validation and what-if (read-only)' $_.Exception.Message }
}

$rows | Format-Table -AutoSize -Wrap | Out-String -Width 250 | Out-Host
$fails = @($rows | Where-Object Result -eq 'FAIL').Count
"L07 TEMPLATE CHECK: $(if ($fails) { 'FAIL' } else { 'PASS' }). $(@($rows | Where-Object Result -eq 'PASS').Count) PASS, $(@($rows | Where-Object Result -eq 'WARN').Count) WARN, $(@($rows | Where-Object Result -eq 'SKIP').Count) SKIP, $fails FAIL. Compiled JSON: $out"
if ($fails) { exit 1 }
