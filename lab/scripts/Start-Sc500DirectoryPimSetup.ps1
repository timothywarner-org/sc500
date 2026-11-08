<#
.SYNOPSIS
Authenticates the Graph PowerShell client with the explicit delegated PIM permission and prepares eligibility.
.DESCRIPTION
The Azure CLI Graph token lacks RoleEligibilitySchedule.ReadWrite.Directory in this tenant.
This requests that specific permission through an interactive administrator sign-in; no app-only credential is created.
The resulting Graph context is process-scoped and is disconnected when this script finishes.
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Sc500.Common.ps1')
Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.36.1 -ErrorAction Stop
try {
    Connect-MgGraph -TenantId $script:Sc500Config.tenantId -Scopes 'RoleEligibilitySchedule.ReadWrite.Directory' -ContextScope Process -UseDeviceCode -NoWelcome
    & (Join-Path $PSScriptRoot 'Initialize-Sc500Pim.ps1') -RoleSystem Entra -UseGraphPowerShellForEligibility
}
finally { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
