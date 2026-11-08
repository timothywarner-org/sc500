<#
.SYNOPSIS
Starts one on-demand backup of the already-protected Lesson 3 runner and preserves its job identifier.
.DESCRIPTION
Refuses a second request while a backup job is running. Retains the recovery point for
seven days; no backup data or protection is removed by this command.
#>
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
$lab=Get-L03Outputs
$base=@('--resource-group',$script:L03Config.resourceGroup,'--vault-name',$lab.recoveryVaultName,'--subscription',$script:L03Config.subscriptionId)
$jobs=@(Invoke-L03Az (@('backup','job','list')+$base))
if(@($jobs|Where-Object {$_.properties.operation -eq 'Backup' -and $_.properties.status -eq 'InProgress'}).Count){throw 'A backup is already running; inspect it before starting another.'}
$items=@(Invoke-L03Az (@('backup','item','list')+$base+@('--backup-management-type','AzureIaasVM')))
$item=@($items|Where-Object {$_.properties.sourceResourceId -ieq $lab.runnerId})
if($item.Count -ne 1){throw 'Exactly one protected Lesson 3 runner is required.'}
$container=($item[0].id -split '/protectionContainers/')[1].Split('/')[0]
$retain=[DateTime]::UtcNow.AddDays(7).ToString('dd-MM-yyyy')
$result=Invoke-L03Az (@('backup','protection','backup-now')+$base+@('--container-name',$container,'--item-name',$item[0].name,'--retain-until',$retain,'--backup-management-type','AzureIaasVM'))
[void](Write-L03Evidence 'backup-started' $result)
$result|Select-Object name,properties|ConvertTo-Json -Depth 10
