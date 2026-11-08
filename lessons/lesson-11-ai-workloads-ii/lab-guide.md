# Lesson 11 lab guide

**Secure AI Workloads II: Microsoft Foundry, AI Gateway, and Defender for AI**

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
| 1 | API Management, `apim-servicehubai-prod-<your-name-suffix>`: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-servicehubai-prod-eastus2/providers/Microsoft.ApiManagement/service/apim-servicehubai-prod-<your-name-suffix>/overview` |
| 2 | [Defender for Cloud, Environment settings](https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/EnvironmentSettings) |
| 3 | [Microsoft Foundry](https://ai.azure.com/) |
| 4 | [Defender for Cloud, Overview](https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/0) |
| 5 | [Microsoft Defender, Alerts](https://security.microsoft.com/alerts) |
| 6 | [Microsoft Defender, Cases](https://security.microsoft.com/casesv2?viewId=incident-cases) |
| 7 | Log Analytics, log-servicehubai-prod-eastus2-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-servicehubai-prod-eastus2/providers/Microsoft.OperationalInsights/workspaces/log-servicehubai-prod-eastus2-001/logs` |

## Demo 1: Front door, side doors, and the AI plan

### 1.1 Try the side doors, then the front door

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the first command below.
2. Confirm the **key** line: **disableLocalAuth is set to be true**.
3. Confirm the **token** line and its **401 PermissionDenied**.
4. Run the second command below.
5. Confirm **no subscription key** and its **401**.
6. Confirm **servicehub-assistant key** and its **200**, then **x-ctso-remaining-tokens** in the **headers** line.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Invoke-L11GatewayDemo.ps1 -Mode Direct
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Invoke-L11GatewayDemo.ps1 -Mode Gateway
```

### 1.2 Find the app's key in API Management

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (API Management, `apim-servicehubai-prod-<your-name-suffix>`).

1. Switch to **page 1** (`apim-servicehubai-prod-<your-name-suffix>`). In the left menu, under **APIs**, click **Subscriptions**.
2. Confirm the **servicehub-assistant** row, then its **Scope** column. Don't click **Show/hide keys**.

### 1.3 Read the budget policy

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (API Management, `apim-servicehubai-prod-<your-name-suffix>`).

1. In the left menu, click **APIs**, then **APIs**, then **servicehub-ai**.
2. Click **All operations**, then the **Design** tab.
3. In **Inbound processing**, click the **</>** policy code editor.
4. Confirm **set-header** with `api-key`, then **authentication-managed-identity**.
5. Confirm **llm-token-limit**, then its `tokens-per-minute` value, `400`.
6. Close the editor. Don't click **Save**.

### 1.4 Spend the token budget until you get 429

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **remaining** falling on each **call** line.
3. Confirm the **429** line and its **retry-after** value.
4. Confirm **after the wait** and its **200**.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Invoke-L11GatewayDemo.ps1 -Mode Burst
```

### 1.5 Read the AI services plan and its settings

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Defender for Cloud, Environment settings).

1. Switch to **page 2** (**Defender for Cloud, Environment settings**). Click **the lab subscription**.
2. Find the **AI services** row. Confirm its status: **On**.
3. On that row, click **Settings**.
4. Confirm **Enable user prompt evidence**: **On**, then **Enable data security for AI interactions**: **Off**, then **AI model security**: **Off**.
5. Close the pane. Don't change a toggle, and don't click **Continue**.

## Demo 2: Model first, then the agent

### 2.1 Read ServiceHub's guardrail

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Foundry portal, page 3 (Microsoft Foundry).

1. Switch to **page 3** (**Microsoft Foundry**). Open the project **proj-servicehubai-prod-eastus2-001**.
2. In the top right menu, click **Build**. In the left navigation, click **Guardrails**.
3. Click **ctso-servicehub-guardrail**.
4. Confirm the **Jailbreak** and **Indirect attack** controls and their intervention points, then the **ctso-customer-ids** blocklist.
5. Close the wizard. Don't click **Next** or **Save**.

### 2.2 Send a clean prompt, an ID, and a jailbreak

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **Benign** and its **200** with **finish=stop**.
3. Confirm **BlocklistIn**, its **400**, then **custom_blocklists: ctso-customer-ids**.
4. Confirm **BlocklistOut**, its **finish=content_filter**, then the empty **returned text**.
5. Confirm **Jailbreak**, its **400**, then **jailbreak: detected=True**.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Invoke-L11GuardrailDemo.ps1 -Mode Model
```

### 2.3 Compare prepared agent versions

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm version **1**'s **X-900** line: **scanned [prompt, post_tool, completion]**.
3. Confirm version **2**'s **X-900** line: **post_tool(blocked)** and **blocked by indirect_attack**.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-11\Invoke-L11GuardrailDemo.ps1 -Mode AgentCompare
```

### 2.4 Read tool output and filter results

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Confirm version **1**'s **X-900** reply. The model declined the planted note on its own.
2. Confirm version **2**'s **X-900** reply: **I'm sorry, but I cannot assist with that request.**
3. Confirm both **C-200** replies: clean traffic still gets its answer.

## Demo 3: Follow the jailbreak

### 3.1 Open the dashboard's AI closer look

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 4 (Defender for Cloud, Overview).

1. Switch to **page 4** (**Defender for Cloud**). In the left menu, click **Data and AI security**.
2. In the overview, confirm the **AI services** count and its protection status.
3. Scroll to **AI closer look**. Confirm **AI threat protection**: prompts scanned, then alerts by severity.

### 3.2 Open the jailbreak alert and its evidence

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 5 (Microsoft Defender, Alerts).

1. Switch to **page 5** (**Microsoft Defender, Alerts**).
2. Click the newest **A Jailbreak attempt on your Azure AI model deployment was blocked by Prompt Shields** row.
3. Confirm **What happened**, then **Activity details**: **Model deployment name** `servicehub-chat`.
4. Click **View alert page in MDC**.

### 3.3 Read the prompt evidence

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. On the Defender for Cloud alert page, under **Alert details**, expand **Supporting evidence events**, then click **Show events**.
2. Confirm **Prompt Suspicious Segment**, then **Application** and **End User**.

### 3.4 Follow it to the Defender XDR incident

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 6 (Microsoft Defender, Cases).

1. Switch to **page 6** (**Microsoft Defender, Cases**).
2. Click the newest case whose **Detection source** reads **Microsoft Defender for AI Services**.
3. Confirm its **Incident ID**, then **Severity**.

### 3.5 Match the request in the gateway logs

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 7 (Log Analytics, log-servicehubai-prod-eastus2-001).

1. Switch to **page 7** (**Log Analytics, log-servicehubai-prod-eastus2-001**). If the **Queries** window opens, close it.
2. Make sure the editor is in **KQL mode**.
3. Click **Copy command** below. Click in the query editor, press **Ctrl+V**, then click **Run**.
4. Confirm the newest row: **ResponseCode** **400**, then its **CorrelationId**.
5. Confirm **PromptTokens**, then **CompletionTokens**: **0**.

```powershell
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h) and ApiId == 'servicehub-ai' and BackendResponseCode == 400
| join kind=inner (ApiManagementGatewayLlmLog | where DeploymentName != '') on CorrelationId
| project TimeGenerated, CorrelationId, ResponseCode, DeploymentName, PromptTokens, CompletionTokens
| order by TimeGenerated desc
```

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
