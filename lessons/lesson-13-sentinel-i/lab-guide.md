# Lesson 13 lab guide

**Microsoft Sentinel I: Workspace, Connectors, and Log Ingestion**

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
| 1 | [Microsoft Defender, Settings](https://security.microsoft.com/securitysettings) |
| 2 | rg-secops-shared-eastus2, Access control (IAM): `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-secops-shared-eastus2/users` |
| 3 | rg-secops-shared-eastus2, Overview: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-secops-shared-eastus2/overview` |
| 4 | [Microsoft Defender, Advanced hunting](https://security.microsoft.com/v2/advanced-hunting) |

## Demo 1: Connect, assign, and follow one record

### 1.1 Check the connection, assign the roles

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 1 (Microsoft Defender, Settings).

1. Switch to **page 1** (**Microsoft Defender, Settings**). Click **Microsoft Sentinel**, then **Workspaces**.
2. Confirm **log-secops-shared-eastus2-001**: **Connected**, then **Primary**.
3. If the page offers **Connect a workspace** instead, connect the workspace first, then come back to this step.

### 1.2 Give the analysts Responder

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (rg-secops-shared-eastus2, Access control (IAM)).

1. Switch to **page 2** (**rg-secops-shared-eastus2, Access control (IAM)**). Click **Add**, then **Add role assignment**.
2. Search `Microsoft Sentinel Responder`, select it, then click **Next**.
3. Click **Select members**, choose **SC500 SOC Analysts**, click **Select**, then **Review + assign** twice.

### 1.3 Give the engineers Contributor, then read both

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the first command below.
2. Confirm **SC500 SOC Analysts already holds Microsoft Sentinel Responder here**, then the **Assigned** line for the engineers.
3. Run the next command below.
4. Confirm the analysts' **Update an incident: Allowed** and **Create an analytics rule: Not allowed**.
5. Confirm the **What this run proves** table at the bottom. Every row should read **as expected**. If one says **DIFFERENT**, say what you see and why.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13WorkspaceDemo.ps1 -Mode Assign
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13WorkspaceDemo.ps1 -Mode Access
```

### 1.4 Install a solution, check each source

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 1 (Microsoft Defender, Settings).

1. Switch to **page 1**. In the left menu, click **Microsoft Sentinel**, **Content management**, then **Content hub**.
2. If the workspace selector at the top doesn't read **log-secops-shared-eastus2-001**, select it.
3. Search `Azure Activity`. Select the **Azure Activity** solution, then click **Install**.
4. When it reads **Installed**, click **Manage**. Confirm the **Data connector**, then the **Analytics rule** templates.

### 1.5 Read the connector page

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 1 (Microsoft Defender, Settings).

1. In the left menu, click **Microsoft Sentinel**, **Configuration**, then **Data connectors**.
2. Search `Azure Activity`, select it, then click **Open connector page**.
3. Confirm **Status**, then **Last log received**.

### 1.6 Read each source and its route

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the first command below.
2. Confirm **AzureActivity** and its row count, then read the **SigninLogs**, **AuditLogs** and **OfficeActivity** states aloud.
3. Run the next command below.
4. Confirm **Activity log to workspace: yes**, then the **Microsoft Entra diagnostic setting** line and its slot count.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13ConnectorDemo.ps1 -Mode Sources
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13ConnectorDemo.ps1 -Mode Routes
```

### 1.7 Read what the tenant connectors need

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 1 (Microsoft Defender, Settings).

1. Switch to **page 1**. On **Data connectors**, search `Microsoft Entra ID` and open it. Confirm **Prerequisites**.
2. Search `Microsoft 365`, open it, and confirm **Prerequisites**.
3. Search `Microsoft Defender XDR`, open it, and confirm where it names the connected workspace.
4. Don't select **Connect** on any of them.

### 1.8 Follow one Activity log record

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the first command below.
2. Confirm **returned 2 keys (not shown)**.
3. Run the next command below.
4. Confirm **In the Activity log itself**, then **In the workspace (AzureActivity)**: **Caller**, **Status**, **CorrelationId**, **IngestDelayMin**.
5. Confirm the **What this run proves** table at the bottom. Every row should read **as expected**. If one says **DIFFERENT**, say what you see and why.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13ConnectorDemo.ps1 -Mode Probe
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13ConnectorDemo.ps1 -Mode Trace
```

## Demo 2: Send a message, fail a sign-in, find both

### 2.1 Read the collection rules

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 3 (rg-secops-shared-eastus2, Overview).

1. Switch to **page 3** (**rg-secops-shared-eastus2, Overview**). Click **dcr-syslog-shared-eastus2-001**.
2. In the left menu, under **Configuration**, click **Data sources**. Click **Linux Syslog**.
3. Confirm the five facilities and their minimum level, **Warning**.
4. Close the pane. Under **Configuration**, click **Resources**, and confirm **vm-logfwd-shared-001**.

### 2.2 Send Syslog and CEF through the forwarder

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm the **marker** in the output.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13HostDemo.ps1 -Mode Send
```

### 2.3 Fail a sign-in and trace both routes

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the first command below.
2. Confirm **Security 4625** in the output.
3. Run the next command below.
4. Confirm **RunTimeStatus: Active**.
5. Run the next command below.
6. Confirm **Syslog**, **CommonSecurityLog** with **Contoso ServiceHubGateway**, and **CefInSyslog rows 0**, then **SecurityEvent** and **WindowsEvent rows 0**.
7. Confirm the **What this run proves** table at the bottom. Every row should read **as expected**. If one says **DIFFERENT**, say what you see and why.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13HostDemo.ps1 -Mode Failure
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13HostDemo.ps1 -Mode Wef
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13HostDemo.ps1 -Mode Trace
```

### 2.4 Find the 4625 in the portal

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 4 (Microsoft Defender, Advanced hunting).

1. Switch to **page 4** (**Microsoft Defender, Advanced hunting**). Click **New query**.
2. Type `SecurityEvent | where EventID == 4625 and TargetUserName =~ 'contoso-probe' | take 5`, then click **Run query**.
3. Confirm **Computer**, then **TimeGenerated**.

## Demo 3: Land the audit, set its retention

### 3.1 Read the table and its rule

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 1 (Microsoft Defender, Settings).

1. Switch to **page 1**. In the left menu, click **Microsoft Sentinel**, **Configuration**, then **Tables**.
2. Search `ServiceHubAudit` and select **ServiceHubAudit_CL**.
3. In the details pane, confirm the tier, **Analytics**, then **Analytics retention** and **Total retention**.
4. Switch to **page 3**, click **dcr-appaudit-prod-eastus2-001**, then **JSON View**. Confirm **transformKql** and **outputStream**.

### 3.2 Send the audit batch and find it

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the first command below.
2. Confirm **Posted 4 records** and the **FixtureId**.
3. Run the next command below.
4. If it reads **0 rows landed**, wait a minute and run it again.
5. Confirm **3 rows landed from 4 records sent**, then the row with **case (none)**.
6. Confirm the **What this run proves** table at the bottom. Every row should read **as expected**. If one says **DIFFERENT**, say what you see and why.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13TableDemo.ps1 -Mode Send
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13TableDemo.ps1 -Mode Trace
```

### 3.3 Set how long it stays

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 3 (rg-secops-shared-eastus2, Overview).

1. Switch to **page 3** (**rg-secops-shared-eastus2, Overview**). Click **log-secops-shared-eastus2-001**, then **Settings**, **Tables**. Search `ServiceHubAudit`, click the **...** on **ServiceHubAudit_CL**, then **Manage table**.
2. Confirm **Interactive retention**, **90 days**, and **Total retention period**, **1 year**.
3. Leave the plan on **Analytics** and interactive retention at **90 days**. Set **Total retention period** to **2 years**, then click **Save**.

### 3.4 Read the change back

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **ServiceHubAudit_CL**: **Analytics**, **90**, then total days **730**, next to the workspace default.
3. Confirm the **What this run proves** table at the bottom. Every row should read **as expected**. If one says **DIFFERENT**, say what you see and why.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-13\Invoke-L13TableDemo.ps1 -Mode Retention -ExpectTotalDays 730
```

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
