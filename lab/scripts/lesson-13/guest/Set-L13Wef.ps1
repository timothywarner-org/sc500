<#
    Runs on vm-wec-shared-001 as SYSTEM through Run Command (Deploy-L13Lab.ps1 -Deploy or -GuestsOnly).
    Makes this VM a Windows Event Collector and also its own event source, so one VM shows the whole
    WEF route. A production design has many sources and a separate collector; this lab collapses them
    onto one VM to keep cost down. Idempotent: the subscription is recreated.

    Route: a source-initiated subscription. Microsoft's default subscription SDDL grants Domain
    Computers and "the local Network Service group (for the local forwarder)", so the local
    forwarder, running as Network Service, can subscribe to its own collector. This VM isn't domain
    joined, so the Domain Computers entry is dropped: its SID alias doesn't resolve off a domain,
    and the second rehearsal failed with "The security ID structure is invalid." Authenticated
    Users is added because a local forwarder off a domain may not present the Network Service SID;
    the VM has no inbound rule, so nothing outside it can reach port 5985. The source side is the
    SubscriptionManager policy value, written to the policy registry key the Group Policy setting
    "Configure target Subscription Manager" writes.

    Why the URL ACL: on Windows Server 2019 and later with more than 3.5 GB of RAM, WinRM and the
    Windows Event Collector run in separate service hosts, and the default ACL on
    http://+:5985/wsman/ admits only WinRM, so sources connect but no events arrive. Microsoft's
    fix (support article "Events are not forwarded if the collector is running Windows Server",
    KB 4494462) re-adds the URL with both service SIDs. The third rehearsal showed exactly that
    symptom: the source enumerated its subscription every minute and ForwardedEvents stayed empty.

    Why not collector-initiated: the first two rehearsals (Kerberos, then Negotiate with a local
    reader account) both failed with "The request is not supported" for the localhost source on
    this non-domain VM. That attempt's local reader account is removed here if it exists.
#>
$ErrorActionPreference = 'Stop'
$name = '__SUBSCRIPTION__'
winrm quickconfig -quiet | Out-Null
wecutil qc /q | Out-Null

# Forwarding the Security log needs NETWORK SERVICE in Event Log Readers (the local forwarder's identity).
if (-not (Get-LocalGroupMember -Group 'Event Log Readers' -Member 'NT AUTHORITY\NETWORK SERVICE' -ErrorAction SilentlyContinue)) {
    Add-LocalGroupMember -Group 'Event Log Readers' -Member 'NT AUTHORITY\NETWORK SERVICE'
}
# Clean up the earlier collector-initiated attempt's account.
if (Get-LocalUser -Name 'sc500-wef-reader' -ErrorAction SilentlyContinue) { Remove-LocalUser -Name 'sc500-wef-reader' }

$xml = @"
<Subscription xmlns="http://schemas.microsoft.com/2006/03/windows/events/subscription">
  <SubscriptionId>$name</SubscriptionId>
  <SubscriptionType>SourceInitiated</SubscriptionType>
  <Description>SC-500 Lesson 13: failed sign-ins forwarded to ForwardedEvents</Description>
  <Enabled>true</Enabled>
  <Uri>http://schemas.microsoft.com/wbem/wsman/1/windows/EventLog</Uri>
  <ConfigurationMode>Custom</ConfigurationMode>
  <Delivery Mode="Push">
    <Batching><MaxItems>1</MaxItems><MaxLatencyTime>10000</MaxLatencyTime></Batching>
    <PushSettings><Heartbeat Interval="60000"/></PushSettings>
  </Delivery>
  <Query><![CDATA[<QueryList><Query Id="0"><Select Path="Security">__QUERY__</Select></Query></QueryList>]]></Query>
  <ReadExistingEvents>false</ReadExistingEvents>
  <TransportName>HTTP</TransportName>
  <ContentFormat>RenderedText</ContentFormat>
  <Locale Language="en-US"/>
  <LogFile>ForwardedEvents</LogFile>
  <AllowedSourceNonDomainComputers></AllowedSourceNonDomainComputers>
  <AllowedSourceDomainComputers>O:NSG:BAD:P(A;;GA;;;NS)(A;;GA;;;AU)S:</AllowedSourceDomainComputers>
</Subscription>
"@
$path = Join-Path $env:TEMP 'sc500-l13-subscription.xml'
Set-Content -LiteralPath $path -Value $xml -Encoding Unicode
# wecutil writes warnings to stderr, which Windows PowerShell 5.1 turns into terminating errors under Stop.
$ErrorActionPreference = 'Continue'
if ((wecutil es) -contains $name) { wecutil ds $name | Out-Null }
$created = cmd /c "wecutil cs `"$path`" 2>&1"
Remove-Item -LiteralPath $path
"--- create: $(if ($created) { $created -join ' ' } else { 'saved' })"

# ---- Collector side: let the Windows Event Collector service use the WinRM URL (KB 4494462) --------
$winrmSid = 'S-1-5-80-569256582-2953403351-2909559716-1301513147-412116970'
$wecSid = 'S-1-5-80-4059739203-877974739-1245631912-527174227-2996563517'
$acl = cmd /c "netsh http show urlacl url=http://+:5985/wsman/"
if (($acl -join ' ') -notmatch $wecSid) {
    cmd /c "netsh http delete urlacl url=http://+:5985/wsman/" | Out-Null
    cmd /c "netsh http add urlacl url=http://+:5985/wsman/ sddl=D:(A;;GX;;;$winrmSid)(A;;GX;;;$wecSid)" | Out-Null
    "--- URL ACL: added the Windows Event Collector service SID to http://+:5985/wsman/"
}
else { "--- URL ACL: already includes the Windows Event Collector service" }

# ---- Source side: point the local forwarder at this collector -----------------------------------
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager'
New-Item -Path $key -Force | Out-Null
# localhost keeps the forwarder's connection on the loopback path, where Network Service can
# authenticate without a domain; the computer name routes through the NIC like a remote source.
Set-ItemProperty -Path $key -Name '1' -Value "Server=http://localhost:5985/wsman/SubscriptionManager/WEC,Refresh=60"
Restart-Service WinRM -Force
Restart-Service Wecsvc -Force
Start-Sleep -Seconds 75
"--- subscriptions"; wecutil es
"--- runtime status"; wecutil gr $name
"--- Wecsvc: $((Get-Service Wecsvc).Status); WinRM: $((Get-Service WinRM).Status)"
$op = Get-WinEvent -LogName 'Microsoft-Windows-Forwarding/Operational' -MaxEvents 3 -ErrorAction SilentlyContinue
foreach ($e in $op) { "--- forwarding log $($e.Id): $($e.Message -replace '\s+', ' ')" }
