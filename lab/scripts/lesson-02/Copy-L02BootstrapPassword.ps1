<#
.SYNOPSIS
Copies Garth's protected bootstrap password locally for your first-sign-in step.
.DESCRIPTION
Human-only helper. Never prints a credential. After first sign-in, the bootstrap is obsolete.
Clear the clipboard after pasting and never paste a credential into chat.
#>
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Windows DPAPI is required.'}
# A successful first-login password change makes the retained bootstrap unusable.
$obsoletePath=Join-Path $env:LOCALAPPDATA 'SC500/Lesson02/garth.credential.obsolete.json'
if(Test-Path -LiteralPath $obsoletePath){
    throw 'Garth changed the bootstrap password. Use his current sign-in method; the obsolete password was not copied.'
}
$credential=Import-Clixml -LiteralPath (Join-Path $env:LOCALAPPDATA 'SC500/Lesson02/garth.credential.xml')
try{Set-Clipboard -Value $credential.GetNetworkCredential().Password}finally{$credential=$null}
Write-Host 'Bootstrap copied locally. Paste only into Garth sign-in, then clear with Set-Clipboard -Value "".'
