# Lesson 6 lab guide

**Private Connectivity: Private Link, Private Endpoints, and Microsoft Entra Private Access**

These are the steps from this lesson's demos, in the order the video runs them. Watch a demo, then do it yourself in your own lab. A step that starts with **Confirm** is a check: find that value on your screen and make sure it matches before you move on, the same way a performance-based exam item grades you.

## Before you start

1. Do the [one-time lab setup](../../lab/README.md) once for the whole course.
2. Deploy this lesson's lab with the **Build** scripts on the [lab files page](demos/README.md).
3. Read this lesson's [Before you start](README.md#before-you-start) list for licenses, costs, and lead times.

> **Your values will differ from the video.** Incident numbers, IDs, times, and generated name endings (shown as `<unique>`) come from the course's lab. Names Azure makes unique across all customers end in your name suffix, and values in angle brackets are yours to fill in.

> **Portals change.** If a menu or label has moved since the course was recorded, the video says so where it matters. If a step no longer matches what you see, open an issue with the *Content question or demo issue* template.

## Portal pages

The steps refer to these pages by number. Open each one in its own browser tab.

| Page | Opens |
| --- | --- |
| 1 | Records account `stservicehubrecords<your-name-suffix>`, Networking: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-servicehub-prod-eastus2/providers/Microsoft.Storage/storageAccounts/stservicehubrecords<your-name-suffix>/networking` |
| 2 | Private Link service pl-partsapi-prod-eastus2-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-partsapi-prod-eastus2/providers/Microsoft.Network/privateLinkServices/pl-partsapi-prod-eastus2-001/overview` |
| 3 | [Microsoft Entra admin center, Global Secure Access](https://entra.microsoft.com/) |
| 4 | [Conditional Access policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies) |
| 5 | [Sign-in logs](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/SignIns) |

## Demo 1: Take the records account private

### 1.0 Every step is one mode of this script

**Sign in as:** ADMIN, your admin account. **Where:** VS Code on this workstation.

1. In VS Code, open C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1.
2. Scroll to the switch block and confirm each -Mode as you name it.
3. Confirm the az storage account show line under Settings, the Invoke-WebRequest line under PublicRead, and the az network private-endpoint create line under CreateEndpoint.

### 1.1 The account answers on its public endpoint

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 on this workstation, page 1 (Records account `stservicehubrecords<your-name-suffix>`, Networking).

1. In PowerShell 7, run the command below.
2. Confirm PublicNetworkAccess: Enabled and PrivateEndpoints: none.

```powershell
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1 -Mode Settings
```

### 1.2 The public read works, and both names resolve public

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 on this workstation, page 1 (Records account `stservicehubrecords<your-name-suffix>`, Networking).

1. Run the two commands below, one at a time.
2. Confirm HttpStatus 200 and the record, then at the public address on both Address lines.

```powershell
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1 -Mode PublicRead
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1 -Mode Resolve
```

### 1.3 Create the private endpoint and its zone group

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 on this workstation, page 1 (Records account `stservicehubrecords<your-name-suffix>`, Networking).

1. Run the command below. Wait until it prints the endpoint (about a minute).
2. Confirm Connection: Approved, PrivateIp 10.60.0.68 and the ZoneARecords line.
3. In page 1, refresh Networking and confirm pep-records-blob-001, Approved, in its private endpoint connections.

```powershell
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1 -Mode CreateEndpoint
```

### 1.4 Private for the app, still public for you

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 on this workstation, page 1 (Records account `stservicehubrecords<your-name-suffix>`, Networking).

1. Run the three commands below, one at a time.
2. Confirm 10.60.0.68 on the app VM's Address line and its HTTP 200, then the workstation's HttpStatus 200.

```powershell
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1 -Mode Resolve
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1 -Mode VmRead
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1 -Mode PublicRead
```

### 1.5 Close public network access in the portal

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (Records account `stservicehubrecords<your-name-suffix>`, Networking).

1. Go to page 1: `stservicehubrecords<your-name-suffix>`, Networking.
2. Under Public network access, select Manage, then Disable, then Proceed.
3. Select Save and confirm the notification that the update succeeded.
4. Wait 90 seconds while the storage firewall applies the change.

### 1.6 The public read fails, the private read works

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 on this workstation, page 1 (Records account `stservicehubrecords<your-name-suffix>`, Networking).

1. Run the two commands below, one at a time.
2. Confirm HttpStatus 403 and ErrorCode AuthorizationFailure, then the app VM's HTTP 200 and the record.

```powershell
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1 -Mode PublicRead
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06EndpointDemo.ps1 -Mode VmRead
```

## Demo 2: Connect Fabrikam to the parts API

### 2.0 The Private Link script, opened first

**Sign in as:** ADMIN, your admin account. **Where:** VS Code on this workstation.

1. In VS Code, open C:\github\sc500\lab\scripts\lesson-06\Invoke-L06PlsDemo.ps1.
2. Scroll to the switch block and confirm each -Mode as you name it.
3. Confirm the az network private-link-service show line under Settings, the --manual-request line under RequestConnection, and the curl line under Probe.

### 2.1 Restricted visibility, empty auto-approval

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 on this workstation, page 2 (Private Link service pl-partsapi-prod-eastus2-001).

1. Run the command below.
2. Confirm Alias, the one subscription under Visibility, AutoApproval: none, and NatIp 10.61.0.68.

```powershell
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06PlsDemo.ps1 -Mode Settings
```

### 2.2 Fabrikam asks by alias

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 on this workstation, page 2 (Private Link service pl-partsapi-prod-eastus2-001).

1. Run the command below.
2. Confirm Status: Pending and the endpoint's PrivateIp.

```powershell
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06PlsDemo.ps1 -Mode RequestConnection
```

### 2.3 Pending carries no traffic

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 on this workstation, page 2 (Private Link service pl-partsapi-prod-eastus2-001).

1. Run the two commands below, one at a time.
2. Confirm Pending on both rows, then at Result: BLOCKED from Fabrikam's client.
3. In page 2, select Settings, then Private endpoint connections, and confirm the same request, Pending, with Fabrikam's message.

```powershell
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06PlsDemo.ps1 -Mode Connections
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06PlsDemo.ps1 -Mode Probe
```

### 2.4 Approve this one connection in the portal

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Private Link service pl-partsapi-prod-eastus2-001).

1. Go to page 2: pl-partsapi-prod-eastus2-001, Settings, Private endpoint connections.
2. Select the Pending connection from pep-fabrikam-to-partsapi-001, then Approve.
3. In the comment box, type: Approved by the Contoso platform team for parts lookups.
4. Select Yes, then Refresh until Connection state reads Approved.
5. Wait 30 seconds while the approval reaches the data path.

### 2.5 The parts API sees the NAT IP

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 on this workstation, page 2 (Private Link service pl-partsapi-prod-eastus2-001).

1. Run the two commands below, one at a time.
2. Confirm Result: OPEN and the Answer, Request arrived from 10.61.0.68, then Approved on both rows.

```powershell
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06PlsDemo.ps1 -Mode Probe
pwsh -NoProfile -File C:\github\sc500\lab\scripts\lesson-06\Invoke-L06PlsDemo.ps1 -Mode Connections
```

## Demo 3: Publish ServiceHub with Private Access

### 3.1 Only the pilot group tunnels private traffic

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center, page 3 (Microsoft Entra admin center, Global Secure Access).

1. Go to page 3: Global Secure Access > Connect > Traffic forwarding.
2. In the Private access profile section, under User and group assignments, select View.
3. Confirm CTSO-L06-PrivateAccess-Pilot.

### 3.2 One app, one segment

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center, page 3 (Microsoft Entra admin center, Global Secure Access).

1. Select Global Secure Access > Applications > Enterprise applications > CTSO-L06-ServiceHub-PrivateAccess > Network access properties.
2. Confirm connector group CTSO-L06-Connectors and the one segment, 10.60.16.4, TCP 8080.

### 3.3 The connector is active and outbound only

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center, page 3 (Microsoft Entra admin center, Global Secure Access).

1. Select Global Secure Access > Connect > Connectors.
2. Confirm pnconnector-001, Active, in CTSO-L06-Connectors.

### 3.4 MFA and a compliant device, in report-only

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center, page 4 (Conditional Access policies).

1. Go to page 4: Conditional Access > Policies > CTSO-L06-ServiceHub-MFA-Compliant-ReportOnly.
2. Confirm Target resources (this app) and Users (the pilot group).
3. Confirm Grant: multifactor authentication and a compliant device with Require all the selected controls, then Enable policy: Report-only.

### 3.6 The sign-in log answers the policy question

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center, page 5 (Sign-in logs).

1. Back on the workstation, page 5: Sign-in logs.
2. Select this app's most recent sign-in, then select the Report-only tab.
3. Confirm CTSO-L06-ServiceHub-MFA-Compliant-ReportOnly and its result.

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
