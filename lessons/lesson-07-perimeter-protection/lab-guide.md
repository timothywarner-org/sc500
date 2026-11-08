# Lesson 7 lab guide

**Perimeter Protection: Azure Firewall and Network Watcher Diagnostics**

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
| 1 | Firewall policy afwp-hub-shared-eastus2-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-perimeter-shared-eastus2/providers/Microsoft.Network/firewallPolicies/afwp-hub-shared-eastus2-001/overview` |
| 2 | Log Analytics workspace log-hub-shared-eastus2-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-perimeter-shared-eastus2/providers/Microsoft.OperationalInsights/workspaces/log-hub-shared-eastus2-001/overview` |
| 3 | Network interface nic-vm-servicehub-prod-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-perimeter-shared-eastus2/providers/Microsoft.Network/networkInterfaces/nic-vm-servicehub-prod-001/overview` |
| 4 | Network interface nic-vm-servicehub-test-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-perimeter-shared-eastus2/providers/Microsoft.Network/networkInterfaces/nic-vm-servicehub-test-001/overview` |
| 5 | Public IP pip-afw-hub-shared-eastus2-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-perimeter-shared-eastus2/providers/Microsoft.Network/publicIPAddresses/pip-afw-hub-shared-eastus2-001/overview` |

## Demo 1: Watch the policy work, then enforce

### 1.1 One inspected workload path, and separate agent exceptions

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (Firewall policy afwp-hub-shared-eastus2-001).

1. Switch to **page 1** (the firewall policy).
2. In the left menu's search box, type `rule`. Click **Rule collections**.
3. Confirm **rcg-dnat 100**, **rcg-network 200** and **rcg-application 300**.
4. Search box: type `threat`. Click **Threat Intelligence**. Confirm **Alert**.
5. Search box: type `IDPS`. Click **IDPS**. Confirm **Alert**.
6. Search box: type `application`. Click **Application rules**.
7. Confirm **allow-firewall-docs-inspected** (TLS inspection on), then the OS and Defender rules below it (TLS inspection off).

### 1.2 The status page shows what production's probe saw

**Sign in as:** ADMIN, your admin account. **Where:** Edge, the status page through the firewall's DNAT rule.

1. Click **Copy command** in the box below.
2. In Edge, press **Ctrl+T**, then **Ctrl+V**, then **Enter**.
3. Confirm **allowed-url**: **200** and **Azure Firewall Manager CA**.
4. Confirm **same-site-other-path**: **470**.
5. Confirm **unlisted-site** and **prod-to-nonprod**: neither one got through.
6. Leave this tab open. Demo step 1.6 comes back to it.

```powershell
http://<your-public-ip>:8080/status
```

### 1.3 Alert mode logs the test and lets it through

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal, any folder.

1. Click **Copy command** in the box below.
2. In **Terminal**, press **Ctrl+V**, then **Enter**. If Terminal warns about multiple lines, click **Paste anyway**.
3. Confirm both answers: **Contoso ServiceHub production**, one from **10.70.0.5** and one from **10.70.0.6**.

```powershell
curl.exe -sS -m 15 http://<your-public-ip>:8080/
curl.exe -sS -m 15 -A "HaxerMen" http://<your-public-ip>:8080/
```

### 1.4 Switch threat intelligence and IDPS to Alert and deny

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (Firewall policy afwp-hub-shared-eastus2-001).

1. **page 1**. Search box: type `threat`. Click **Threat Intelligence**.
2. Set **Threat intelligence mode** to **Alert and deny**. Click **Save**.
3. Wait for the bell to show **Succeeded**, about 5 minutes.
4. Search box: type `IDPS`. Click **IDPS**. On the **Mode** tab, choose **Alert and deny**. Click **Apply**.
5. Wait for the bell to show **Succeeded**. The portal refuses a second policy update while one is running.
6. Click the **Signature rules** tab. In the **Signature ID** filter, type `2032081`.
7. Tick that one row's checkbox. Click **Edit Rules**.
8. Set **Signature mode** to **Alert and Deny** (there is no plain Deny). Click **Apply**.
9. Wait for **Succeeded**, about 5 minutes.

### 1.5 The test request now dies at the firewall

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal, any folder.

1. Wait **one more minute** after the second Succeeded.
2. Click **Copy command** in the box below.
3. In **Terminal**, press **Ctrl+V**, then **Enter**. If Terminal warns about multiple lines, click **Paste anyway**.
4. Confirm line one: the page answers.
5. Confirm line two: **curl: (28)** after 15 seconds.
6. Line two still answers? Wait 60 seconds and run both again.

```powershell
curl.exe -sS -m 15 http://<your-public-ip>:8080/
curl.exe -sS -m 15 -A "HaxerMen" http://<your-public-ip>:8080/
```

### 1.6 Threat intelligence answers before any rule does

**Sign in as:** ADMIN, your admin account. **Where:** Edge, the status page through the firewall's DNAT rule.

1. Switch to the Edge **status tab** from demo step 1.2. Press **F5**.
2. Confirm **threat-intel-test**: **470**, Reason: **Threat Intel**.
3. Still timeout? Wait 60 seconds and press **F5** again.

### 1.7 The logs name each engine

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Log Analytics workspace log-hub-shared-eastus2-001).

1. **page 2** (the workspace). Left menu: click **Logs**.
2. Close the **Queries** pop-up with its **X**.
3. Top right dropdown: switch **Simple mode** to **KQL mode**.
4. Click **Copy command** in the box below. Click in the editor, press **Ctrl+A**, then **Ctrl+V**. Click **Run**.
5. Confirm the two **learn.microsoft.com** rows: one **Allow**, one **Deny**, both **IsTlsInspected True**.
6. Confirm **deny-prod-to-nonprod**, then **AZFWThreatIntel Deny**, then **2032081 drop**.
7. Skip every other host. **Failed to resolve table** means wait 60 seconds and click **Run** again.

```powershell
AZFWApplicationRule
| union AZFWNetworkRule, AZFWThreatIntel, AZFWIdpsSignature
| where TimeGenerated > ago(30m)
| summarize Hits = count(), Last = max(TimeGenerated) by Type, Action, Rule, Fqdn, TargetUrl, IsTlsInspected, SignatureId
| sort by Last desc
```

## Demo 2: Diagnose prod to non-prod

### 2.1 The route sends both destinations to the firewall

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. **page 1**. In the top search bar, type `Network Watcher`. Click **Network Watcher**.
2. Left menu: click **Next hop**.
3. Resource group: **rg-perimeter-shared-eastus2**. Virtual machine: **vm-servicehub-prod-001**.
4. Source IP address: `10.70.16.4`. Destination IP address: `10.70.32.4`. Click **Next hop**.
5. Confirm **Virtual appliance**, **10.70.0.4** and **rt-servicehub-prod-eastus2-001**.
6. Change Destination IP address to `<your-public-ip>`. Click **Next hop**. Confirm the same answer.
7. Reads **None**? Stop. The firewall is gone.

### 2.2 The user-defined route is the one in effect

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 3 (Network interface nic-vm-servicehub-prod-001).

1. **page 3** (production's network interface).
2. In the left menu's search box, type `effective`. Click **Effective routes**.
3. Confirm the **User** route: **0.0.0.0/0**, **Active**, **Virtual appliance 10.70.0.4**.
4. Confirm the **Default** route for **0.0.0.0/0** to **Internet**: **Invalid**.

### 2.3 The NSGs allow the flow the firewall denies

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. **page 1**. Network Watcher left menu: click **IP flow verify**.
2. Check A: **vm-servicehub-prod-001**, **TCP**, **Outbound**, local `10.70.16.4` port `50000`, remote `10.70.32.4` port `8080`. Click **Verify IP flow** (or **Check**). Confirm **Access allowed**.
3. Check B: **vm-servicehub-test-001**, **TCP**, **Inbound**, local `10.70.32.4` port `8080`, remote `10.70.16.4` port `50000`. Run it. Confirm **Access allowed**.
4. Check C: **vm-servicehub-prod-001**, **TCP**, **Inbound**, local `10.70.16.4` port `8080`, remote `10.70.32.4` port `50000`. Run it. Confirm **Access denied** and **deny-all-other-inbound**.

### 2.4 Effective rules explain each verdict

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 4 (Network interface nic-vm-servicehub-test-001).

1. **page 4** (the test VM's network interface). Left menu search: type `effective`. Click **Effective security rules**.
2. Confirm **AllowVnetInBound** at **65000**.
3. **page 3** (production's interface). Left menu search: type `effective`. Click **Effective security rules**.
4. Confirm **allow-app-from-firewall** at **100** and **deny-all-other-inbound** at **4000**.

## Demo 3: Turn on DDoS IP Protection

### 3.1 The public IP inherits from a hub with no plan

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 5 (Public IP pip-afw-hub-shared-eastus2-001).

1. **page 5** (the firewall's public IP). On **Overview**, click the **Properties** tab (beside **Get started**).
2. Find the **DDoS Protection** section on the right.
3. Confirm **Protection status: Unprotected** and **Protection type: Network inherited protection**.

### 3.2 Turn on IP Protection and read it back

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. Click the **Network inherited protection** link. **Configure DDoS Protection** opens.
2. Set **Protection type** to **IP** (Specific to this IP address). Click **Save**.
3. When the save finishes, confirm **Protection status: Protected** and **Protection type: IP protection**.

### 3.3 Put the inherited baseline back

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal, any folder.

1. Click **Copy command** in the box below.
2. In **Terminal**, press **Ctrl+V**, then **Enter**.
3. Confirm **VirtualNetworkInherited** in the output.

```powershell
az network public-ip update --subscription <your-subscription-id> --resource-group rg-perimeter-shared-eastus2 --name pip-afw-hub-shared-eastus2-001 --ddos-protection-mode VirtualNetworkInherited --query ddosSettings
```

### 3.4 When the requirement changes the tier

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 5 (Public IP pip-afw-hub-shared-eastus2-001).

1. **page 5**. Press **F5**, then click **DDoS protection** again.
2. Confirm the inherited setting, the baseline you started from.

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
