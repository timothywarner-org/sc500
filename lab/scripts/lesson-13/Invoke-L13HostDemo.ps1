<#
.SYNOPSIS
    Demo 13.3: Syslog and CEF through the Linux forwarder, and Windows Security events directly and
    through Windows Event Forwarding (WEF).
.DESCRIPTION
    Modes:
      Routes   Read-only. The four host collection rules: facilities and levels, XPath filters, and
               which VM each is attached to. Plus each VM's newest agent heartbeat.
      Send     WRITE (log messages only). Sends one labeled Syslog message and one labeled CEF message
               through the forwarder's listener on port 514. The marker is saved for Trace.
      Failure  WRITE (one failed sign-in). Makes one failed network sign-in on the collector for an
               account name that doesn't exist (Security event 4625), then checks that WEF copied it
               into ForwardedEvents.
      Wef      Read-only. The WEF subscription's runtime status on the collector.
      Trace    Read-only. Finds the latest marker in Syslog and CommonSecurityLog, checks that the CEF
               message did not also land in Syslog, and finds the 4625 in SecurityEvent and
               WindowsEvent, with each row's ingestion delay.
    The VMs must be running (Start-L13Lab.ps1). Every message is synthetic and says so.
.PARAMETER Mode Routes, Send, Failure, Wef, or Trace.
.PARAMETER Hours How far back Trace looks. Default 6.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13HostDemo.ps1 -Mode Send
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Routes', 'Send', 'Failure', 'Wef', 'Trace')][string]$Mode,
    [ValidateRange(1, 168)][int]$Hours = 6
)
. (Join-Path $PSScriptRoot 'L13.Common.ps1')
$cfg = $script:L13Config
[void](Assert-L13Context)
$lab = Get-L13Outputs
$n = $cfg.names
$markerFile = Join-Path $script:L13State 'last-marker.json'

switch ($Mode) {
    'Routes' {
        $rows = foreach ($id in @($lab.dcrSyslogId, $lab.dcrCefId, $lab.dcrWindowsSecurityId, $lab.dcrForwardedId)) {
            $d = Invoke-L13Rest -Path "$id`?api-version=2023-03-11"
            $assoc = Invoke-L13Rest -Path "$id/associations?api-version=2023-03-11"
            $src = $d.properties.dataSources
            $filter = if (Get-L13Value $src 'syslog') {
                @($src.syslog | ForEach-Object { "$($_.facilityNames -join ',') at $($_.logLevels[0]) and above" }) -join '; '
            } else { @($src.windowsEventLogs | ForEach-Object { $_.xPathQueries -join '; ' }) -join '; ' }
            [pscustomobject][ordered]@{
                Rule = $d.name; Stream = (@($d.properties.dataFlows | ForEach-Object { $_.streams }) -join ', ')
                Filter = $filter
                AttachedTo = (@($assoc.value | ForEach-Object { ($_.id -split '/providers/Microsoft.Insights')[0].Split('/')[-1] }) -join ', ')
            }
        }
        $rows | Format-List | Out-Host
        $hb = Invoke-L13Query -Lab $lab -Kql 'Heartbeat | where TimeGenerated > ago(1d) | summarize Newest = max(TimeGenerated) by Computer, Category, OSType' -Timespan 'P1D'
        $hb | ForEach-Object { Write-Host ("Agent heartbeat: {0} ({1}, {2}) newest {3:u}" -f $_.Computer, $_.OSType, $_.Category, ([DateTime]$_.Newest).ToUniversalTime()) }
        [void](Write-L13Evidence 'host-routes' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); rules = $rows; heartbeats = $hb }))
    }
    'Send' {
        Assert-L13Running -Vm $n.forwarderVm
        $marker = 'SC500-L13-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
        $out = Invoke-L13Guest -Vm $n.forwarderVm -Name 'Send-L13Syslog.sh' -Values @{ MARKER = $marker }
        Write-Host $out
        $state = if (Test-Path -LiteralPath $markerFile) { Get-Content -LiteralPath $markerFile -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
        $state.syslogMarker = $marker; $state.syslogSentUtc = [DateTime]::UtcNow.ToString('o')
        $state | ConvertTo-Json | Set-Content -LiteralPath $markerFile -Encoding utf8
        [void](Write-L13Evidence 'send-syslog' ([ordered]@{ marker = $marker; sentUtc = $state.syslogSentUtc; guest = $out }))
    }
    'Failure' {
        Assert-L13Running -Vm $n.collectorVm
        $failureStart = [DateTime]::UtcNow.ToString('o')
        $out = Invoke-L13Guest -Vm $n.collectorVm -Name 'Send-L13Failure.ps1' -Values @{ PROBE = $cfg.collection.probeAccount }
        Write-Host $out
        $state = if (Test-Path -LiteralPath $markerFile) { Get-Content -LiteralPath $markerFile -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
        $state.failureUtc = $failureStart
        $state | ConvertTo-Json | Set-Content -LiteralPath $markerFile -Encoding utf8
        [void](Write-L13Evidence 'send-failure' ([ordered]@{ account = $cfg.collection.probeAccount; sentUtc = $state.failureUtc; guest = $out }))
    }
    'Wef' {
        Assert-L13Running -Vm $n.collectorVm
        $out = Invoke-L13Guest -Vm $n.collectorVm -Name 'Get-L13WefStatus.ps1' -Values @{ SUBSCRIPTION = $n.wefSubscription }
        Write-Host $out
        [void](Write-L13Evidence 'wef-status' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); guest = $out }))
    }
    'Trace' {
        if (-not (Test-Path -LiteralPath $markerFile)) { throw 'No marker yet. Run -Mode Send and -Mode Failure first.' }
        $state = Get-Content -LiteralPath $markerFile -Raw | ConvertFrom-Json
        $m = $state.syslogMarker; $probe = $cfg.collection.probeAccount
        $failureStart = Get-L13Value $state 'failureUtc'
        # No failed-sign-in receipt means no Windows proof, even if an old matching account exists.
        if (-not $failureStart) { $failureStart = [DateTime]::UtcNow.ToString('o') }
        $q = [ordered]@{
            Syslog            = "Syslog | where TimeGenerated > ago($($Hours)h) | where SyslogMessage has '$m' | project TimeGenerated, Ingested = ingestion_time(), Computer, Facility, SeverityLevel, ProcessName, Detail = SyslogMessage"
            CommonSecurityLog = "CommonSecurityLog | where TimeGenerated > ago($($Hours)h) | where DeviceCustomString1 == '$m' | project TimeGenerated, Ingested = ingestion_time(), Computer, DeviceVendor, DeviceProduct, Activity, Detail = strcat(SourceIP, ' ', SourceUserName)"
            CefInSyslog       = "Syslog | where TimeGenerated > ago($($Hours)h) | where SyslogMessage has '$m' and SyslogMessage has 'CEF' | project TimeGenerated, Ingested = ingestion_time(), Computer, Detail = SyslogMessage"
            SecurityEvent     = "SecurityEvent | where TimeGenerated > ago($($Hours)h) and TimeGenerated >= datetime($failureStart) | where EventID == 4625 and TargetUserName =~ '$probe' | project TimeGenerated, Ingested = ingestion_time(), Computer, EventID, Detail = strcat(TargetUserName, ' logon type ', LogonType, ' ', Status)"
            WindowsEvent      = "WindowsEvent | where TimeGenerated > ago($($Hours)h) and TimeGenerated >= datetime($failureStart) | where EventID == 4625 and tostring(EventData.TargetUserName) =~ '$probe' | project TimeGenerated, Ingested = ingestion_time(), Computer, EventID, Detail = strcat(tostring(EventData.TargetUserName), ' via ', Channel)"
        }
        $all = [ordered]@{}
        foreach ($k in $q.Keys) {
            $rows = @(Invoke-L13Query -Lab $lab -Kql $q[$k] -Timespan "PT$($Hours)H")
            $all[$k] = $rows
            $newest = $rows | Sort-Object { [DateTime]$_.TimeGenerated } -Descending | Select-Object -First 1
            if ($newest) {
                $t = [DateTime]$newest.TimeGenerated; $i = [DateTime]$newest.Ingested
                Write-Host ("{0,-18} rows {1}  newest {2:u}  delay {3:N1} min  {4}  {5}" -f $k, $rows.Count, $t.ToUniversalTime(), ($i - $t).TotalMinutes, $newest.Computer, $newest.Detail)
            }
            else { Write-Host ("{0,-18} rows 0" -f $k) }
        }
        Write-Host "Marker $m; failed sign-in account $probe. CefInSyslog should stay at 0."
        $seen = { param($k) if (@($all[$k]).Count) { 'found' } else { 'none' } }
        Write-L13Verdict -Rows @(
            [ordered]@{ Check = 'Syslog message in Syslog'; Expected = 'found'; Observed = (& $seen 'Syslog') }
            [ordered]@{ Check = 'CEF message in CommonSecurityLog'; Expected = 'found'; Observed = (& $seen 'CommonSecurityLog') }
            [ordered]@{ Check = 'CEF message also in Syslog'; Expected = 'none'; Observed = (& $seen 'CefInSyslog') }
            [ordered]@{ Check = '4625 in SecurityEvent (direct)'; Expected = 'found'; Observed = (& $seen 'SecurityEvent') }
            # config.json collection.wefExpected: 'none' while the single-VM WEF lane is an open item (November 6).
            [ordered]@{ Check = '4625 in WindowsEvent (WEF)'; Expected = $(if (Get-L13Value $cfg 'collection.wefExpected') { $cfg.collection.wefExpected } else { 'found' }); Observed = (& $seen 'WindowsEvent') }
        )
        [void](Write-L13Evidence 'trace-hosts' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); marker = $m; probeAccount = $probe; rows = $all }))
    }
}
