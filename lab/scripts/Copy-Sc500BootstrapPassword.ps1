<#
.SYNOPSIS
Copies Debra's Windows-protected bootstrap password to the local clipboard for first sign-in.
.DESCRIPTION
Run locally in your Windows session. Never prints the password or sends it to the agent.
The credential is usable only by the Windows profile that created the DPAPI file.
After first sign-in changes the password, the bootstrap is obsolete. Clear the clipboard after pasting.
#>
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if (-not $IsWindows) { throw 'This bootstrap credential is protected by Windows DPAPI.' }
$credential=Import-Clixml -LiteralPath (Join-Path $env:LOCALAPPDATA 'SC500/debra-bootstrap.credential.xml')
try { Set-Clipboard -Value $credential.GetNetworkCredential().Password }
finally { $credential=$null }
Write-Host 'Bootstrap password copied locally. Paste into the Debra sign-in, then clear the clipboard with Set-Clipboard -Value "". Never paste it into chat.'
