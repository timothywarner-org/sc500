# Lesson 10 lab guide

**Secure AI Workloads I: Data Overexposure, Copilot, and Microsoft Entra Agent ID**

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
| 1 | [Microsoft Purview, Data risk assessments](https://purview.microsoft.com/dspm/explorer) |
| 2 | [Microsoft Defender, Security for AI](https://security.microsoft.com/securitysettings/security_for_ai) |
| 3 | [Microsoft Defender, Real-time protection](https://security.microsoft.com/securitysettings/security_for_ai?tabid=realTimeProtection) |
| 4 | [Microsoft 365 admin center](https://admin.microsoft.com/) |
| 5 | [Microsoft Entra admin center, Agent identities](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/AllAgents.MenuView/~/allAgentIds) |
| 6 | [Conditional Access policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies) |
| 7 | [Microsoft Entra admin center, Sign-in logs](https://entra.microsoft.com/) |
| 8 | [Microsoft Defender, AI agents](https://security.microsoft.com/ai-inventory?viewid=agentsView) |
| 9 | [Microsoft Defender, Advanced hunting](https://security.microsoft.com/v2/advanced-hunting) |
| 10 | Storage account `stservicehubkbprod<your-name-suffix>`: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-aiagents-prod-eastus2/providers/Microsoft.Storage/storageAccounts/stservicehubkbprod<your-name-suffix>/overview` |

## Demo 1: Find the overshare, then guard the agents

### 1.1 Open the default data risk assessment

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Purview, Defender and admin centers, page 1 (Microsoft Purview, Data risk assessments).

1. Switch to **page 1** (**Microsoft Purview**, **Data risk assessments**). Make sure the **Microsoft 365** tab is selected.
2. Confirm the **Default assessment** summary: **Total items**, **Sensitive data detected**, then **Sharing links accessed by Anonymous/External**.
3. Click **View details**. Scroll to **Data risk assessment results** and click **Contoso Cert Hub**.
4. In the flyout, click **Identify**. Confirm **Items scanned** and **Not scanned**.
5. Click **Protect**. Confirm **Restrict access by label**, then **Restrict all items**. Don't click either one.
6. Click **Monitor**. Confirm **Anonymous links accessed (monthly)**, then **Start a SharePoint site access review**. Don't click it.

### 1.2 Turn on real-time protection

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Purview, Defender and admin centers, page 2 (Microsoft Defender, Security for AI).

1. Switch to **page 2** (**Microsoft Defender**, **Security for AI**). Make sure **Get started** is selected.
2. Confirm **Agent 365**: **Done**, then **Microsoft 365 connector**: **Connected**.
3. Confirm **Copilot Studio**: **Unavailable**, then at the orange banner above the checklist.

### 1.3 Connected isn't blocking

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Purview, Defender and admin centers, page 3 (Microsoft Defender, Real-time protection).

1. Switch to **page 3** (**Real-time protection**). Confirm the **Default** rule's **Status**, **Action** and **Scope** columns: **Enabled**, **Audit**, **All**.
2. Confirm the notice above the list that says blocking isn't currently supported for **Copilot Studio** agents.

### 1.4 Review the agents in the admin center

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Purview, Defender and admin centers, page 4 (Microsoft 365 admin center).

1. Switch to **page 4** (**Microsoft 365 admin center**). In the left navigation, click **Agents**, then **All agents**.
2. Make sure **Registry** is selected. Confirm the **Requests** and **Local agents** tabs beside it, then **Deleted agents** in the left navigation under **Agents**.
3. In the search box, type `Contoso IT Helpdesk Agent` and click it. In the details pane, confirm **Owner** under **Overview**, then **Assign new owner** and **Block** at the top right. Don't click **Block**.

## Demo 2: Watch the agents, then stop one

### 2.1 Inventory agents and their sponsors

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center, page 5 (Microsoft Entra admin center, Agent identities).

1. Switch to **page 5** (**Agent identities**).
2. In the search box, type `SC500-L10`. Confirm **SC500-L10 ServiceHub Assistant** and **SC500-L10 ServiceHub Triage Agent**, then their **Status** column: **Active**.
3. Click **SC500-L10 ServiceHub Assistant**. Under **Access**, click **Owners and sponsors**.
4. Confirm **Garth Fort** in the **Sponsor** role.

### 2.2 Read the report-only policies and sign-ins

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center, page 6 (Conditional Access policies).

1. Switch to **page 6** (**Conditional Access**). In the search box, type `CTSO-L10`.
2. Click **CTSO-L10-Agents-Unapproved-Block-ReportOnly**. Under **Users, agents or workload identities**, confirm **All agent identities** included, then **SC500-L10 ServiceHub Assistant** excluded.
3. Under **Grant**, confirm **Block access**. At the bottom, confirm **Enable policy**: **Report-only**.
4. Close the policy pane without clicking **Save**.

### 2.3 What the policy would have done

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center, page 7 (Microsoft Entra admin center, Sign-in logs).

1. Switch to **page 7** (**Microsoft Entra admin center**). Click **Entra ID**, then **Monitoring & health**, then **Sign-in logs**.
2. Click **Service principal sign-ins**. Click **Add filters**, choose **Is Agent**, set it to **Yes**, then click **Apply**.
3. Click the newest **SC500-L10 ServiceHub Triage Agent** sign-in to **Azure Storage**. Click the **Report-only** tab.
4. Confirm the result beside **CTSO-L10-Agents-Unapproved-Block-ReportOnly**.

### 2.4 Disable the assistant, then enable it

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center in Edge, then PowerShell 7 in Terminal, page 5 (Microsoft Entra admin center, Agent identities).

1. Switch to **page 5** (**Agent identities**). Click **SC500-L10 ServiceHub Assistant**, then click **Disable** in the command bar.
2. If a confirmation appears, click **Disable**. Confirm **Status**: **Disabled**.
3. Switch to **Terminal**. Run the command below.
4. Confirm **SC500-L10 ServiceHub Assistant: no token** and **AADSTS7000112**, then at the triage agent's **token issued**.

```powershell
./scripts/lesson-10/Invoke-L10AgentDemo.ps1 -Mode Token
```

### 2.5 Pause one agent, or the whole family

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Entra admin center, page 5 (Microsoft Entra admin center, Agent identities).

1. Switch to **page 5**. On **SC500-L10 ServiceHub Assistant**, click **Enable** in the command bar.
2. Confirm **Status**: **Active**.

## Demo 3: Shrink the blast radius

### 3.1 Read the agent inventory in Defender XDR

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 8 (Microsoft Defender, AI agents).

1. Switch to **page 8** (**Microsoft Defender**, **AI agents**).
2. Click the **Agents** tab. Confirm the **Platform**, **Risk level** and **Risk indicators** columns.
3. Click the first agent whose **Platform** reads **Copilot Studio**. In the details pane, confirm its tools and identity, then click **Open Agent page**.

### 3.2 Hunt the latest state of every agent

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 9 (Microsoft Defender, Advanced hunting).

1. Switch to **page 9** (**Advanced hunting**). Click the plus sign beside the query tabs, then **Query in editor**, so the editor opens empty.
2. Click **Copy command** below. Click in the empty query editor, press **Ctrl+V**, then click **Run query**.
3. Confirm the **Copilot Studio** rows in the results.

```powershell
AgentsInfo
| summarize arg_max(Timestamp, *) by AgentId
| where LifecycleStatus != "Deleted"
```

### 3.3 Check the assistant's access to storage

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 10 (Storage account `stservicehubkbprod<your-name-suffix>`).

1. Switch to **page 10** (storage account `stservicehubkbprod<your-name-suffix>`). In the left menu, click **Access control (IAM)**.
2. Click the **Check access** tab, then the **Check access** button.
3. In the pane's search box, type `SC500-L10 ServiceHub Assistant` and click it.
4. Under **Current role assignments**, confirm **Storage Blob Data Reader**, scope **This resource**.

### 3.4 Scope its role to the knowledge container

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 10 (Storage account `stservicehubkbprod<your-name-suffix>`).

1. In the left menu, under **Data storage**, click **Containers**, then click **knowledge**.
2. In the container's left menu, click **Access control (IAM)**. Click **Add**, then **Add role assignment**.
3. On **Role**, search for `Storage Blob Data Reader`, click it, then click **Next**.
4. On **Members**, choose **User, group, or service principal**. Click **Select members**, type `SC500-L10 ServiceHub Assistant`, click it, then click **Select**.
5. Click **Review + assign**, then **Review + assign** again.
6. In the breadcrumb, click `stservicehubkbprod<your-name-suffix>`. In the left menu, click **Access control (IAM)**, then **Role assignments**.
7. Check the **SC500-L10 ServiceHub Assistant** row where the scope reads **This resource**. Click **Delete**, then **Yes**.

### 3.5 Prove the new reach

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal in Edge, then PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm the assistant's **knowledge** **200**, then **finance** **403** and **tickets** **403**.
3. If finance still reads **200**, wait one minute, press the **Up arrow**, then **Enter**.

```powershell
./scripts/lesson-10/Invoke-L10AgentDemo.ps1 -Mode Token
```

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
