<#
.SYNOPSIS
Runs a reviewed Lesson 3 guest script and returns its structured, nonsecret result.
.DESCRIPTION
The source and parameters may contain public lab bindings only. Tokens stay inside
the guest. A nonzero exit or missing result is a failure, never a successful rehearsal.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourcePath,[string[]]$Arguments=@())
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
[void](Assert-L03Group $script:L03Config.resourceGroup)
foreach($arg in $Arguments){if($arg -notmatch '^[A-Za-z0-9_./:=?&;,+%-]+$'){throw 'Guest argument contains an unsupported shell character.'}}
$source=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourcePath).Path)
$encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($source))
$argsText=($Arguments|ForEach-Object {"'$_'"}) -join ' '
# The payload is code plus nonsecret identifiers, so ARM Run Command history contains no credential.
$guest="set -eu`nprintf '%s' '$encoded' | base64 -d > /tmp/sc500-l03-completion.py`npython3 /tmp/sc500-l03-completion.py $argsText`n"
$guestPath=Join-Path $script:L03Root '.azure/lesson-03/completion-command.sh'
[IO.File]::WriteAllText($guestPath,$guest,[Text.UTF8Encoding]::new($false))
$response=Invoke-L03Az @('vm','run-command','invoke','--resource-group',$script:L03Config.resourceGroup,'--name',$script:L03Config.vmName,'--command-id','RunShellScript','--scripts',('@'+$guestPath),'--subscription',$script:L03Config.subscriptionId)
$messages=($response.value|ForEach-Object message)-join "`n"
$match=[regex]::Match($messages,'SC500_L03_COMPLETION=(\{[^\r\n]+\})')
if(-not $match.Success){[void](Write-L03Evidence 'completion-guest-error' $response);throw 'Guest did not return a completed result; inspect private evidence.'}
$record=$match.Groups[1].Value|ConvertFrom-Json -Depth 25
[void](Write-L03Evidence ('completion-'+$record.operation) $record)
$record|ConvertTo-Json -Depth 25
if(-not $record.success){throw 'The requested guest operation did not pass.'}
