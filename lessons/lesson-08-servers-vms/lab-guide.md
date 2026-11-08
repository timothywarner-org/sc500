# Lesson 8 lab guide

**Secure Servers and Virtual Machines**

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
| 1 | App server vm-servicehub-prod-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-servers-prod-eastus2/providers/Microsoft.Compute/virtualMachines/vm-servicehub-prod-001/overview` |
| 2 | Legacy server vm-legacyapp-prod-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-servers-prod-eastus2/providers/Microsoft.Compute/virtualMachines/vm-legacyapp-prod-001/overview` |
| 3 | Legacy server's NSG inbound rules: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-servers-prod-eastus2/providers/Microsoft.Network/networkSecurityGroups/nsg-vm-legacyapp-prod-001/inboundSecurityRules` |
| 4 | Datacenter server vm-datacenter-prod-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-servers-prod-eastus2/providers/Microsoft.Compute/virtualMachines/vm-datacenter-prod-001/overview` |
| 5 | Policy compliance for rg-servers-prod-eastus2: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-servers-prod-eastus2/policies` |

## Demo 1: Read the security type from both sides

### 1.1 The app server, from Azure's side

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (App server vm-servicehub-prod-001).

1. Switch to **page 1** (the app server).
2. On **Overview**, click the **Properties** tab.
3. Under **Security**, confirm **Security type**: **Trusted launch**.
4. Confirm **Enable secure boot**, **Enable vTPM** and **Integrity monitoring**, each **Enabled**.
5. Scroll to **Disk**. Confirm **Encryption at host**: **Enabled**.

### 1.2 The legacy server: the before picture

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Legacy server vm-legacyapp-prod-001).

1. Switch to **page 2** (the legacy server).
2. On **Overview**, click **Properties**. Under **Security**, confirm **Security type**: **Standard**.
3. Scroll to **Disk**. Confirm **Encryption at host**: **Disabled**, then **Azure disk encryption**: **Not enabled**.

### 1.3 Ask the guest itself

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (App server vm-servicehub-prod-001).

1. Switch to **page 1**. In the left menu, under **Operations**, click **Run command**.
2. Click **RunShellScript**.
3. Click **Copy command** below. Click in the **Linux Shell Script** box and press **Ctrl+V**.
4. Click **Run**. Wait for **Script execution complete** (about 45 seconds).
5. Under **Output**, confirm **SecureBoot enabled**, then **/dev/tpm0**, then **[integrity]**.

```powershell
mokutil --sb-state
ls -l /dev/tpm0
cat /sys/kernel/security/lockdown
```

### 1.4 Integrity monitoring's evidence

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (App server vm-servicehub-prod-001).

1. Still on **page 1**. In the left menu, under **Settings**, click **Extensions + applications**.
2. Confirm **GuestAttestation**: **Provisioning succeeded**.
3. Confirm **MDE.Linux**: **Provisioning succeeded**. The template never asked for it.

### 1.5 The audit names the exception

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 5 (Policy compliance for rg-servers-prod-eastus2).

1. Switch to **page 5** (policy compliance for **rg-servers-prod-eastus2**).
2. Click **Contoso servers: Virtual machines should have encryption at host enabled**.
3. Confirm **vm-legacyapp-prod-001**: **Non-compliant**.
4. Confirm **vm-servicehub-prod-001** and **vm-datacenter-prod-001**: **Compliant**.

## Demo 2: Bastion in, standing access out

### 2.1 A shell on a server with no public IP

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (App server vm-servicehub-prod-001).

1. Switch to **page 1** (the app server).
2. In the left menu, under **Connect**, click **Bastion**.
3. Set **Authentication Type** to **Private Key from Local File**.
4. In **Username**, type `contosoadmin`.
5. Next to **Local File**, click **Browse**.
6. In the dialog's **File name** box, type `%USERPROFILE%\SC500-keys\lesson-08\contosoadmin-bastion.pem`, then click **Open**.
7. Click **Connect** at the bottom. If Edge asks for clipboard access, click **Allow**. The session opens in the portal.
8. Wait for the **contosoadmin@vm-servicehub-prod-001** prompt.
9. Click **Copy command** below. Click inside the **Bastion session** and press **Ctrl+V**, then **Enter**.
10. Confirm the host name **vm-servicehub-prod-001**, then **inet 10.80.1.4**: a private address only.

```powershell
hostname
ip -4 addr show eth0
```

### 2.2 The legacy server answers, all day

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal, any folder.

1. Switch to **Terminal** (PowerShell 7).
2. Click **Copy command** below. In **Terminal**, press **Ctrl+V**, then **Enter**.
3. Confirm **True**.

```powershell
Test-NetConnection (az network public-ip show --subscription <your-subscription-id> --resource-group rg-servers-prod-eastus2 --name pip-vm-legacyapp-prod-001 --query ipAddress --output tsv) -Port 22 -InformationLevel Quiet
```

### 2.3 Turn on just-in-time access

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Legacy server vm-legacyapp-prod-001).

1. Switch to **page 2** (the legacy server). In the left menu, under **Settings**, click **Configuration**.
2. Under **Just-in-time VM access**, click **Enable just-in-time**. Wait for **Just-in-time VM access (JIT) is enabled** (about 20 seconds).
3. Switch to **page 3** (the NSG's inbound rules). Click **Refresh**.
4. Confirm **allow-ssh-admin-standing**, **Allow** at **1000**, then **MicrosoftDefenderForCloud-JITRule**, **Deny** at **4096**.
5. Switch to **Terminal**. Press **Up**, then **Enter**. Confirm **True**.

### 2.4 Remove the standing rule

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 3 (Legacy server's NSG inbound rules).

1. Switch to **page 3**. At the right end of the **allow-ssh-admin-standing** row, click the **trash can** icon.
2. In **Delete security rule**, click **Yes**. Wait for the row to disappear.
3. Switch to **Terminal**. Press **Up**, then **Enter**.
4. Wait about 20 seconds. Confirm **False**.

### 2.5 Request access, just for now

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Legacy server vm-legacyapp-prod-001).

1. Switch to **page 2**. In the left menu, under **Connect**, click **Connect**.
2. Under **Connection prerequisites**, click **Request JIT + Check access**.
3. Wait for **JIT access granted to port 22** and **Port 22 is accessible** (about 40 seconds).
4. Switch to **Terminal**. Press **Up**, then **Enter**. Confirm **True**.
5. Switch to **page 3**. Click **Refresh**. Confirm the new **Allow** rule at **100** for your IP, above the **4096** deny.

## Demo 3: Onboard a server and read the baseline

### 3.1 The datacenter server, before Arc

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 4 (Datacenter server vm-datacenter-prod-001).

1. Switch to **page 1** and press **F5** to end the demo 2 Bastion session. Bastion Developer holds one VM connection at a time.
2. Switch to **page 4** (the datacenter server).
3. In the left menu, under **Connect**, click **Bastion**.
4. Set **Authentication Type** to **Private Key from Local File**.
5. In **Username**, type `contosoadmin`.
6. Next to **Local File**, click **Browse**.
7. In the dialog's **File name** box, type `%USERPROFILE%\SC500-keys\lesson-08\contosoadmin-bastion.pem`, then click **Open**.
8. Click **Connect** at the bottom. If Edge asks for clipboard access, click **Allow**. The session opens in the portal.
9. Wait for the **contosoadmin@datacenter-001** prompt.
10. Click **Copy command** below. Click inside the **Bastion session** and press **Ctrl+V**, then **Enter**.
11. Confirm **Agent Status**: **Disconnected**.

```powershell
sudo azcmagent show
```

### 3.2 Connect it to Azure Arc

**Sign in as:** ADMIN, your admin account. **Where:** Bastion session in the portal, page 4.

1. Click **Copy command** below. Click inside the **Bastion session** and press **Ctrl+V**, then **Enter**.
2. When it prints a code, press **Ctrl+T** in Edge, type `microsoft.com/devicelogin`, press **Enter**.
3. Type the code, then click **Next**.
4. Choose `<your-admin-upn>`, then click **Continue**.
5. Close that tab and switch back to **page 4**. Wait for **Connected machine to Azure** (about a minute).
6. In the session, type `sudo azcmagent show`, press **Enter**. Confirm **Agent Status**: **Connected**.

```powershell
sudo MSFT_ARC_TEST=true azcmagent connect --resource-group rg-servers-prod-eastus2 --tenant-id <your-tenant-id> --subscription-id <your-subscription-id> --location eastus2 --resource-name arcs-datacenter-prod-001 --cloud AzureCloud --tags "managedby=sc500-l08-iac,lesson=8,scenario=Contoso ServiceHub,region=eastus2,criticality=low,dataclass=synthetic,costcenter=sc500-video-course,lifecycle=retain-deallocated,workload=datacenter,env=prod" --use-device-code
```

### 3.3 The server is an Azure resource now

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. In the portal's top search box, type `arcs-datacenter`. Click **arcs-datacenter-prod-001**.
2. Confirm **Status**: **Connected**.
3. Confirm **Tags**: **managedby**, **workload: datacenter**, **env: prod**.

### 3.4 Defender for Servers covers it

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. Top search box: type `Defender for Cloud`. Click **Microsoft Defender for Cloud**.
2. Click **Environment settings**. Click **Expand all**, then **the lab subscription**.
3. In the **Servers** row, confirm **Plan 2** and **On**. Under **Monitoring coverage**, click **Settings**.
4. Confirm **Vulnerability assessment for machines**, **Endpoint protection** and **Agentless scanning for machines**, each **On**. Don't click **Continue**.
5. Top search box: type `arcs-datacenter`. Click **arcs-datacenter-prod-001**.
6. Search box: type `extensions`. Click **Extensions**.
7. Confirm **MDE.Linux** if it's listed.

### 3.5 The baseline report, rule by rule

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. Top search box: type `guest assignments`. Under **Services**, click **Guest Assignments**. If **Machine Configuration** opens, click the **Reports** tab.
2. Click **AzureLinuxBaseline** for **vm-servicehub-prod-001**.
3. Confirm **Total** and **Not compliant**.
4. In **Filter by name**, type `sshd`. Confirm the **NonCompliant** rule and its **Reason**.

### 3.6 The vulnerability findings

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. Top search box: type `Defender for Cloud`. Click **Microsoft Defender for Cloud**, then **Recommendations**.
2. In **Search by title/resource**, type `vm-servicehub`. Confirm the **Update** recommendations for that server.
3. Click any **Update** recommendation. Click the **Associated CVEs** tab.
4. Confirm the **CVE**, its **CVSS** score, and **Discovery Sources**.

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
