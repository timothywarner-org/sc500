<#
.SYNOPSIS
Shows the exact REST configuration request and current state for each database plan.
.DESCRIPTION
This is a worked configuration example. It performs GET only. The printed PUT
would enable a paid plan at subscription scope, so it is not silently submitted.
The course already retains these plans; undeployed database families remain examples.
.EXAMPLE
./scripts/lesson-04/Show-L04DatabasePlanConfiguration.ps1
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L04.Common.ps1')
[void](Assert-L04Context)
$families=[ordered]@{
    SqlServers='Azure SQL Database and SQL Managed Instance'
    OpenSourceRelationalDatabases='Azure Database for PostgreSQL and MySQL flexible servers'
    CosmosDbs='Azure Cosmos DB for NoSQL'
    SqlServerVirtualMachines='SQL Server on machines (comparison)'
}
$rows=foreach($plan in $families.Keys){
    $path="/subscriptions/$($script:L04Config.subscriptionId)/providers/Microsoft.Security/pricings/$($plan)?api-version=2024-01-01"
    $current=Invoke-L04Arm -Path $path
    # Show the intended mutation separately from observed state, without changing billing.
    [pscustomobject]@{family=$families[$plan];plan=$plan;method='PUT (worked example, not sent)';uri='https://management.azure.com'+$path;body=@{properties=@{pricingTier='Standard'}};observedTier=$current.properties.pricingTier}
}
[void](Write-L04Evidence 'database-plan-worked-configuration' @{checkedAt=[DateTime]::UtcNow.ToString('o');requestsSubmitted=$false;plans=$rows})
$rows|ConvertTo-Json -Depth 6
