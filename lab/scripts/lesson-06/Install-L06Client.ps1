<#
.SYNOPSIS Installs the signed Global Secure Access client and checks the isolated VM.
.DESCRIPTION
    Device join and software installation are machine preparation. You must still sign in
    interactively; this script cannot prove a user tunnel or device compliance.
#>
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'L06.Common.ps1')
[void](Assert-L06Context)
$rg=$script:L06Config.clientResourceGroup;$vm=$script:L06Names.clientVm
$group=Invoke-L06Az @('group','show','-n',$rg)
if($group.tags.managedBy -ne $script:L06Config.managedBy){throw 'Unowned client group.'}
Assert-L06GuestReady -ResourceGroup $rg -VmName $vm
$guest=@'
$ErrorActionPreference='Stop'
$client='C:\Program Files\Global Secure Access Client\TrayApp\GlobalSecureAccessClient.exe'
$join=(& dsregcmd /status | Out-String)
if($join -notmatch 'AzureAdJoined\s*:\s*YES'){throw 'The client is not Microsoft Entra joined.'}
if($join -notmatch 'TenantId\s*:\s*<your-tenant-id>'){throw 'Wrong joined tenant.'}
if(-not(Test-Path -LiteralPath $client)){
    $installer=Join-Path $env:TEMP 'GlobalSecureAccessClient.exe'
    Invoke-WebRequest 'https://aka.ms/GlobalSecureAccess-windows' -OutFile $installer -UseBasicParsing
    $sig=Get-AuthenticodeSignature $installer
    if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation'){throw 'Invalid Microsoft installer signature.'}
    $process=Start-Process $installer -ArgumentList '/quiet','/norestart' -Wait -PassThru -WindowStyle Hidden
    if($process.ExitCode -notin 0,3010){throw "Installer exit $($process.ExitCode)"}
    Write-Output "INSTALL_EXIT=$($process.ExitCode)"
}
if(-not(Test-Path -LiteralPath $client)){throw 'Client executable missing.'}
# A SYSTEM-context probe before user sign-in is a negative control, not a tunnel test.
$socket=[Net.Sockets.TcpClient]::new()
try{$pending=$socket.ConnectAsync('10.60.16.4',8080);$direct=$pending.Wait(5000) -and $socket.Connected}catch{$direct=$false}finally{$socket.Dispose()}
$services=@(Get-Service | Where-Object DisplayName -match 'Global Secure Access' | Select-Object Name,Status)
[pscustomobject]@{AzureAdJoined=$true;TenantId='<your-tenant-id>';Version=(Get-Item $client).VersionInfo.FileVersion;DirectAppReachableBeforeUserSignIn=$direct;Services=$services;UserTunnel='Not tested - interactive sign-in required'} | ConvertTo-Json -Depth 5
if($direct){throw 'The isolated client unexpectedly reaches the private app before user sign-in.'}
Write-Output 'L06_CLIENT_PREPARED'
'@
$result=Invoke-L06Az @('vm','run-command','invoke','-g',$rg,'-n',$vm,'--command-id','RunPowerShellScript','--scripts',$guest)
[void](Write-L06Evidence 'client-install' $result)
$messages=($result.value.message -join "`n")
if($messages -notmatch 'L06_CLIENT_PREPARED'){throw 'Client preparation did not finish. Inspect private evidence.'}
$result.value | Select-Object code,message | Format-List
