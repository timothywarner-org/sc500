<#
.SYNOPSIS
    Demo 4.3 helper: Azure SQL platform settings, a rejected SQL-authentication login, an
    Entra-authenticated query, and the audit records those attempts produced.

.DESCRIPTION
    Modes:
      Settings    Read back public network access, firewall rules, minimum TLS, the Entra
                  admin and Entra-only flag, TDE, and server auditing (read-only).
      SqlLogin    Attempt a SQL-authentication login. Entra-only authentication rejects it
                  (error 18456), whatever the user name or password.
      EntraQuery  Connect with a Microsoft Entra token and run a query that also proves
                  Entra-only mode and TDE from inside the database.
      Audit       Query Log Analytics for the last hour of SQLSecurityAuditEvents. Records
                  usually arrive 3 to 10 minutes after the activity.

.PARAMETER Mode
    One of the modes above.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-04\Invoke-L04SqlDemo.ps1 -Mode SqlLogin

.NOTES
    No password is stored anywhere. SqlLogin generates a throwaway random one in memory,
    because the point is that no password can work, not that this one is wrong.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Settings', 'SqlLogin', 'EntraQuery', 'Audit')]
    [string]$Mode
)
. (Join-Path $PSScriptRoot 'L04.Common.ps1')
[void](Assert-L04Context)
$lab = Get-L04Outputs
$rg = $script:L04Config.resourceGroup

switch ($Mode) {
    'Settings' {
        $s = Invoke-L04Az @('sql', 'server', 'show', '--name', $lab.sqlServer, '--resource-group', $rg)
        $fw = @(Invoke-L04Az @('sql', 'server', 'firewall-rule', 'list', '--server', $lab.sqlServer, '--resource-group', $rg))
        $tde = Invoke-L04Az @('sql', 'db', 'tde', 'show', '--server', $lab.sqlServer, '--database', $lab.sqlDatabase, '--resource-group', $rg)
        $tdeKey = Invoke-L04Az @('sql', 'server', 'tde-key', 'show', '--server', $lab.sqlServer, '--resource-group', $rg)
        $audit = Invoke-L04Az @('sql', 'server', 'audit-policy', 'show', '--name', $lab.sqlServer, '--resource-group', $rg)
        $rows = [ordered]@{
            'Public network access'            = $s.publicNetworkAccess
            'Firewall rules'                   = (($fw | ForEach-Object { '{0} ({1})' -f $_.name, $_.startIpAddress }) -join ', ')
            'Allow Azure services'             = $(if ($fw.name -contains 'AllowAllWindowsAzureIps') { 'Yes' } else { 'No' })
            'Minimum TLS version'              = $s.minimalTlsVersion
            'Microsoft Entra admin'            = $s.administrators.login
            'Microsoft Entra-only authentication' = $s.administrators.azureAdOnlyAuthentication
            'TDE on servicehub-records'        = $tde.state
            'TDE protector'                    = $tdeKey.serverKeyType
            'Server auditing'                  = $audit.state
            'Audit to Log Analytics'           = $audit.isAzureMonitorTargetEnabled
            'Audited action groups'            = ($audit.auditActionsAndGroups -join ', ')
            'Server region'                    = $s.location
        }
        $rows.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Setting = $_.Key; Value = $_.Value } } | Format-Table -AutoSize -Wrap | Out-String -Width 160 | Write-Host
        [void](Write-L04Evidence 'sql-settings' $rows)
    }
    'SqlLogin' {
        # A random password that no one ever sees. Entra-only mode rejects the login before
        # any password comparison would matter.
        $pw = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
        $result = [ordered]@{ Time = [DateTime]::UtcNow.ToString('HH:mm:ss') + 'Z'; Request = 'SQL authentication login servicehub_app'; Result = $null }
        try {
            [void](Invoke-Sqlcmd -ServerInstance $lab.sqlFqdn -Database $lab.sqlDatabase -Username 'servicehub_app' -Password $pw -Query 'SELECT 1' -Encrypt Mandatory -ConnectionTimeout 20 -ErrorAction Stop)
            $result.Result = 'ALLOWED (unexpected: Entra-only authentication is not in effect)'
        }
        catch {
            $msg = ($_.Exception.Message -replace '\s+', ' ').Trim()
            $result.Result = 'REJECTED ' + $msg
        }
        finally { $pw = $null }
        [pscustomobject]$result | Format-List | Out-String -Width 160 | Write-Host
        [void](Write-L04Evidence 'sql-sqllogin' $result)
        if ($result.Result -notmatch '(Azure Active Directory|Microsoft Entra).*only authentication is enabled') {
            throw 'The login did not return the Entra-only rejection reason. A generic login failure is insufficient evidence.'
        }
    }
    'EntraQuery' {
        $token = Get-L04SqlToken
        try {
            $q = @'
SELECT SUSER_SNAME() AS SignedInAs,
       SERVERPROPERTY('IsExternalAuthenticationOnly') AS EntraOnly,
       (SELECT CASE encryption_state WHEN 3 THEN 'Encrypted' ELSE CAST(encryption_state AS varchar(4)) END
          FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID()) AS TdeState,
       (SELECT COUNT(*) FROM dbo.ServiceRecords) AS ServiceRecords;
SELECT RequestId, Customer, Status FROM dbo.ServiceRecords ORDER BY RequestId;
'@
            $sets = Invoke-Sqlcmd -ServerInstance $lab.sqlFqdn -Database $lab.sqlDatabase -AccessToken $token -Query $q -Encrypt Mandatory -OutputAs DataTables -ErrorAction Stop
            $sets[0] | Format-List | Out-String | Write-Host
            $sets[1] | Format-Table -AutoSize | Out-String | Write-Host
            [void](Write-L04Evidence 'sql-entraquery' @{ identity = $sets[0].Rows[0].SignedInAs; entraOnly = $sets[0].Rows[0].EntraOnly; tde = $sets[0].Rows[0].TdeState; rows = $sets[0].Rows[0].ServiceRecords })
        }
        finally { $token = $null }
    }
    'Audit' {
        $kql = @"
AzureDiagnostics
| where Category == 'SQLSecurityAuditEvents' and TimeGenerated > ago(1h)
| where LogicalServerName_s == '$($lab.sqlServer)'
| project TimeGenerated, action_name_s, succeeded_s, server_principal_name_s, database_name_s, statement_s = substring(statement_s, 0, 70)
| order by TimeGenerated desc
| take 15
"@
        $r = Invoke-L04Az -NoSubscription @('monitor', 'log-analytics', 'query', '--workspace', $lab.workspaceCustomerId, '--analytics-query', $kql)
        if (-not $r -or @($r).Count -eq 0) { Write-Host 'No audit records yet. Resource logs usually arrive 3 to 10 minutes after the activity.' }
        else { @($r) | Format-Table TimeGenerated, action_name_s, succeeded_s, server_principal_name_s, statement_s -AutoSize -Wrap | Out-String -Width 180 | Write-Host }
        [void](Write-L04Evidence 'sql-audit' @($r))
    }
}
