<#
.SYNOPSIS
    Demo 13.1: the ServiceHub Sentinel workspace and who may do what in it.
.DESCRIPTION
    Modes:
      Workspace  Read-only. The workspace, its retention and daily cap, and Sentinel's onboarding state.
      Roles      Read-only. Reads the built-in Microsoft Sentinel role definitions from Azure and
                 evaluates a short list of operations against each role's Actions and NotActions.
      Assign     WRITE. Gives the SC500 SOC Analysts group Microsoft Sentinel Responder and the SC500
                 SOC Engineers group Microsoft Sentinel Contributor, at the resource group. Idempotent.
                 Reset-L13Lab.ps1 removes both assignments.
      Access     Read-only. Reads back the role assignments at the resource group and evaluates the
                 same operations for each group.
    Nobody signs in as an analyst here: no analyst account exists in the tenant, so Access evaluates
    the role definitions. It does not observe a refused request.
.PARAMETER Mode Workspace, Roles, Assign, or Access.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13WorkspaceDemo.ps1 -Mode Roles
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Workspace', 'Roles', 'Assign', 'Access')][string]$Mode)
. (Join-Path $PSScriptRoot 'L13.Common.ps1')
$cfg = $script:L13Config
[void](Assert-L13Context)
$lab = Get-L13Outputs
$rgScope = "/subscriptions/$($cfg.subscriptionId)/resourceGroups/$($cfg.resourceGroup)"

# The operations Katie's team argues about. Each is a real Azure RBAC action string.
$ops = [ordered]@{
    'Query workspace data'          = 'Microsoft.OperationalInsights/workspaces/query/read'
    'Read incidents'                = 'Microsoft.SecurityInsights/incidents/read'
    'Update an incident'            = 'Microsoft.SecurityInsights/incidents/write'
    'Create an analytics rule'      = 'Microsoft.SecurityInsights/alertRules/write'
    'Create an automation rule'     = 'Microsoft.SecurityInsights/automationRules/write'
    'Configure a data connector'    = 'Microsoft.SecurityInsights/dataConnectors/write'
    'Install a content hub package' = 'Microsoft.SecurityInsights/contentPackages/write'
}

function Get-L13RoleDefinition {
    param([Parameter(Mandatory)][string]$Id)
    $d = Invoke-L13Rest -Path "/subscriptions/$($cfg.subscriptionId)/providers/Microsoft.Authorization/roleDefinitions/$Id`?api-version=2022-04-01"
    return [pscustomobject]@{ name = $d.properties.roleName; permissions = @($d.properties.permissions) }
}

switch ($Mode) {
    'Workspace' {
        $ws = Invoke-L13Rest -Path "$($lab.workspaceId)?api-version=2023-09-01"
        $onb = Invoke-L13Rest -AllowNotFound -Path "$($lab.workspaceId)/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2024-09-01"
        $out = [ordered]@{
            workspace = $ws.name; region = $ws.location; resourceGroup = $cfg.resourceGroup
            pricing = $ws.properties.sku.name; retentionDays = $ws.properties.retentionInDays
            dailyCapGb = $ws.properties.workspaceCapping.dailyQuotaGb
            resourceContextAccess = [bool](Get-L13Value $ws 'properties.features.enableLogAccessUsingOnlyResourcePermissions')
            sentinelEnabled = [bool]$onb
            created = $ws.properties.createdDate
        }
        [pscustomobject]$out | Format-List | Out-Host
        Write-Host 'Inspect the portal connection: Defender portal, System, Settings, Microsoft Sentinel, Workspaces.'
        Write-L13Verdict -Rows @(
            [ordered]@{ Check = 'Sentinel enabled'; Expected = 'True'; Observed = "$($out.sentinelEnabled)" }
            [ordered]@{ Check = 'Retention days'; Expected = "$($cfg.workspace.retentionInDays)"; Observed = "$($out.retentionDays)" }
            [ordered]@{ Check = 'Region'; Expected = $cfg.location; Observed = $out.region }
        )
        [void](Write-L13Evidence 'workspace' $out)
    }
    'Roles' {
        $roles = @($cfg.roles.sentinelReader, $cfg.roles.sentinelResponder, $cfg.roles.sentinelContributor) | ForEach-Object { Get-L13RoleDefinition -Id $_ }
        $rows = foreach ($k in $ops.Keys) {
            $row = [ordered]@{ Operation = $k }
            foreach ($r in $roles) { $row[$r.name -replace '^Microsoft Sentinel ', ''] = if (Test-L13RoleAction @($r) $ops[$k]) { 'Allowed' } else { 'Not allowed' } }
            [pscustomobject]$row
        }
        $rows | Format-Table -AutoSize | Out-Host
        [void](Write-L13Evidence 'roles' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); operations = $ops; matrix = $rows; definitions = $roles }))
    }
    'Assign' {
        $pairs = @(
            @{ group = $cfg.names.analystGroup; role = $cfg.roles.sentinelResponder; roleName = 'Microsoft Sentinel Responder' },
            @{ group = $cfg.names.engineerGroup; role = $cfg.roles.sentinelContributor; roleName = 'Microsoft Sentinel Contributor' }
        )
        $made = foreach ($p in $pairs) {
            $gid = @(Invoke-L13Az -NoSubscription @('ad', 'group', 'list', '--filter', "displayName eq '$($p.group)'", '--query', '[].id'))[0]
            if (-not $gid) { throw "Group $($p.group) not found. Run Deploy-L13Lab.ps1 -Deploy." }
            $existing = @(Invoke-L13Az @('role', 'assignment', 'list', '--assignee', $gid, '--scope', $rgScope, '--role', $p.role, '--query', '[].id'))
            if ($existing.Count -eq 0) {
                $a = Invoke-L13Az @('role', 'assignment', 'create', '--assignee-object-id', $gid, '--assignee-principal-type', 'Group', '--scope', $rgScope, '--role', $p.role)
                # The create output carries the role's ID, not its name, so the name comes from the pair.
                Write-Host "Assigned $($p.roleName) to $($p.group) at $($cfg.resourceGroup)."
                [pscustomobject]@{ group = $p.group; role = $p.roleName; id = $a.id; created = $true }
            }
            else { Write-Host "$($p.group) already holds $($p.roleName) here."; [pscustomobject]@{ group = $p.group; role = $p.roleName; id = $existing[0]; created = $false } }
        }
        [void](Write-L13Evidence 'roles-assign' ([ordered]@{ assignedUtc = [DateTime]::UtcNow.ToString('o'); scope = $rgScope; assignments = $made }))
    }
    'Access' {
        $defs = @{}
        $rows = foreach ($g in @($cfg.names.analystGroup, $cfg.names.engineerGroup)) {
            $gid = @(Invoke-L13Az -NoSubscription @('ad', 'group', 'list', '--filter', "displayName eq '$g'", '--query', '[].id'))[0]
            $assigned = @(Invoke-L13Az @('role', 'assignment', 'list', '--assignee', $gid, '--scope', $rgScope, '--include-inherited'))
            $grantedRoles = @(); $names = @()
            foreach ($a in $assigned) {
                $id = ($a.roleDefinitionId -split '/')[-1]
                if (-not $defs[$id]) { $defs[$id] = Get-L13RoleDefinition -Id $id }
                $grantedRoles += $defs[$id]; $names += $defs[$id].name
            }
            $row = [ordered]@{ Group = $g; Roles = if ($names) { ($names -join ', ') } else { '(none)' } }
            foreach ($k in $ops.Keys) { $row[$k] = if (Test-L13RoleAction $grantedRoles $ops[$k]) { 'Allowed' } else { 'Not allowed' } }
            [pscustomobject]$row
        }
        $rows | Format-List | Out-Host
        $an = $rows | Where-Object Group -EQ $cfg.names.analystGroup; $en = $rows | Where-Object Group -EQ $cfg.names.engineerGroup
        Write-L13Verdict -Rows @(
            [ordered]@{ Check = 'Analysts: update an incident'; Expected = 'Allowed'; Observed = $an.'Update an incident' }
            [ordered]@{ Check = 'Analysts: create an analytics rule'; Expected = 'Not allowed'; Observed = $an.'Create an analytics rule' }
            [ordered]@{ Check = 'Engineers: create an analytics rule'; Expected = 'Allowed'; Observed = $en.'Create an analytics rule' }
            [ordered]@{ Check = 'Engineers: install a content hub package'; Expected = 'Allowed'; Observed = $en.'Install a content hub package' }
        )
        Write-Host 'Evaluated ARM Actions from group role definitions, not effective user access. No analyst sign-in, deny-assignment, condition or data-action test was performed.'
        [void](Write-L13Evidence 'roles-access' ([ordered]@{ readUtc = [DateTime]::UtcNow.ToString('o'); scope = $rgScope; access = $rows }))
    }
}
