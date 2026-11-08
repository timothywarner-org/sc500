# Lesson 14 lab guide

**Microsoft Sentinel II: Analytics, Automation, KQL Hunting, and Purview Audit**

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
| 1 | [Microsoft Defender, Home](https://security.microsoft.com) |
| 2 | [Microsoft Defender, Incidents](https://security.microsoft.com/incidents) |
| 3 | logic-exportresponse-shared-eastus2-001, Overview: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-secopsresponse-shared-eastus2/providers/Microsoft.Logic/workflows/logic-exportresponse-shared-eastus2-001/logicApp` |
| 4 | [Microsoft Defender, Audit](https://security.microsoft.com/auditlogsearch) |

## Demo 1: From a labeled export to an incident

### 1.1 Read the rule back

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 1 (Microsoft Defender, Home).

1. Switch to **page 1** (**Microsoft Defender, Home**). In the left menu, click **Microsoft Sentinel**, **Configuration**, then **Analytics**.
2. Search `ServiceHub` and select **ServiceHub parts export with no service case**.
3. In the details pane, confirm the **Rule query**, then **Rule frequency** (every 5 minutes) and **Rule period** (20 minutes).
4. In the query, confirm `isempty(CaseId)`, then `approved_export_jobs`.

### 1.2 Read the entities and the grouping

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **runsEvery PT5M** and **looksBack PT20M**.
3. Confirm **entities**: Account from Actor, IP from ClientIp, File from FileName.
4. Confirm **customDetails**, then **grouping**: AllEntities within PT5H.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14DetectionDemo.ps1 -Mode Rule
```

### 1.3 Read the test exports and tune

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the first command below.
2. Confirm **fixtureId** and **fileName**, then the line **this command did not send new events**.
3. Run the next command below.
4. Confirm **removed: service case SR-1043**, then **removed: approved export job**, then **kept: no case, not an approved job**.
5. Confirm **Untuned query: 3 rows. Tuned query: 1**.
6. If it reads **actively refused** from api.loganalytics.io, run it again; a second try usually connects.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14DetectionDemo.ps1 -Mode Fixture
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14DetectionDemo.ps1 -Mode Tune
```

### 1.4 Find the alert and its incident

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **alertName**, then **entities**: account svc-servicehub-parts, ip 198.51.100.77, and the file.
3. Confirm **incidentNumber 1**, **incidentProvider Microsoft XDR**, and **alertsInIncident 2**.
4. If it reads **actively refused** from api.loganalytics.io, run it again; a second try usually connects.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14DetectionDemo.ps1 -Mode Alert
```

### 1.5 Open the incident Katie works

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 2 (Microsoft Defender, Incidents).

1. Switch to **page 2** (**Microsoft Defender, Incidents**). Search `Parts export with no service case`, then open incident **99** (the older one).
2. Confirm the incident's account **svc-servicehub-parts**, the IP address **198.51.100.77**, and the file.
3. Confirm the tags **ServiceHub** and **parts-export**. Don't open anything else.

## Demo 2: Tag the incident, run the playbook

### 2.1 Read the automation rule

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 1 (Microsoft Defender, Home).

1. Switch to **page 1**. In the left menu, click **Microsoft Sentinel**, **Configuration**, then **Automation**.
2. On **Automation rules**, select **ServiceHub export incidents: tag and run the response playbook**.
3. Confirm the trigger, **When incident is created**, then the condition on the export rule.
4. Confirm the actions in order: **Add tags**, then **Run playbook**.

### 2.2 Check the playbook and its roles

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 3 (logic-exportresponse-shared-eastus2-001, Overview).

1. Switch to **page 3** (**logic-exportresponse-shared-eastus2-001**). In the left menu, click **Development Tools**, then **Logic app designer**.
2. Confirm the trigger, **Microsoft Sentinel incident**, then the one action, **Add comment to incident (V3)**.
3. In the left menu, click **Settings**, then **Identity**. Confirm **System assigned**, **Status On**.

### 2.3 Read the two roles that make it run

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **Microsoft Sentinel Automation Contributor** for **Microsoft Sentinel (Azure Security Insights)** on rg-secopsresponse-shared-eastus2.
3. Confirm **Microsoft Sentinel Responder** for the playbook identity on log-secops-shared-eastus2-001.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14ResponseDemo.ps1 -Mode Playbook
```

### 2.4 Trace the tags, the comment, and the run

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm **Incident 1** and its tags, **parts-export, ServiceHub**.
3. Confirm the comment's run ID, then **Succeeded**.
4. If it reads **actively refused** from api.loganalytics.io, run it again; a second try usually connects.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14ResponseDemo.ps1 -Mode Trace
```

### 2.5 See the comment where Katie works

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 2 (Microsoft Defender, Incidents).

1. Switch to **page 2**, on incident **99**. Click **Activity log**.
2. Confirm the comment from **logic-exportresponse-shared-eastus2-001** and the run ID inside it.

## Demo 3: Hunt it, then put Audit on the case

### 3.1 Run the saved hunt and open the workbook

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 1 (Microsoft Defender, Home).

1. Switch to **page 1**. In the left menu, click **Microsoft Sentinel**, **Threat management**, then **Hunting**.
2. On **Queries**, search `ServiceHub`, select **ServiceHub exports with no service case, by actor**, then click **Run query**.
3. Confirm **svc-servicehub-parts**: **Exports**, then **WithoutCase**, then **SourceIps**.

### 3.2 Open the workbook

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 1 (Microsoft Defender, Home).

1. In the left menu, click **Microsoft Sentinel**, **Threat management**, then **Workbooks**.
2. On **My workbooks**, select **ServiceHub export investigation**, then click **View saved workbook**.
3. Confirm **Parts exports by case status**, **Exports with no service case**, then **Incidents from the export rule**.

### 3.3 Search Audit for the uploaded file

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 4 (Microsoft Defender, Audit).

1. Switch to **page 4** (**Microsoft Defender, Audit**). Set the start and end dates so they cover the time you uploaded the file. Audit search dates are in UTC.
2. In **Activities - operation names**, type `FileUploaded`.
3. Leave **File, folder, or site** empty. A file name with hyphens or dots in that box returns no results. Click **Search**.
4. When the search reads **Completed**, open it, then select the **FileUploaded** row for your `parts-export-` CSV file.
5. Confirm **User**, **Operation**, **ObjectId**, then the **CreationTime** in UTC. You need the time and the record **Id** for the next step.

### 3.4 Add it to the incident

**Sign in as:** ADMIN, your admin account. **Where:** Microsoft Defender portal, page 2 (Microsoft Defender, Incidents).

1. Switch to **page 2**, on incident **99**. Click **Activity log**, then the comment box.
2. Type `Purview Audit: FileUploaded by <your-admin-upn>, parts-export-20261106T161241871Z-c8e264f5.csv, <CreationTime> UTC, record <Id>. The name matches; the bytes aren't proven.`, filling in the two values from demo step 3.3.
3. Click **Comment**. Leave the incident's status alone.

### 3.5 Add it to the incident and read the timeline

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal.

1. Switch to **Terminal**. Run the command below.
2. Confirm the evidence class on each row: **synthetic fixture**, **live observation**, **playbook comment**.
3. Confirm the newest row, the comment you just added.
4. If it reads **actively refused** from api.loganalytics.io, run it again; a second try usually connects.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-14\Invoke-L14AuditDemo.ps1 -Mode Timeline
```

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
