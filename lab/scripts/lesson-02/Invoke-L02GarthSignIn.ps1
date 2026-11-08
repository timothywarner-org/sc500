<#
.SYNOPSIS
Opens an interactive Garth sign-in targeting the Lesson 2 API.
.DESCRIPTION
Uses MSAL's browser authorization-code flow with PKCE, isolated in-memory cache,
and the existing public client. Checks identity and records the requested resource without displaying tokens.
Does not call a running API backend or prove Conditional Access enforcement.
#>
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$state=Join-Path $root '.azure/lesson-02/identity-state.json'
$python='C:/Program Files/Microsoft SDKs/Azure/CLI2/python.exe'
& $python (Join-Path $PSScriptRoot 'garth_signin.py') $state
if($LASTEXITCODE){throw 'Garth sign-in did not complete. No password or token was captured.'}
