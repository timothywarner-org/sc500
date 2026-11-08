/*
Purpose: worked SQL Managed Instance audit configuration for HOL 4.3.
Execution boundary: Microsoft-documented example, syntax checked locally; no MI is
deployed in this course lab. Run only on a designated training Managed Instance.
Why EXTERNAL_MONITOR: keeps credentials out of the script. The accompanying Bicep
diagnostic setting must route SQLSecurityAuditEvents to the chosen workspace.
Source: https://learn.microsoft.com/azure/azure-sql/managed-instance/auditing-configure
*/
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'ContosoServiceHubAudit')
    CREATE SERVER AUDIT [ContosoServiceHubAudit] TO EXTERNAL_MONITOR;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'ContosoServiceHubLogins')
    CREATE SERVER AUDIT SPECIFICATION [ContosoServiceHubLogins]
    FOR SERVER AUDIT [ContosoServiceHubAudit]
    ADD (FAILED_LOGIN_GROUP), ADD (SUCCESSFUL_LOGIN_GROUP)
    WITH (STATE = ON);
GO
-- The destination and the event selection are separate objects; both must be enabled.
ALTER SERVER AUDIT [ContosoServiceHubAudit] WITH (STATE = ON);
ALTER SERVER AUDIT SPECIFICATION [ContosoServiceHubLogins] WITH (STATE = ON);
GO
SELECT name, type_desc, is_state_enabled FROM sys.server_audits
WHERE name = N'ContosoServiceHubAudit';
SELECT name, is_state_enabled FROM sys.server_audit_specifications
WHERE name = N'ContosoServiceHubLogins';
SELECT name, status_desc FROM sys.dm_server_audit_status
WHERE name = N'ContosoServiceHubAudit';
GO
/* Evidence procedure: make a new successful SQL connection and a deliberately failed
   SQL login, then query SQLSecurityAuditEvents in the selected workspace. A running
   audit alone does not prove records reached the destination. For object-level reads,
   add a database audit specification in the intended database, bound to this audit.
   Preserve records before disabling this lesson's named specification and audit. */
