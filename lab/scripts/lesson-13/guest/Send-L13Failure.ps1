<#
    Runs on vm-wec-shared-001 through Run Command. Makes one failed network sign-in for a local
    account name that doesn't exist, which Windows records as Security event 4625. The attempted
    password is a random GUID made on the spot; no real credential is involved.
#>
$ErrorActionPreference = 'Stop'
$user = '__PROBE__'
Add-Type -Namespace SC500 -Name Native -MemberDefinition @'
[DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool LogonUser(string user, string domain, string password, int logonType, int provider, out System.IntPtr token);
'@
$token = [IntPtr]::Zero
$ok = [SC500.Native]::LogonUser($user, '.', [guid]::NewGuid().ToString(), 3, 0, [ref]$token)
$utc = [DateTime]::UtcNow.ToString('o')
Start-Sleep -Seconds 3
$e = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = (Get-Date).AddMinutes(-2) } -MaxEvents 5 |
    Where-Object { $_.Properties[5].Value -eq $user } | Select-Object -First 1
"attempted $user at $utc; LogonUser returned $ok"
if ($e) { "Security 4625 RecordId $($e.RecordId) at $($e.TimeCreated.ToUniversalTime().ToString('o'))" } else { 'no 4625 found yet' }
Start-Sleep -Seconds 20
$f = Get-WinEvent -FilterHashtable @{ LogName = 'ForwardedEvents'; StartTime = (Get-Date).AddMinutes(-3) } -MaxEvents 20 -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -eq 4625 -and $_.Message -match [regex]::Escape($user) } | Select-Object -First 1
if ($f) { "ForwardedEvents 4625 RecordId $($f.RecordId) at $($f.TimeCreated.ToUniversalTime().ToString('o'))" } else { 'no forwarded copy yet' }
