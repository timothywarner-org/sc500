# Lesson 12 lab guide

**Manage Posture with Microsoft Defender for Cloud and Multicloud**

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
| 1 | [Microsoft Defender, Recommendations](https://security.microsoft.com/exposure-recommendations) |
| 2 | Storage account, `stservicehubexports<your-name-suffix>`: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-servicehub-prod-eastus2/providers/Microsoft.Storage/storageAccounts/stservicehubexports<your-name-suffix>/overview` |
| 3 | [Defender for Cloud, Overview](https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/0) |
| 4 | [Defender for Cloud, Environment settings](https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/EnvironmentSettings) |
| 5 | Defender EASM, easmattacksurface001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-attacksurface-shared-eastus/providers/Microsoft.Easm/workspaces/easmattacksurface001/overview` |

## Demo 1: Rank it, fix it, prove it

### 1.1 Rank ServiceHub's findings by risk

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 1 (Microsoft Defender, Recommendations).

1. Switch to **page 1** (**Microsoft Defender, Recommendations**). Click the **Cloud assets** tab.
2. Switch to the **Recommendation title** view. Search `shared key`.
3. Click **Storage accounts should prevent shared key access**. In the side panel, open **Exposed assets**.
4. Confirm `stservicehubexports<your-name-suffix>`: its **risk level**, then its **risk factors**.
5. Confirm `stservicehubarchive<your-name-suffix>`: same recommendation, its **risk level**.

### 1.2 Read the same finding from the terminal

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm the `stservicehubexports<your-name-suffix>` line: **severity**, **risk**, then **factors**.
3. Confirm the `stservicehubarchive<your-name-suffix>` line: same severity, its own risk.
4. Confirm the **What this run proves** table at the bottom. Every row should read **as expected**. If one says **DIFFERENT**, say what you see and why.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PostureDemo.ps1 -Mode Findings
```

### 1.3 Turn off Shared Key access and prove it

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Storage account, `stservicehubexports<your-name-suffix>`).

1. Switch to **page 2** (`stservicehubexports<your-name-suffix>`). In the left menu, under **Settings**, click **Configuration**.
2. Confirm **Allow storage account key access**: **Enabled**. Don't change it here.

### 1.4 Refuse the key, keep the Entra path

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **Before**: **ALLOWED**.
3. Confirm **After**: **REFUSED**, and the reason **Key based authentication is not permitted**.
4. Confirm **your Entra request**: **ALLOWED**, then the **Activity log** line and its **correlation** ID.
5. Confirm the **What this run proves** table at the bottom. Every row should read **as expected**. If one says **DIFFERENT**, say what you see and why.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PostureDemo.ps1 -Mode Remediate
```

### 1.5 Read the setting back in the portal

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Storage account, `stservicehubexports<your-name-suffix>`).

1. Switch to **page 2**. Click **Refresh** on **Configuration**.
2. Confirm **Allow storage account key access**: **Disabled**.

### 1.6 Trace it to compliance and an owner

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 3 (Defender for Cloud, Overview).

1. Switch to **page 3** (**Defender for Cloud, Overview**). In the left menu, click **Regulatory compliance**.
2. Click **Microsoft cloud security benchmark**. Expand **IM. Identity Management**, then **IM.1**.
3. Confirm **Storage accounts should prevent shared key access** and its failed resource count.

### 1.7 Give the finding an owner and a date

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the first command below.
2. Confirm **Assigned**: owner, due date, grace period **True**.
3. Confirm the **What this run proves** table at the bottom. Every row should read **as expected**. If one says **DIFFERENT**, say what you see and why.
4. Run the second command below.
5. Confirm the **Assignments on the store's shared-key finding** line.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PostureDemo.ps1 -Mode Assign
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PostureDemo.ps1 -Mode Governance
```

### 1.8 Read the owner on the finding

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 3 (Defender for Cloud, Overview).

1. Switch to **page 3**. In the left menu, click **Recommendations**.
2. Search `shared key`, then click **Storage accounts should prevent shared key access**.
3. Confirm `stservicehubexports<your-name-suffix>`: its **Owner**, then its **Due date**.

## Demo 2: One plan, one account

### 2.1 Read the plans and their components

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 4 (Defender for Cloud, Environment settings).

1. Switch to **page 4** (**Defender for Cloud, Environment settings**). Click **the lab subscription**.
2. Confirm **Defender CSPM**: **On**, then **Storage**: **On**, **AI services**: **On**, and **Servers**: **Off**.
3. On the **Storage** row, click **Settings**.
4. Confirm **On-upload malware scanning** and its monthly cap, then **Sensitive data threat detection**.
5. Close the pane. Don't change a toggle, and don't click **Save**.

### 2.2 Override Defender for Storage on the export store

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Storage account, `stservicehubexports<your-name-suffix>`).

1. Switch to **page 2** (`stservicehubexports<your-name-suffix>`). In the left menu, under **Security + networking**, click **Microsoft Defender for Cloud**.
2. Confirm the banner: the account **overrides** the subscription setting.
3. Click **Settings**. Confirm **Override Defender for Storage subscription-level settings**: **On**, and protection: **Off**.
4. Close the pane. Don't click **Save**.

### 2.3 Turn on the override for one account

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the first command below.
2. Confirm **After**: enabled, override, malware on upload, cap **5** GB, sensitive data threat detection.
3. Confirm the **What this run proves** table at the bottom. Every row should read **as expected**. If one says **DIFFERENT**, say what you see and why.
4. Run the second command below.
5. Confirm the subscription's cap, **10000** GB, then the `stservicehubexports<your-name-suffix> read from ARM now` line.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PlanDemo.ps1 -Mode StorageOverride
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PlanDemo.ps1 -Mode StorageRead
```

### 2.4 Read the override in the portal

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Storage account, `stservicehubexports<your-name-suffix>`).

1. Switch to **page 2**. Click **Refresh** on the **Microsoft Defender for Cloud** page.
2. Click **Settings**. Confirm the override: protection **On**, malware scanning cap **5** GB.
3. Close the pane. Don't click **Save**.

### 2.5 Upload the export and read the verdict

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. While **Waiting up to three minutes** shows, it's waiting for the verdict for this one blob.
3. If the table reads **not written yet**, click **Copy command** again, press **Ctrl+V**, then **Enter**.
4. Confirm **Malware Scanning scan result** and its **scan time**.
5. Confirm the **What this run proves** table at the bottom. Every row should read **as expected**. If one says **DIFFERENT**, say what you see and why.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12PlanDemo.ps1 -Mode Scan
```

### 2.6 Read the verdict tag on the blob

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Storage account, `stservicehubexports<your-name-suffix>`).

1. Switch to **page 2**. In the left menu, under **Data storage**, click **Containers**, then **parts-exports**.
2. Click the **parts-export-proof-** blob that the script printed.
3. Confirm **Blob index tags**: **Malware Scanning scan result**.

## Demo 3: Beyond Azure, then from outside

### 3.1 Walk the AWS and GCP connector wizards

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 4 (Defender for Cloud, Environment settings).

1. Switch to **page 4** (**Defender for Cloud, Environment settings**). Click **Add environment**, then **Amazon Web Services**.
2. Confirm the account details: the connector's **name**, its **subscription** and **resource group**, then the **AWS account ID**.
3. Leave the fields blank. Close the wizard without selecting **Create**.

### 3.2 Walk the GCP connector to its boundary

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 4 (Defender for Cloud, Environment settings).

1. Click **Add environment**, then **Google Cloud Platform**.
2. Confirm the choice between a **single project** and an **organization**.
3. Leave the fields blank. Close the wizard without selecting **Create**.

### 3.3 Read what Defender covers beyond Azure

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **Multicloud connectors**: **None**.
3. Confirm **Azure Arc-enabled servers**: **None**, then **Defender for Servers**.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12CloudDemo.ps1 -Mode All
```

### 3.4 Read the discovery and decide ownership

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 5 (Defender EASM, easmattacksurface001).

1. Switch to **page 5** (**Defender EASM, easmattacksurface001**). In the left menu, under **Manage**, click **Discovery**.
2. Click **servicehub-external**. Confirm the seed, `<your-domain>`, the weekly recurrence, then the latest run.

### 3.5 Sort the inventory by state

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 5 (Defender EASM, easmattacksurface001).

1. In the left menu, under **General**, click **Inventory**.
2. Remove the **State = Approved** filter with its **X**.
3. Filter **Kind** to **Domain** and **Host**. Confirm the **State** column: **Approved**, **Candidate**, **Dependency**.
4. Don't open an **IP address** asset.

### 3.6 Count the inventory from the terminal

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm the **Approved** and **Dependency** rows.
3. Confirm **Candidates that need an ownership decision**.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-12\Invoke-L12EasmDemo.ps1 -Mode Inventory
```

### 3.7 Open the attack surface priorities

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 5 (Defender EASM, easmattacksurface001).

1. In the left menu, under **Dashboards**, click **Attack surface summary**.
2. Confirm the dashboard's **updated** date first.
3. Confirm **Attack surface priorities**: **High**, **Medium**, **Low**.
4. If a priority is listed, open it and confirm its **remediation guidance**. Don't open **IP address** assets.

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
