<#
.SYNOPSIS
Runs the synthetic object lifecycle or restricted workload request in the private L3 VM.
.DESCRIPTION
Object administration uses a separate bootstrap identity and a temporary vault-scoped grant.
The system identity remains a Secrets User. Tokens and values never appear in output.
.EXAMPLE
./scripts/lesson-03/Invoke-L03VaultDemo.ps1 -Mode Objects -KeepRunning
#>
param([ValidateSet('Objects','ReadBoundary')][string]$Mode='ReadBoundary',[switch]$KeepRunning)
. (Join-Path $PSScriptRoot 'L03.Cloud.Common.ps1')
Assert-L03Context
[void](Assert-L03Group $script:L03Config.resourceGroup)
$lab=Get-L03Outputs
$grantId=$null
$completed=$false
try {
    & (Join-Path $PSScriptRoot 'Start-L03Lab.ps1')
    if($Mode -eq 'Objects'){
        $role=@(Invoke-L03Az @('role','definition','list','--name','Key Vault Administrator','--subscription',$script:L03Config.subscriptionId))
        if($role.Count -ne 1){throw 'The bootstrap role did not resolve.'}
        $existing=@(Invoke-L03Az @('role','assignment','list','--assignee',$lab.bootstrapPrincipalId,'--scope',$lab.vaultId,'--role',$role[0].name,'--subscription',$script:L03Config.subscriptionId))
        if($existing.Count){throw 'A bootstrap admin grant already exists. Inspect and remove it before a new run.'}
        $grant=Invoke-L03Az @('role','assignment','create','--assignee-object-id',$lab.bootstrapPrincipalId,'--assignee-principal-type','ServicePrincipal','--role',$role[0].name,'--scope',$lab.vaultId,'--subscription',$script:L03Config.subscriptionId)
        $grantId=$grant.id
    }
    $source=Get-Content (Join-Path $PSScriptRoot 'vault_probe.py') -Raw
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($source))
    if($lab.vaultName -notmatch '^kv-sc500-l03-[a-z0-9]+$' -or $lab.bootstrapClientId -notmatch '^[a-f0-9-]{36}$'){throw 'Unexpected deployment bindings.'}
    # The shell payload carries source and public identifiers only. Credentials are fetched inside the guest.
    $guest="printf '%s' '$encoded' | base64 -d > /tmp/sc500-l03-vault-probe.py`npython3 /tmp/sc500-l03-vault-probe.py --vault $($lab.vaultName) --mode $Mode --bootstrap-client-id $($lab.bootstrapClientId)`n"
    $guestPath=Join-Path $script:L03Root '.azure/lesson-03/guest-command.sh'
    [IO.File]::WriteAllText($guestPath,$guest,[Text.UTF8Encoding]::new($false))
    $result=Invoke-L03Az @('vm','run-command','invoke','--resource-group',$script:L03Config.resourceGroup,'--name',$script:L03Config.vmName,'--command-id','RunShellScript','--scripts',('@'+$guestPath),'--subscription',$script:L03Config.subscriptionId)
    $messages=($result.value|ForEach-Object message)-join "`n"
    $match=[regex]::Match($messages,'SC500_L03_RESULT=(\{[^\r\n]+\})')
    if(-not $match.Success){[void](Write-L03Evidence 'guest-no-result' $result);throw 'Guest output did not contain a completed result. Inspect private run-command evidence.'}
    $probe=$match.Groups[1].Value|ConvertFrom-Json -Depth 20
    [void](Write-L03Evidence ('vault-'+$Mode) $probe)
    $expected=if($Mode -eq 'Objects'){$lab.bootstrapPrincipalId}else{$lab.runnerPrincipalId}
    if($probe.principalId -ne $expected){throw 'The request used an unexpected managed identity.'}
    $probe|ConvertTo-Json -Depth 20
    if(-not $probe.success){throw 'The private-vault demonstration did not pass. Read the recorded operation result.'}
    $completed=$true
} finally {
    try {
        if($grantId){[void](Invoke-L03Az @('role','assignment','delete','--ids',$grantId,'--subscription',$script:L03Config.subscriptionId));Write-Host 'Temporary bootstrap grant removed.'}
    } finally {
        # A failed permission cleanup must not also prevent compute and egress cleanup.
        if(-not $KeepRunning -or -not $completed){& (Join-Path $PSScriptRoot 'Stop-L03Lab.ps1')}
    }
}
