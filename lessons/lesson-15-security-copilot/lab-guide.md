# Lesson 15 lab guide

**Microsoft Security Copilot for Cloud and AI Defenders**

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
| 1 | [Microsoft Security Copilot](https://securitycopilot.microsoft.com) |
| 2 | [Microsoft Defender, Incidents](https://security.microsoft.com/incidents) |
| 3 | [Microsoft Defender, Advanced hunting](https://security.microsoft.com/v2/advanced-hunting) |

## Demo 1: Capacity, owners, and what Copilot reads

### 1.1 Read the workspace, its capacity, and usage

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Security Copilot, page 1 (Microsoft Security Copilot).

1. Switch to **page 1** (**Microsoft Security Copilot**). Click the **home menu**, then **Owner settings**.
2. Confirm the workspace name **default** in the breadcrumb, then the capacity **copilot-secops-shared-eastus-001** with **1** provisioned SCU and overage **0**.
3. Confirm the **data sharing** setting, then the **file upload** setting.
4. Confirm **audit logging**. Leave every setting as it is.

### 1.2 Read the capacity's clock

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **copilot-secops-shared-eastus-001**, then **guarded by the reaper**.
3. Confirm **Deleted by**, then the **billed clock hours** line.
4. Confirm the **Reaper** line and its last run.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Invoke-L15CopilotDemo.ps1 -Mode Capacity
```

### 1.3 Read the usage dashboard

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Security Copilot, page 1 (Microsoft Security Copilot).

1. Switch to **page 1**. Click the **home menu**, then **Usage monitoring**.
2. Confirm the **copilot-secops-shared-eastus-001** tab, then the bar chart.
3. Confirm the table's **Copilot experience** and **Plugins used** columns.
4. Confirm **Export**, and leave it alone.

### 1.4 Read the role assignments and my data access

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Security Copilot, page 1 (Microsoft Security Copilot).

1. Click the **home menu**, then **Role assignment**.
2. Under **Owner**, confirm the Entra roles that inherit owner, starting with **Global Administrator**.
3. Under **Contributor**, confirm **Recommended Microsoft Security roles**.

### 1.5 Read my data roles

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm the Entra roles marked as inheriting **Copilot owner**.
3. Confirm the Azure role on **log-secops-shared-eastus2-001**.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Invoke-L15CopilotDemo.ps1 -Mode Access
```

### 1.6 Walk through adding a contributor

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Security Copilot, page 1 (Microsoft Security Copilot).

1. On **Role assignment**, click **Add members**.
2. Confirm the search box for a person or a group, then open the role list and confirm **Copilot contributor**.
3. Click **Cancel**. Nobody gets added.

## Demo 2: Point Copilot at ServiceHub's data

### 2.1 Turn on the plugins and set the workspace

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Security Copilot, page 1 (Microsoft Security Copilot).

1. On page 1's home page, click the **Sources** icon in the prompt bar.
2. Under **Microsoft**, turn on **Microsoft Defender XDR**, **Microsoft Sentinel**, **Microsoft Entra** and **Microsoft Intune**.
3. Click the gear on **Microsoft Sentinel**. In **Default workspace name**, type `log-secops-shared-eastus2-001`, then click **Save**.

### 2.2 Look at a partner plugin's sign-in

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Security Copilot, page 1 (Microsoft Security Copilot).

1. In **Sources**, scroll to **Non-Microsoft** and find **ServiceNow Security Incident Response**.
2. Open its setup and confirm the **client ID** and **client secret** fields.
3. Close the setup without saving.

### 2.3 Read who can add custom plugins

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Security Copilot, page 1 (Microsoft Security Copilot).

1. Click the **home menu**, then **Plugin settings**.
2. Confirm **Who can add and manage their own custom plugins?**, set to **Owners only**.
3. Confirm the preinstalled plugins, each with **All users** or **Owners only** beside it.

### 2.4 Upload the ServiceHub KQL plugin

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Security Copilot, page 1 (Microsoft Security Copilot).

1. Click the **Sources** icon in the prompt bar, scroll to **Custom**, then click **Upload plugin**.
2. Choose **Just me**, then **Security Copilot plugin**.
3. Click **Upload file**, pick `C:\github\sc500\lab\infra\lesson-15\plugins\Contoso-ServiceHub-KQL.yaml`, then click **Add**.
4. Fill **TenantId**, **SubscriptionId**, **ResourceGroupName** and **WorkspaceName** from your lesson's config.json, then click **Setup**.
5. Turn on **Contoso ServiceHub investigation** in the **Custom** list.

### 2.5 Ask the plugin and check its rows

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Security Copilot, page 1 (Microsoft Security Copilot).

1. Click in the **prompt bar** on **page 1**.
2. Type `Using Contoso ServiceHub investigation, which accounts exported parts data without a service case in the last 7 days, and from which IP addresses?` and press **Enter**.
3. Confirm **Contoso ServiceHub investigation** in the process log.
4. Confirm **svc-servicehub-parts** with **198.51.100.77**, then **svc-parts-replication** with **192.0.2.20**.

### 2.6 Check the same rows outside Copilot

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **GetServiceHubExportsWithoutCase** and its rows.
3. Confirm **svc-servicehub-parts** and **198.51.100.77**, then **svc-parts-replication**.
4. If it reads **actively refused** from api.loganalytics.io, run it again; a second try usually connects.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Invoke-L15CopilotDemo.ps1 -Mode Plugin
```

## Demo 3: Work the case, then close it

### 3.1 Summarize the incident and read guided response

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 2 (Microsoft Defender, Incidents).

1. Switch to **page 2** (**Microsoft Defender, Incidents**). Open incident **99**.
2. In the **Copilot** pane, wait for the **incident summary**, then confirm where the attack started, the assets, and the timeline.
3. Confirm the guided response card's **triage**, **containment**, **investigation** and **remediation** groups.
4. Read the recommendations, and leave every action button alone.

### 3.2 Run the Security Analyst Agent and visit the Store

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 3 (Microsoft Defender, Advanced hunting).

1. Switch to **page 3** (**Microsoft Defender, Advanced hunting**). In the **Copilot** pane, click **More actions**, then **Switch to Security Analyst Agent**.
2. Open the chat you started before the demo from the agent's history.
3. Confirm the ranked actors, then the evidence behind the top finding.

### 3.3 Look at a Store agent

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Security Copilot, page 1 (Microsoft Security Copilot).

1. Switch to **page 1**. Click the **home menu**, then **Security Store**.
2. Search `triage` and open a partner agent.
3. Confirm the **publisher**, the **pricing**, and the **permissions** it needs. Leave **Get agent** alone.

### 3.4 Read the case's records

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **Incident 1** and Defender incident **99**.
3. Confirm the **export row**, the **IP entity**, and the **playbook comment**, each with its source.
4. If it reads **actively refused** from api.loganalytics.io, run it again; a second try usually connects.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-15\Invoke-L15CopilotDemo.ps1 -Mode Case
```

### 3.5 Verify the claims and close the case

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 2 (Microsoft Defender, Incidents).

1. Switch to **page 2**, on incident **99**. Click **Activity log**, then the comment box.
2. Type `Copilot review: no-case export and source IP supported by the export row and IP entity. File left the network: can't check, no egress data. Phished user: not supported, the actor is a service account.` and click **Comment**.
3. Click **Manage incident**. Set **Status** to **Resolved**.
4. Set **Classification** to **Informational, expected activity**, then click **Save**.

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
