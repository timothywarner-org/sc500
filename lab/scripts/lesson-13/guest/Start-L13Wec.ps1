<#
.SYNOPSIS
    Starts the collector after VM boot and returns its actual readiness.
.DESCRIPTION
    VM power state does not prove that the delayed Event Collector service has started.
#>
$ErrorActionPreference = 'Stop'
Set-Service Wecsvc -StartupType Automatic
Start-Service Wecsvc
(Get-Service Wecsvc).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
wecutil gr '__SUBSCRIPTION__'
if ($LASTEXITCODE -ne 0) { throw 'The WEF subscription could not be read after service startup.' }
'L13_WEC_RUNNING'
