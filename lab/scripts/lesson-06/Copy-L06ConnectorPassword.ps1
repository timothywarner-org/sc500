<#
.SYNOPSIS
    Copies the bounded connector host's admin password to the clipboard for your RDP sign-in.

.DESCRIPTION
    Deploy-L06Bounded.ps1 -Lab Connector generates the password and saves it only as a
    DPAPI-protected credential under %LOCALAPPDATA%\SC500\Lesson06, readable by your Windows
    account on this machine. This script never prints it. Paste it only into the Remote Desktop
    prompt for the connector VM (config.json names.connectorVm, user contosoadmin), then clear the clipboard:
        Set-Clipboard -Value ''
    Never paste it into chat, a document, or a recording.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-06\Copy-L06ConnectorPassword.ps1
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows DPAPI is required.' }
$path = Join-Path $env:LOCALAPPDATA 'SC500/Lesson06/connector-admin.credential.xml'
if (-not (Test-Path -LiteralPath $path)) { throw 'No saved connector credential. Deploy the Connector lab first.' }
$credential = Import-Clixml -LiteralPath $path
try { Set-Clipboard -Value $credential.GetNetworkCredential().Password }
finally { $credential = $null }
Write-Host 'Copied for RDP as contosoadmin. Paste it only into the Remote Desktop prompt, then run: Set-Clipboard -Value ""'
