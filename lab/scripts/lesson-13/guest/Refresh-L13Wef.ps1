<# .SYNOPSIS Refreshes the lab source after WEC startup and reads the actual subscription query. #>
$ErrorActionPreference = 'Stop'
# The source service must refresh its subscription after the collector becomes available.
Restart-Service WinRM -Force
Start-Service Wecsvc
wecutil gs '__SUBSCRIPTION__' /f:xml
Start-Sleep -Seconds 45
Get-WinEvent -LogName 'Microsoft-Windows-Forwarding/Operational' -MaxEvents 4 | ForEach-Object {
    "$($_.Id) $($_.TimeCreated.ToUniversalTime().ToString('o')) $($_.Message -replace '\s+',' ')"
}
