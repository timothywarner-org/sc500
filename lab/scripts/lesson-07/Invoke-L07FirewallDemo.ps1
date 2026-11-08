<#
.SYNOPSIS
    Demo 7.1: read what Azure Firewall Premium did to ServiceHub's traffic, then enforce.

.DESCRIPTION
    Status   Reads production's /status page through the DNAT rule. The production VM's probe
             sends the lesson's test traffic out through the firewall once a minute; this shows
             what each request got back, including who issued the HTTPS certificate the VM saw.
    Idps     Sends two requests from this workstation to the published status page: one normal,
             one with Microsoft's IDPS test user agent (HaxerMen). This is Microsoft's documented
             test, aimed at our own lab server, never a public one.
    Enforce  Raises threat intelligence and IDPS to Alert and deny, and sets the test
             signature 2032081 to Deny. The firewall applies a policy change within minutes.
    Logs     Queries the AZFW* resource-specific tables in the lesson workspace for the last 30 minutes.
             New rows usually take a few minutes to arrive.
    Reset-L07Lab.ps1 returns the policy to baseline.

.PARAMETER Mode
    Status, Idps, Enforce, or Logs.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-07\Invoke-L07FirewallDemo.ps1 -Mode Status
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Status', 'Idps', 'Enforce', 'Logs')][string]$Mode)
. (Join-Path $PSScriptRoot 'L07.Common.ps1')
[void](Assert-L07Context)
$cfg = $script:L07Config
$lab = Get-L07DeploymentOutput

function Test-Published([string]$UserAgent) {
    # One request to the published page. A timeout or reset here is the result, not a failure.
    $uri = "http://$($lab.firewallPublicIpAddress):$($cfg.ports.app)/"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Uri $uri -UserAgent $UserAgent -TimeoutSec 15 -SkipHttpErrorCheck
        return [pscustomobject]@{ UserAgent = $UserAgent; Outcome = "HTTP $([int]$r.StatusCode)"; Body = "$($r.Content)".Trim(); Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
    }
    catch {
        $kind = if ($_.Exception.Message -match '(?i)timeout|timed out|canceled') { 'timed out' } elseif ($_.Exception.Message -match '(?i)reset|forcibly closed|ended prematurely|closed') { 'connection reset' } else { $_.Exception.GetType().Name }
        return [pscustomobject]@{ UserAgent = $UserAgent; Outcome = $kind; Body = ''; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
    }
}

switch ($Mode) {
    'Status' {
        $s = Get-L07Status
        [void](Write-L07Evidence 'status-page' $s)
        "Production probe results from $($s.generatedUtc) (UTC). This page was served to $($s.servedTo), a firewall instance address: DNAT traffic is SNATed."
        $s.results | ForEach-Object {
            $detail = if ($_.PSObject.Properties['status']) { "HTTP $($_.status) $($_.body)" } elseif ($_.PSObject.Properties['error']) { $_.error } else { '' }
            [pscustomobject]@{
                Test   = $_.name
                Saw    = $_.outcome
                Issuer = if ($_.PSObject.Properties['certificateIssuer']) { $_.certificateIssuer } else { '' }
                Detail = if ($detail.Length -gt 90) { $detail.Substring(0, 90) + '...' } else { $detail }
            }
        } | Format-Table -AutoSize -Wrap | Out-String -Width 200
    }
    'Idps' {
        $results = @(
            Test-Published 'ContosoOperator/1.0'
            Test-Published $cfg.tests.idpsTestUserAgent
        )
        [void](Write-L07Evidence 'idps-test' $results)
        $results | Format-Table -AutoSize -Wrap | Out-String -Width 200
    }
    'Enforce' {
        & (Join-Path $PSScriptRoot 'Set-L07Policy.ps1') -State Enforced
        $fw = Get-L07Firewall
        if ($fw) {
            $deadline = (Get-Date).AddMinutes(10)
            do {
                Start-Sleep -Seconds 20
                $state = (Invoke-L07Az @('resource', 'show', '--ids', $fw.id)).properties.provisioningState
                Write-Host "Firewall provisioning state: $state"
            } while ($state -ne 'Succeeded' -and (Get-Date) -lt $deadline)
            if ($state -ne 'Succeeded') { throw "Firewall update did not finish: $state. Don't present this as enforced." }
        }
        else { Write-Host 'No firewall is deployed; the policy is enforced and will apply when one attaches.' }
    }
    'Logs' {
        $queries = [ordered]@{
            'Application rules (AZFWApplicationRule)' = 'AZFWApplicationRule | where TimeGenerated > ago(30m) | summarize Requests = count(), Last = max(TimeGenerated) by Fqdn, TargetUrl, Action, Rule, ActionReason, IsTlsInspected | order by Last desc | take 12'
            'Network rules (AZFWNetworkRule)'         = 'AZFWNetworkRule | where TimeGenerated > ago(30m) | summarize Flows = count(), Last = max(TimeGenerated) by SourceIp, DestinationIp, DestinationPort, Action, Rule, ActionReason | order by Last desc | take 8'
            'DNAT (AZFWNatRule)'                      = 'AZFWNatRule | where TimeGenerated > ago(30m) | summarize Flows = count(), Last = max(TimeGenerated) by SourceIp, DestinationIp, DestinationPort, TranslatedIp, TranslatedPort, Rule | order by Last desc | take 5'
            'Threat intelligence (AZFWThreatIntel)'   = 'AZFWThreatIntel | where TimeGenerated > ago(30m) | summarize Hits = count(), Last = max(TimeGenerated) by Fqdn, DestinationIp, Action, ThreatDescription | order by Last desc | take 5'
            'IDPS (AZFWIdpsSignature)'                = 'AZFWIdpsSignature | where TimeGenerated > ago(30m) | summarize Hits = count(), Last = max(TimeGenerated) by SourceIp, DestinationIp, DestinationPort, Action, SignatureId, Description | order by Last desc | take 5'
        }
        $all = [ordered]@{}
        foreach ($title in $queries.Keys) {
            $rows = @(Invoke-L07LogQuery -Query $queries[$title] -Timespan 'PT1H')
            $all[$title] = $rows
            "== $title"
            if ($rows.Count) { $rows | Format-Table -AutoSize -Wrap | Out-String -Width 220 } else { '(no rows yet; allow a few minutes after traffic)' }
        }
        [void](Write-L07Evidence 'firewall-logs' $all)
    }
}
