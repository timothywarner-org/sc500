# Lesson 3 lab guide

**Key Vault, Azure Policy, Compliance, Backup, and Infrastructure as Code**

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
| 1 | Key vault `kv-sc500-l03-<unique>`: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l03-platform/providers/Microsoft.KeyVault/vaults/kv-sc500-l03-<unique>/overview` |
| 2 | [Defender for Cloud, Environment settings](https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/EnvironmentSettings) |
| 3 | [Defender for Cloud, Recommendations](https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/%7E/5) |
| 4 | [Defender for Cloud, Security alerts](https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/%7E/7) |
| 5 | [Azure Policy, Assignments](https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyMenuBlade/~/Assignments) |
| 6 | [Create a storage account](https://portal.azure.com/#create/Microsoft.StorageAccount) |
| 7 | Recovery Services vault rsv-sc500-l03: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l03-platform/providers/Microsoft.RecoveryServices/vaults/rsv-sc500-l03/overview` |

## Demo 1: Follow the Key Vault boundary

### 1.1 Permission model

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Key vault `kv-sc500-l03-<unique>`).

1. Go to page 1: `kv-sc500-l03-<unique>`.
2. In the left menu, select Settings > Access configuration.
3. Confirm Permission model: Azure role-based access control.

### 1.2 The workload's data role

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Key vault `kv-sc500-l03-<unique>`).

1. Select Access control (IAM).
2. Select the Role assignments tab.
3. Set the Role filter to Key Vault Secrets User.
4. Confirm vm-sc500-l03-runner, Key Vault Secrets User, scope This resource.

### 1.3 Owner isn't a data role

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Key vault `kv-sc500-l03-<unique>`).

1. Set the Role filter to Owner.
2. Confirm your own Owner row, inherited from the subscription.

### 1.4 Give your account a data role

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Key vault `kv-sc500-l03-<unique>`).

1. Still on Access control (IAM), select + Add > Add role assignment.
2. On the Role tab, search for Key Vault Secrets Officer, select it, then select Next.
3. On the Members tab, keep User, group, or service principal, select + Select members, pick `<your-admin-upn>`, then select Select.
4. Select Review + assign, then select Review + assign again.

### 1.5 The network path

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Key vault `kv-sc500-l03-<unique>`).

1. In the left menu, select Settings > Networking.
2. On Firewalls and virtual networks, confirm Allow access from: Disable public access.
3. Select the Private endpoint connections tab.
4. Confirm pe-sc500-l03-vault, Connection state Approved.

### 1.6 Deletion safeguards

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Key vault `kv-sc500-l03-<unique>`).

1. In the left menu, select Settings > Properties.
2. Confirm the soft delete retention, 7 days.
3. Confirm Purge protection: enabled.

### 1.7 The firewall refuses the portal

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Key vault `kv-sc500-l03-<unique>`).

1. In the left menu, select Objects > Secrets.
2. Wait for the portal's message.
3. Confirm the message text.

### 1.8 Open a narrow path

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Key vault `kv-sc500-l03-<unique>`).

1. In the left menu, select Settings > Networking.
2. Under Allow access from, select Allow public access from specific virtual networks and IP addresses.
3. Under Exception, if Allow trusted Microsoft services to bypass this firewall is selected, clear it.
4. Under Firewall, select Add your client IP address. If that option isn't there, type your public IP address.
5. Save the change (the button reads Apply or Save) and wait for the success notification.

### 1.9 Create ServiceHub's secret

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Key vault `kv-sc500-l03-<unique>`).

1. In the left menu, select Objects > Secrets.
2. Select + Generate/Import.
3. Name: servicehub-config. Secret value: type any test value.
4. Select Create.
5. If the portal still refuses the connection, wait a minute for the firewall change, then refresh.
6. If it says the operation isn't allowed by RBAC, wait a few minutes for the role, then refresh and try again.

### 1.10 Close it again

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Key vault `kv-sc500-l03-<unique>`).

1. In the left menu, select Settings > Networking.
2. Under Firewall, delete your IP address row.
3. If Add your client IP address is checked, clear it.
4. Under Allow access from, select Disable public access.
5. Save the change (the button reads Apply or Save) and wait for the success notification.
6. Select Access control (IAM) > Role assignments, and set the Role filter to Key Vault Secrets Officer.
7. Select your row, select Delete (or Remove), then select Yes.

### 1.11 Wrap

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Key vault `kv-sc500-l03-<unique>`).

## Demo 2: Turn on Defender coverage

### 2.1 Find the subscription's plans

**Sign in as:** ADMIN, your admin account. **Where:** page 2 (Defender for Cloud, Environment settings).

1. Go to page 2: Defender for Cloud, Environment settings.
2. Expand the tenant if needed, then select your lab subscription.
3. Confirm Foundational CSPM: On.

### 2.2 Defender CSPM and agentless scanning

**Sign in as:** ADMIN, your admin account. **Where:** page 2 (Defender for Cloud, Environment settings).

1. In the Defender CSPM row, set Status to On.
2. In the same row, select Settings.
3. Confirm Agentless scanning for machines. If it reads Off, set it to On.
4. Select Continue.

### 2.3 Key Vault plan, then save

**Sign in as:** ADMIN, your admin account. **Where:** page 2 (Defender for Cloud, Environment settings).

1. In the Key Vault row, set Status to On.
2. Select Save at the top of the page.
3. Wait for the success notification.

### 2.4 Read it back

**Sign in as:** ADMIN, your admin account. **Where:** page 2 (Defender for Cloud, Environment settings).

1. Refresh the page.
2. Confirm Defender CSPM: On and Key Vault: On.

### 2.5 Where secret findings land

**Sign in as:** ADMIN, your admin account. **Where:** page 3 (Defender for Cloud, Recommendations).

1. Go to page 3: Recommendations.
2. In the search box, type secrets.
3. Read what's listed.

### 2.6 Generate a sample alert

**Sign in as:** ADMIN, your admin account. **Where:** page 4 (Defender for Cloud, Security alerts).

1. Go to page 4: Security alerts.
2. On the toolbar, select Sample alerts.
3. Select the lab subscription, select only Key Vault, then select Create sample alerts.
4. Wait until the sample alerts appear, usually a few minutes, then refresh.

### 2.7 Read the alert

**Sign in as:** ADMIN, your admin account. **Where:** page 4 (Defender for Cloud, Security alerts).

1. Select one of the Key Vault sample alerts.
2. Confirm the severity, the activity time, and the affected resource.
3. Confirm the MITRE ATT&CK tactic.

### 2.8 Close it out

**Sign in as:** ADMIN, your admin account. **Where:** page 4 (Defender for Cloud, Security alerts).

1. In the alert's status menu, select Dismissed.
2. Back in the list, select the other Key Vault sample alerts, select Change status, then select Dismissed.

### 2.9 Wrap

**Sign in as:** ADMIN, your admin account. **Where:** page 4 (Defender for Cloud, Security alerts).

## Demo 3: Test the guardrail and check the backups

### 3.1 The assignment

**Sign in as:** ADMIN, your admin account. **Where:** page 5 (Azure Policy, Assignments).

1. Go to page 5: Azure Policy, Assignments.
2. In the search box, type SC500 L03 allowed.
3. Select SC500 L03 allowed lab location.
4. Confirm the definition Allowed locations, the scope rg-sc500-l03-policy, and the parameter East US 2.

### 3.2 Break the rule

**Sign in as:** ADMIN, your admin account. **Where:** page 6 (Create a storage account).

1. Go to page 6: Create a storage account.
2. Subscription: your lab subscription, resource group rg-sc500-l03-policy.
3. Storage account name: `stcontosowestus<your-name-suffix>`.
4. Region: (US) West US. If the portal flags the region as disallowed when you pick it, read that message and skip to step 7.
5. Select Review + create.
6. Wait for validation to fail.
7. Open the error details and confirm the assignment name.
8. Leave the page without creating anything.

### 3.3 The same rule as code

**Sign in as:** ADMIN, your admin account. **Where:** page 6 (Create a storage account).

1. Switch to VS Code with infra/lesson-03/policy.bicep open.
2. Confirm the locationRule resource, lines 8 to 17.
3. Confirm line 15, the non-compliance message.

### 3.4 Immutability and soft delete

**Sign in as:** ADMIN, your admin account. **Where:** page 7 (Recovery Services vault rsv-sc500-l03).

1. Go to page 7: rsv-sc500-l03.
2. In the left menu, select Settings > Properties.
3. Under Immutable vault, select Settings.
4. Confirm Enable vault immutability, checked, and the lock option, unchecked.
5. Close the pane with X. Never select Apply.
6. Under Security settings, select Update.
7. Confirm soft delete: always on, 14 days.
8. Close the pane with X. Never select Update inside the pane.

### 3.5 Multi-user authorization

**Sign in as:** ADMIN, your admin account. **Where:** page 7 (Recovery Services vault rsv-sc500-l03).

1. On Properties, find Multi-User Authorization and select Update.
2. Confirm Protect with Resource Guard and guard-sc500-l03.
3. Select Cancel. Don't save anything.

### 3.6 The recovery points

**Sign in as:** ADMIN, your admin account. **Where:** page 7 (Recovery Services vault rsv-sc500-l03).

1. In the left menu, select Protected items > Backup items.
2. Select Azure Virtual Machine, then vm-sc500-l03-runner.
3. Confirm the restore points list and the most recent one.

### 3.7 Trace a recommendation to the VM

**Sign in as:** ADMIN, your admin account. **Where:** page 3 (Defender for Cloud, Recommendations).

1. Go to page 3: Defender for Cloud.
2. In the left menu, select Inventory.
3. Search for vm-sc500-l03-runner and open it.
4. On the Recommendations tab, confirm Azure Backup should be enabled for virtual machines: Healthy.

### 3.8 Wrap

**Sign in as:** ADMIN, your admin account. **Where:** page 3 (Defender for Cloud, Recommendations).

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
