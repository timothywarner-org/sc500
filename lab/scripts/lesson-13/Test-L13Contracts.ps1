<#
.SYNOPSIS
    Offline regression tests for cumulative RBAC grants and the demo evidence boundary.
.DESCRIPTION
    No Azure calls or writes. These cases reproduce the false deny from merging NotActions
    across roles, and check that syntax errors cannot reach your demo session.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'L13.Common.ps1')
$operation = 'Microsoft.SecurityInsights/automationRules/write'
$restricted = @{ permissions = @(@{ actions = @('Microsoft.SecurityInsights/*'); notActions = @($operation) }) }
$grant = @{ permissions = @(@{ actions = @($operation); notActions = @() }) }
$cases = @(
    @{ Name='Excluded action alone is not granted'; Roles=@($restricted); Expected=$false },
    @{ Name='Independent role adds excluded action'; Roles=@($restricted,$grant); Expected=$true },
    @{ Name='Role order does not change cumulative grant'; Roles=@($grant,$restricted); Expected=$true },
    @{ Name='No assignments means no grant'; Roles=@(); Expected=$false },
    @{ Name='Case-insensitive resource operation'; Roles=@(@{permissions=@(@{actions=@($operation.ToUpper());notActions=@()})}); Expected=$true }
)
foreach ($case in $cases) {
    $actual = Test-L13RoleAction -Roles $case.Roles -Operation $operation
    if ($actual -ne $case.Expected) { throw $case.Name }
    Write-Host "PASS $($case.Name)"
}
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.ps1 -Recurse) {
    $tokens=$null; $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw "$($file.Name): $($parseErrors.Message -join '; ')" }
}
Write-Host 'PASS all Lesson 13 PowerShell sources parse'
