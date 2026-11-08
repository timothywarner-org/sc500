# Lesson 4 lab guide

**Secure Storage and Databases**

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
| 1 | Records account `stsc500l04rec<unique>`: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l04-data/providers/Microsoft.Storage/storageAccounts/stsc500l04rec<unique>/overview` |
| 2 | Defender for Cloud, Defender plans for the lab subscription: `https://portal.azure.com/#view/Microsoft_Azure_Security/PolicyMenuBlade/~/pricingTier/subscriptionId/<your-subscription-id>/entryPoint/EnvironmentSettings` |
| 3 | Intake account `stsc500l04in<unique>`: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l04-data/providers/Microsoft.Storage/storageAccounts/stsc500l04in<unique>/overview` |
| 4 | [Defender for Cloud, Security alerts](https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/7) |
| 5 | SQL server sql-sc500-l04-cj2pz7-centralus: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l04-data/providers/Microsoft.Sql/servers/sql-sc500-l04-cj2pz7-centralus/overview` |
| 6 | Database servicehub-records: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l04-data/providers/Microsoft.Sql/servers/sql-sc500-l04-cj2pz7-centralus/databases/servicehub-records/overview` |
| 7 | Log Analytics workspace law-sc500-l04, Logs: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l04-data/providers/Microsoft.OperationalInsights/workspaces/law-sc500-l04/logs` |

## Demo 1: Follow a request into storage

### 1.1 The account's settings

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Records account `stsc500l04rec<unique>`).

1. Go to page 1: `stsc500l04rec<unique>`, Overview.
2. Under Properties, confirm Security: Storage account key access Enabled, Minimum TLS version 1.2, Infrastructure encryption Enabled.
3. Confirm Networking: Public network access, the line that names selected virtual networks and IP addresses.

### 1.2 The firewall refuses your desk

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Records account `stsc500l04rec<unique>`).

1. In the left menu, select Data storage > Containers.
2. Confirm the list: $logs, customer-documents, service-records.
3. Select service-records.
4. Confirm the message: This request is not authorized to perform this operation. Don't open its details, because they print your public IP.

### 1.3 Allow one address

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Records account `stsc500l04rec<unique>`).

1. In the left menu, select Security + networking > Networking.
2. On the Public access tab, under Resource settings: Virtual networks, IP addresses, and exceptions, select Manage.
3. In Resource access settings, select + Add your client IPv4 address.
4. Confirm the Resource instances entry Microsoft.Security/datascanners, storageDataScanner.
5. Confirm Exceptions: Allow trusted Microsoft services to access this resource, checked.
6. Select Save and wait for the success notification.

### 1.4 Read with the account key

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Records account `stsc500l04rec<unique>`).

1. Select Data storage > Containers, then customer-documents.
2. If the portal still refuses, wait 30 seconds and refresh.
3. Confirm Authentication method: Access key.
4. Confirm CTSO-CUST-1042-contract.txt.

### 1.5 Switch to Microsoft Entra ID

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Records account `stsc500l04rec<unique>`).

1. Next to Authentication method, select Switch to Microsoft Entra user account.
2. Confirm the message: You do not have permissions to list the data using your user account with Microsoft Entra ID.
3. Go back to Containers and select service-records.
4. Read the Authentication method line. If it says Access key, select Switch to Microsoft Entra user account.
5. Confirm SR-2026-0418.json.

### 1.6 Issue the partner's SAS

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Records account `stsc500l04rec<unique>`).

1. In service-records, select Settings > Access policy.
2. Confirm servicehub-partner-read, permission r, and its expiry.
3. Select Overview, then select SR-2026-0418.json.
4. Select the Generate SAS tab.
5. Signing method: Account key. Stored access policy: servicehub-partner-read.
6. Confirm Permissions and Expiry, now unavailable.
7. Select Generate SAS token and URL.
8. Copy the Blob SAS URL, open a new browser tab, paste it, and press Enter.
9. Confirm the JSON for Fabrikam, Inc.

### 1.7 Revoke it with the policy

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Records account `stsc500l04rec<unique>`).

1. Switch back to the portal tab and open service-records > Settings > Access policy.
2. On the servicehub-partner-read row, select the ... menu, then Delete.
3. Select Save at the top of the page.
4. Switch to the partner's tab and refresh.
5. Confirm AuthenticationFailed and the message that the SAS identifier can't be found for the signed identifier.

### 1.8 Turn off Shared Key

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Records account `stsc500l04rec<unique>`).

1. Close the partner's tab. In the left menu, select Settings > Configuration.
2. Set Allow storage account key access to Disabled.
3. Confirm the warning under the setting.
4. Select Save and wait for the success notification.
5. Select Data storage > Containers, then customer-documents. Read the Authentication method line, then select Switch to Microsoft Entra user account if it's offered.
6. Confirm the Microsoft Entra permissions message.
7. Open service-records, switch to Microsoft Entra user account if needed, and confirm SR-2026-0418.json.
8. Select Settings > Shared access tokens.
9. Confirm the banner: Authorization with Shared Key is disabled for this account, and at Account key, grayed out, with User delegation key selected.

## Demo 2: Scan a customer upload

### 2.1 The subscription's plan

**Sign in as:** ADMIN, your admin account. **Where:** page 2 (Defender for Cloud, Defender plans for the lab subscription).

1. Go to page 2: Defender plans for the lab subscription.
2. Confirm the Storage row: Status On, Plan Full.
3. Confirm the Databases row: Status On.
4. On the Storage row, select Settings.
5. Confirm Malware scanning On with its monthly cap, scan results as blob index tags, soft delete for malicious blobs Off, and Sensitive data discovery On.
6. Close the pane without saving.

### 2.2 The intake account's own settings

**Sign in as:** ADMIN, your admin account. **Where:** page 3 (Intake account `stsc500l04in<unique>`).

1. Go to page 3: `stsc500l04in<unique>`.
2. In the left menu, select Security + networking > Microsoft Defender for Cloud.
3. Confirm On, Enabled on subscription.
4. Select Settings.
5. Turn on Override Defender for Storage subscription-level settings.
6. Set the monthly cap to 10 GB.
7. Select Save and wait for the success notification.
8. Confirm the banner that begins: You enabled 'Override Defender for Storage subscription-level settings'.

### 2.3 Upload a clean file

**Sign in as:** ADMIN, your admin account. **Where:** page 3 (Intake account `stsc500l04in<unique>`).

1. In the left menu, select Data storage > Containers, then intake-uploads.
2. Select Upload, then Browse for files.
3. Go to C:\github\sc500\lab\infra\lesson-04\seed and pick CTSO-UPLOAD-7731-site-photo-notes.txt.
4. Select Upload.
5. Select the new blob, wait about 10 seconds, and refresh.
6. Confirm Blob index tags: Malware Scanning scan result, No threats found, and Malware Scanning scan time UTC.

### 2.4 The EICAR result

**Sign in as:** ADMIN, your admin account. **Where:** page 3 (Intake account `stsc500l04in<unique>`).

1. Go back to intake-uploads and select CTSO-UPLOAD-7732-eicar-test.txt. Never select Download.
2. Confirm Blob index tags: Malware Scanning scan result, Malicious, and the scan time.
3. Confirm the delete icon next to each tag.

### 2.5 The alert

**Sign in as:** ADMIN, your admin account. **Where:** page 4 (Defender for Cloud, Security alerts).

1. Go to page 4: Security alerts.
2. Set the Subscription filter to the lab subscription only.
3. Add a Resource group filter for rg-sc500-l04-data.
4. Select Malicious blob uploaded to storage account, severity High.
5. Confirm the affected resource, `stsc500l04in<unique>`.

## Demo 3: Prove database access and coverage

### 3.1 The server's settings

**Sign in as:** ADMIN, your admin account. **Where:** page 5 (SQL server sql-sc500-l04-cj2pz7-centralus).

1. Go to page 5: sql-sc500-l04-cj2pz7-centralus, Overview.
2. Confirm Server admin, and at Microsoft Entra admin `<your-admin-upn>`.
3. In the left menu, select Settings > Microsoft Entra ID.
4. Confirm Support only Microsoft Entra authentication for this server, checked.
5. Select Security > Networking.
6. Confirm Public network access: Selected networks, and the firewall rule kim-akers-workstation.
7. Confirm Allow Azure services and resources to access this server, unchecked.
8. Select the Connectivity tab and confirm Minimum TLS version 1.2.

### 3.2 A SQL login gets refused

**Sign in as:** ADMIN, your admin account. **Where:** page 6 (Database servicehub-records).

1. Go to page 6: servicehub-records.
2. In the left menu, select Query editor.
3. Select the SQL authentication tab.
4. Username: servicehub_app. Password: type any test value.
5. Select Connect.
6. Confirm the refusal message.

### 3.3 Your Entra connection gets in

**Sign in as:** ADMIN, your admin account. **Where:** page 6 (Database servicehub-records).

1. Select the Microsoft Entra authentication tab, then Connect as your admin account.
2. Paste the query below into the query window.
3. Select Run.
4. Confirm SignedInAs `<your-admin-upn>`, EntraOnly 1, and ServiceRecords 3.

### 3.4 Encryption and the audit policy

**Sign in as:** ADMIN, your admin account. **Where:** page 5 (SQL server sql-sc500-l04-cj2pz7-centralus).

1. Go to page 5: the server.
2. Select Security > Transparent data encryption.
3. Confirm Service-managed key.
4. Select Security > Auditing.
5. Confirm Enable Azure SQL Auditing, On, and the Log Analytics destination law-sc500-l04.

### 3.5 Find both attempts in the audit trail

**Sign in as:** ADMIN, your admin account. **Where:** page 7 (Log Analytics workspace law-sc500-l04, Logs).

1. Go to page 7: law-sc500-l04, Logs. Close any pop-up, and switch to KQL mode if the editor opens in Simple mode.
2. Paste the query below and select Run.
3. Confirm a DATABASE AUTHENTICATION FAILED row: blank principal name, error 18456 in additional_information_s.
4. Confirm a DATABASE AUTHENTICATION SUCCEEDED row for `<your-admin-upn>` from WQE_Azure SQL Query Editor v2.

### 3.6 Coverage and the assessment finding

**Sign in as:** ADMIN, your admin account. **Where:** page 5 (SQL server sql-sc500-l04-cj2pz7-centralus).

1. Go to page 5: the server.
2. Select Security > Microsoft Defender for Cloud.
3. Confirm Microsoft Defender for SQL: On, Enabled at the subscription level.
4. Select View server vulnerability summary.
5. Confirm servicehub-records, 1 of 24 rules failed, and VA1143, Medium.
6. If older recommendations still say Defender for SQL or vulnerability assessment isn't configured.

### 3.7 Sample alerts

**Sign in as:** ADMIN, your admin account. **Where:** page 4 (Defender for Cloud, Security alerts).

1. Go to page 4: Security alerts.
2. Set the Subscription filter to the lab subscription only.
3. In the search box, type SAMPLE.
4. Select [SAMPLE ALERT] Potential SQL Injection, severity High.
5. Confirm the affected resource, Sample-SQL.

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
