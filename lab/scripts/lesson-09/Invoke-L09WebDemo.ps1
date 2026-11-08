<#
.SYNOPSIS
    Demo 9.3 for SC-500 Lesson 9: App Service security, and Web Application Firewall on
    Application Gateway and Front Door. Needs the edge part (Deploy-L09Edge.ps1 -Deploy).

.DESCRIPTION
    Read-only except for the requests it sends.
      App         The origin's settings: HTTPS only, TLS, FTP, basic-auth publishing, and its
                  access restrictions (default deny, the gateway's address, this Front Door).
      Direct      Request the origin's default host name directly (expect 403).
      Gateway     Through Application Gateway: a normal request (expect 200), then one carrying a
                  SQL injection pattern in the query string (expect 403 from the WAF).
      FrontDoor   Through Front Door: a normal request (expect 200), then a scanner path that the
                  custom rule blocks (expect 403).
      Logs        The WAF log rows from the last hour: Application Gateway's AGWFirewallLogs and
                  Front Door's WAF log.
      All         App, Direct, Gateway, FrontDoor, Logs.

.PARAMETER Mode
    One of the modes above.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-09\Invoke-L09WebDemo.ps1 -Mode Gateway
#>
[CmdletBinding()]
param([ValidateSet('App', 'Direct', 'Gateway', 'FrontDoor', 'Logs', 'All')][string]$Mode = 'All')
. (Join-Path $PSScriptRoot 'L09.Common.ps1')
[void](Assert-L09Context)
$cfg = $script:L09Config
$lab = Get-L09Outputs -Lab Retained
$edge = Get-L09Outputs -Lab Edge
$webId = Get-L09ResourceId 'Microsoft.Web/sites' $edge.webApp

if ($Mode -in 'App', 'All') {
    Write-Host "== $($edge.webApp)"
    $site = Invoke-L09Rest -Path "$webId`?api-version=2024-04-01"
    $web = Invoke-L09Rest -Path "$webId/config/web?api-version=2024-04-01"
    $ftp = Invoke-L09Rest -Path "$webId/basicPublishingCredentialsPolicies/ftp?api-version=2024-04-01"
    $scm = Invoke-L09Rest -Path "$webId/basicPublishingCredentialsPolicies/scm?api-version=2024-04-01"
    $rules = @($web.properties.ipSecurityRestrictions | Where-Object { $_.name -ne 'Deny all' } | ForEach-Object {
        $hdr = Get-L09Value $_ 'headers'
        $extra = if ($hdr) { ' with X-Azure-FDID = this profile' } else { '' }
        '{0} {1} {2}{3}' -f $_.priority, $_.action, $_.ipAddress, $extra })
    $row = [ordered]@{
        'HTTPS only' = $site.properties.httpsOnly; 'Minimum TLS' = $web.properties.minTlsVersion; FTP = $web.properties.ftpsState
        'Basic-auth publishing (FTP / SCM)' = '{0} / {1}' -f $(if ($ftp.properties.allow) { 'allowed' } else { 'off' }), $(if ($scm.properties.allow) { 'allowed' } else { 'off' })
        'Remote debugging' = $web.properties.remoteDebuggingEnabled; 'Managed identity' = $site.identity.type
        'Inbound default' = $web.properties.ipSecurityRestrictionsDefaultAction; 'Inbound rules' = ($rules -join '; ')
    }
    [void](Write-L09Evidence 'web-app' $row)
    [pscustomobject]$row | Format-List | Out-String -Width 220 | Out-Host
}

if ($Mode -in 'Direct', 'All') {
    $r = Invoke-L09Http -Uri "https://$($edge.webHost)/" -TimeoutSec 60
    '{0} {1} requesting {2} directly' -f $r.Status, $r.Reason, $edge.webHost | Out-Host
    [void](Write-L09Evidence 'web-direct' ($r | Select-Object Status, Reason, Body, AtUtc))
}

# Send what a browser sends. In rehearsal, a bare scripted request to the gateway's IP address
# was blocked even with no attack in it: rule 920350 (Host header is a numeric IP, Warning = 3)
# plus rule 920320 (Missing User Agent header, Notice = 2) reached the anomaly threshold of 5.
# A User-Agent header keeps the clean request at 3, so only the real attack crosses the line.
$browser = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) SC500-Lesson09'; 'Accept' = 'text/html' }

if ($Mode -in 'Gateway', 'All') {
    $base = "http://$($edge.gatewayIp)"
    $ok = Invoke-L09Http -Uri "$base/?part=PN-1001" -Headers $browser -TimeoutSec 60
    '{0} {1}  GET /?part=PN-1001 through Application Gateway' -f $ok.Status, $ok.Reason | Out-Host
    $attack = Invoke-L09Http -Uri "$base/?part=PN-1001'%20OR%20'1'='1" -Headers $browser -TimeoutSec 60
    "{0} {1}  GET /?part=PN-1001' OR '1'='1 through Application Gateway" -f $attack.Status, $attack.Reason | Out-Host
    [void](Write-L09Evidence 'web-gateway' ([ordered]@{ normal = ($ok | Select-Object Status, Reason, AtUtc); sqlInjection = ($attack | Select-Object Status, Reason, Body, AtUtc) }))
}

if ($Mode -in 'FrontDoor', 'All') {
    $base = "https://$($edge.frontDoorHost)"
    $ok = Invoke-L09Http -Uri "$base/?part=PN-1001" -Headers $browser -TimeoutSec 60
    '{0} {1}  GET /?part=PN-1001 through Front Door' -f $ok.Status, $ok.Reason | Out-Host
    $probe = Invoke-L09Http -Uri "$base/.env" -Headers $browser -TimeoutSec 60
    '{0} {1}  GET /.env through Front Door' -f $probe.Status, $probe.Reason | Out-Host
    [void](Write-L09Evidence 'web-frontdoor' ([ordered]@{ normal = ($ok | Select-Object Status, Reason, AtUtc); scannerPath = ($probe | Select-Object Status, Reason, Body, AtUtc) }))
}

if ($Mode -in 'Logs', 'All') {
    $ws = Invoke-L09Az @('monitor', 'log-analytics', 'workspace', 'show', '--ids', $lab.workspaceId, '--query', 'customerId')
    Write-Host '== Application Gateway WAF log (AGWFirewallLogs), last hour'
    # One row per request: every rule that matched it, and whether the request was blocked.
    $q1 = "AGWFirewallLogs | where TimeGenerated > ago(1h) | summarize Actions = strcat_array(make_set(Action), ' '), Rules = strcat_array(make_set(RuleId), ' ') by At = bin(TimeGenerated, 1s), RequestUri | order by At desc | take 8"
    $r1 = @(Invoke-L09Az -NoSubscription @('monitor', 'log-analytics', 'query', '--workspace', $ws, '--analytics-query', $q1))
    # The Azure CLI adds a TableName column to every row; it says nothing about the request.
    if ($r1.Count) { $r1 | Select-Object * -ExcludeProperty TableName | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Out-Host } else { Write-Host '(no rows yet; the first rows took a few minutes to arrive)' }
    Write-Host '== Front Door WAF log, last hour'
    # Front Door writes to AzureDiagnostics, whose _s columns exist only after the first row
    # lands. column_ifexists keeps the query valid on a brand-new workspace.
    $q2 = "AzureDiagnostics | where TimeGenerated > ago(1h) | where Category == 'FrontDoorWebApplicationFirewallLog' | project TimeGenerated, Action = column_ifexists('action_s', ''), Rule = column_ifexists('ruleName_s', ''), RequestUri = column_ifexists('requestUri_s', '') | order by TimeGenerated desc | take 8"
    $r2 = @(Invoke-L09Az -NoSubscription @('monitor', 'log-analytics', 'query', '--workspace', $ws, '--analytics-query', $q2))
    if ($r2.Count) { $r2 | Select-Object * -ExcludeProperty TableName | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Out-Host } else { Write-Host '(no rows yet; Front Door rows took about two minutes to arrive)' }
    [void](Write-L09Evidence 'web-waf-logs' ([ordered]@{ appGateway = $r1; frontDoor = $r2 }))
}
