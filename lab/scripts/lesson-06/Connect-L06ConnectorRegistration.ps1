<#
.SYNOPSIS
    Gets a short-lived connector registration token and protects it with Windows DPAPI.
.DESCRIPTION
    The user completes Microsoft's device sign-in. Tokens never print and are never stored
    in the repository. Use only on the course operator's Windows account.
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
$start=[Diagnostics.ProcessStartInfo]::new($script:L06Python)
$start.UseShellExecute=$false
$start.RedirectStandardOutput=$true
$start.RedirectStandardError=$true
$start.ArgumentList.Add((Join-Path $PSScriptRoot 'Get-L06ConnectorRegistrationToken.py'))
$p=[Diagnostics.Process]::new();$p.StartInfo=$start
try {
    [void]$p.Start()
    $output=$p.StandardOutput.ReadToEndAsync()
    while(-not $p.StandardError.EndOfStream){Write-Host $p.StandardError.ReadLine()}
    $p.WaitForExit()
    if($p.ExitCode -ne 0){throw 'Connector registration sign-in did not complete.'}
    $result=$output.GetAwaiter().GetResult()|ConvertFrom-Json
    $folder=Join-Path $env:LOCALAPPDATA 'SC500/Lesson06'
    [void][IO.Directory]::CreateDirectory($folder)
    $result.access_token|ConvertTo-SecureString -AsPlainText -Force|Export-Clixml (Join-Path $folder 'connector-registration.token.xml')
    [pscustomobject]@{ExpiresUtc=[DateTime]::UtcNow.AddSeconds($result.expires_in).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $folder 'connector-registration-expiry.json')
    $result=$null
    Write-Host 'Connector registration token obtained and DPAPI protected.'
} finally {$p.Dispose()}
