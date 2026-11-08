<#
.SYNOPSIS
    Write-L13Verdict: end a Lesson 13 demo mode with a short "What this run proves" table.
.DESCRIPTION

    The verdict is a word, never a color, because color alone fails colorblind viewers and output shows up on every kind of
    screen. The comparison is trimmed, case-insensitive text, so callers turn booleans and counts into the same
    words on both sides first. Nothing here calls Azure. Same design as lesson-12\L12.Verdict.ps1.
.PARAMETER Rows
    Ordered dictionaries, each with Check, Expected and Observed.
.PARAMETER Title
    The table's heading line. Defaults to "What this run proves".
.EXAMPLE
    Write-L13Verdict -Rows @([ordered]@{ Check = 'CEF in Syslog'; Expected = 'none'; Observed = 'none' })
#>
function Write-L13Verdict {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary[]]$Rows,
        [string]$Title = 'What this run proves'
    )
    foreach ($r in $Rows) {
        foreach ($k in 'Check', 'Expected', 'Observed') {
            if (-not $r.Contains($k)) { throw "Write-L13Verdict: a row is missing '$k'." }
        }
    }
    # Column widths come from the longest value, so the table lines up at any font size.
    $w1 = [Math]::Max(5, ($Rows | ForEach-Object { "$($_['Check'])".Length } | Measure-Object -Maximum).Maximum)
    $w2 = [Math]::Max(8, ($Rows | ForEach-Object { "$($_['Expected'])".Length } | Measure-Object -Maximum).Maximum)
    $w3 = [Math]::Max(8, ($Rows | ForEach-Object { "$($_['Observed'])".Length } | Measure-Object -Maximum).Maximum)
    Write-Host ''
    Write-Host "== $Title"
    Write-Host ('  {0}  {1}  {2}  {3}' -f 'Check'.PadRight($w1), 'Expected'.PadRight($w2), 'Observed'.PadRight($w3), 'Verdict')
    foreach ($r in $Rows) {
        $same = [string]::Equals("$($r['Expected'])".Trim(), "$($r['Observed'])".Trim(), [StringComparison]::OrdinalIgnoreCase)
        $verdict = if ($same) { 'as expected' } else { 'DIFFERENT: say why' }
        Write-Host ('  {0}  {1}  {2}  {3}' -f "$($r['Check'])".PadRight($w1), "$($r['Expected'])".PadRight($w2), "$($r['Observed'])".PadRight($w3), $verdict)
    }
}
