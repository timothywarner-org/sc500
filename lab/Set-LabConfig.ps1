<#
.SYNOPSIS
    Puts your own tenant, subscription, domain, and account into every SC-500 lab file, in one step.

.DESCRIPTION
    The published lab files carry placeholders such as <your-subscription-id> where the course
    lab used real values. This script replaces those placeholders under the lab folder with the
    values you pass, so every config.json, script, and template points at your environment.

    WHY one script: each lesson has its own config.json, and several scripts check that you are
    signed in to the expected tenant and subscription before they change anything. Editing a
    dozen files by hand invites a typo that only shows up halfway through a demo.

    What it changes: text files under lab\ that contain a placeholder. Nothing else.
    What it never touches: Azure, Microsoft Entra, or any file outside lab\.
    Run it with -WhatIf first to see every file it would change.

    It is safe to run more than once. After the first run no placeholders remain, so a second run
    changes nothing. To start over with different values, restore the originals from Git
    (git -C C:\github\sc500 checkout -- lab) and run it again.

    Two values are left for you to fill in by hand, because they only exist after you create
    the Lesson 1 objects: <your-access-review-id> and <your-lab-user-object-id>. The script
    lists where they are.

.PARAMETER SubscriptionId
    The Azure subscription for the labs. Use a dedicated sandbox with a budget alert.

.PARAMETER TenantId
    The Microsoft Entra tenant that owns that subscription.

.PARAMETER Domain
    A verified domain in your tenant, for example contoso.onmicrosoft.com. Lab users are created
    as sc500.<name>@<Domain>, and Lesson 12 uses it as the Defender EASM discovery seed, so only
    use a domain you own.

.PARAMETER AdminUpn
    The account you sign in with to run the labs, for example admin@contoso.onmicrosoft.com.

.PARAMETER GitHubOwner
    Your GitHub user or organization, for the Lesson 2 workload identity federation subject.
    Only Lesson 2 uses it. Default: the placeholder stays.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\Set-LabConfig.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -TenantId 11111111-1111-1111-1111-111111111111 -Domain contoso.onmicrosoft.com -AdminUpn admin@contoso.onmicrosoft.com -WhatIf

    Shows every file that would change, and changes nothing.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\Set-LabConfig.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -TenantId 11111111-1111-1111-1111-111111111111 -Domain contoso.onmicrosoft.com -AdminUpn admin@contoso.onmicrosoft.com -GitHubOwner my-github-name

    Writes your values into the lab files and prints a count for each placeholder.

.NOTES
    Requires PowerShell 7.4 or later. Part of the companion repository for the Pearson video course
    Exam SC-500: Cloud and AI Security Engineer Associate (Video).
#>
#Requires -Version 7.4
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][guid]$TenantId,
    [Parameter(Mandatory)][ValidatePattern('^(?=.{4,253}$)([a-z0-9-]+\.)+[a-z]{2,}$')][string]$Domain,
    [Parameter(Mandatory)][ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')][string]$AdminUpn,
    [ValidatePattern('^[A-Za-z0-9-]{1,39}$')][string]$GitHubOwner
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The lab folder is wherever this script lives, so it works from any clone location.
$labRoot = $PSScriptRoot

# Placeholder -> your value. The domain and UPN are lowercased because Entra compares them
# case-insensitively but the scripts compare strings exactly.
$map = [ordered]@{
    '<your-subscription-id>' = $SubscriptionId.ToString()
    '<your-tenant-id>'       = $TenantId.ToString()
    '<your-admin-upn>'       = $AdminUpn.ToLowerInvariant()
    '<your-domain>'          = $Domain.ToLowerInvariant()
}
if ($GitHubOwner) { $map['<your-github-owner>'] = $GitHubOwner }
$manual = '<your-access-review-id>', '<your-lab-user-object-id>'

# Text files only. Binary files never carry placeholders, and reading them as text would corrupt them.
$extensions = '.ps1', '.py', '.bicep', '.json', '.yaml', '.yml', '.sh', '.xml', '.kql', '.csv', '.txt', '.sql', '.md'
$files = Get-ChildItem -LiteralPath $labRoot -Recurse -File |
    Where-Object {
        # Skip this script, the lab README (it names the placeholders on purpose), and local state.
        $_.Extension -in $extensions -and $_.FullName -ne $PSCommandPath -and $_.Name -ne 'README.md' -and
        $_.FullName -notmatch '[\\/]\.azure[\\/]'
    }

$counts = [ordered]@{}
foreach ($key in $map.Keys) { $counts[$key] = 0 }
$changed = 0
foreach ($file in $files) {
    $text = [IO.File]::ReadAllText($file.FullName)
    $new = $text
    foreach ($key in $map.Keys) {
        $hits = ([regex]::Matches($new, [regex]::Escape($key))).Count
        if ($hits) {
            $counts[$key] += $hits
            $new = $new.Replace($key, $map[$key])
        }
    }
    if ($new -ne $text -and $PSCmdlet.ShouldProcess($file.FullName.Substring($labRoot.Length + 1), 'Write your lab values')) {
        # Keep the file's encoding as UTF-8 without a byte order mark, which every tool in the lab reads.
        [IO.File]::WriteAllText($file.FullName, $new, [Text.UTF8Encoding]::new($false))
        $changed++
    }
}

Write-Host ''
Write-Host "Files changed: $changed"
foreach ($key in $counts.Keys) { Write-Host ("  {0,-26} {1} replaced" -f $key, $counts[$key]) }
if (-not $GitHubOwner) { Write-Host '  <your-github-owner>        left as is (pass -GitHubOwner for Lesson 2)' }

# Point at the two values that only exist after you build Lesson 1.
$left = $files | Select-String -SimpleMatch -Pattern $manual
if ($left) {
    Write-Host ''
    Write-Host 'Fill these in by hand after you create the Lesson 1 objects:'
    $left | ForEach-Object { Write-Host ("  {0}:{1}  {2}" -f $_.Path.Substring($labRoot.Length + 1), $_.LineNumber, $_.Line.Trim()) }
}
if ($changed -eq 0 -and -not $WhatIfPreference) {
    Write-Host ''
    Write-Host 'No placeholders were left to replace. To use different values, run: git -C C:\github\sc500 checkout -- lab'
}
