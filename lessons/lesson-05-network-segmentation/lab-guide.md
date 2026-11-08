# Lesson 5 lab guide

**Network Segmentation: NSGs, ASGs, Virtual Network Manager, Virtual WAN, and VPN**

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
| 1 | Web tier VM vm-servicehub-web: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l05-network/providers/Microsoft.Compute/virtualMachines/vm-servicehub-web/overview` |
| 2 | [Network Watcher, Connection troubleshoot](https://portal.azure.com/#view/Microsoft_Azure_Network/NetworkWatcherMenuBlade/~/vmConnectivity) |
| 3 | NSG nsg-servicehub, Inbound security rules: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l05-network/providers/Microsoft.Network/networkSecurityGroups/nsg-servicehub/inboundSecurityRules` |
| 4 | Data tier network interface nic-vm-servicehub-data: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l05-network/providers/Microsoft.Network/networkInterfaces/nic-vm-servicehub-data/overview` |
| 5 | Flow-log storage account `stsc500l05flow<unique>`: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l05-network/providers/Microsoft.Storage/storageAccounts/stsc500l05flow<unique>/overview` |
| 6 | Network manager avnm-sc500-l05: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l05-network/providers/Microsoft.Network/networkManagers/avnm-sc500-l05/overview` |
| 7 | ServiceHub VNet vnet-sc500-l05-servicehub: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l05-network/providers/Microsoft.Network/virtualNetworks/vnet-sc500-l05-servicehub/overview` |
| 8 | Hub connection conn-hub-to-field-branch: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l05-vpn/providers/Microsoft.Network/connections/conn-hub-to-field-branch/overview` |
| 9 | Branch connection conn-field-branch-to-hub, Configuration: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l05-vpn/providers/Microsoft.Network/connections/conn-field-branch-to-hub/configuration` |
| 10 | Hub VPN gateway vgw-contoso-platform-hub, Point-to-site configuration: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-sc500-l05-network/providers/Microsoft.Network/virtualNetworkGateways/vgw-contoso-platform-hub/pointtositeconfiguration` |

## Demo 1: Segment the ServiceHub tiers

### 1.1 Each tier has a group

**Sign in as:** ADMIN, your admin account. **Where:** page 1 (Web tier VM vm-servicehub-web).

1. Go to page 1: vm-servicehub-web. In the left menu, select Networking > Application security groups.
2. Confirm asg-servicehub-web.

### 1.2 The web tier reaches the data tier

**Sign in as:** ADMIN, your admin account. **Where:** page 2 (Network Watcher, Connection troubleshoot).

1. Go to page 2: Connection troubleshoot. Source type: Virtual machine. Virtual machine: vm-servicehub-web.
2. Destination type: Specify manually. URI, FQDN, or IP address: 10.55.16.6.
3. Protocol: TCP. Destination port: 5432. Diagnostic tests: Connectivity only (clear NSG diagnostic, Next hop and Port scanner).
4. Select Run diagnostic tests. Wait until the result shows (25 to 85 seconds).
5. Confirm the Connectivity test row: Status and Details. If it reads Unreachable, select See details and confirm the rule it names.

### 1.3 Allow the two tier paths

**Sign in as:** ADMIN, your admin account. **Where:** page 3 (NSG nsg-servicehub, Inbound security rules).

1. Go to page 3: nsg-servicehub, Inbound security rules. Select + Add.
2. Source: Application security group. Source application security groups: asg-servicehub-web. Destination: Application security group. Destination application security groups: asg-servicehub-app.
3. Service: Custom. Destination port ranges: 8080. Protocol: TCP. Action: Allow. Priority: 100. Name: Allow-Web-To-App. Select Add.
4. Select + Add. Source application security groups: asg-servicehub-app. Destination application security groups: asg-servicehub-data.
5. Destination port ranges: 5432. Protocol: TCP. Action: Allow. Priority: 110. Name: Allow-App-To-Data. Select Add.

### 1.4 Deny the rest of the internal traffic

**Sign in as:** ADMIN, your admin account. **Where:** page 3 (NSG nsg-servicehub, Inbound security rules).

1. Select + Add. Source: Service Tag. Source service tag: VirtualNetwork. Destination: Any.
2. Service: Custom. Destination port ranges: *. Protocol: Any. Action: Deny. Priority: 4000. Name: Deny-Other-VNet-Inbound. Select Add.
3. Confirm the rule order: 100, 110, 4000, then AllowVnetInBound at 65000.

### 1.5 Test fresh connections, then read the rules

**Sign in as:** ADMIN, your admin account. **Where:** page 2 (Network Watcher, Connection troubleshoot).

1. Go to page 2: run Connectivity from vm-servicehub-web to 10.55.16.5, TCP 8080. Then run it from vm-servicehub-app to 10.55.16.6, TCP 5432. Wait for each run to finish.
2. Run Connectivity from vm-servicehub-web to 10.55.16.6, TCP 5432. Select See details and confirm Deny-Other-VNet-Inbound.
3. Go to page 4: nic-vm-servicehub-data. Select Help > Effective security rules. Confirm 110 and 4000 above the default rules.

### 1.6 The flow log records the deny

**Sign in as:** ADMIN, your admin account. **Where:** page 5 (Flow-log storage account `stsc500l05flow<unique>`).

1. Go to page 5: `stsc500l05flow<unique>`. Select Data storage > Containers > insights-logs-flowlogflowevent.
2. Open flowLogResourceID= > `<your-subscription-id>_NETWORKWATCHERRG` > NETWORKWATCHER_EASTUS2_FL-VNET-SC500-L05-SERVICEHUB.
3. Open the current UTC hour: y=, m=, d=, h=, then m=00, then macAddress=7C1E52C8905B.
4. Select PT1H.json, then Edit. Press Ctrl+F, search for 10.55.16.4,10.55.16.6, and confirm the tuple ending 5432,6,I,D. Close without saving.
5. If the tuple isn't there yet, wait five minutes and refresh.

## Demo 2: Enforce a platform guardrail

### 2.1 Garth's troubleshooting rule

**Sign in as:** ADMIN, your admin account. **Where:** page 3 (NSG nsg-servicehub, Inbound security rules).

1. Go to page 3: nsg-servicehub, Inbound security rules. Select + Add.
2. Source application security groups: asg-servicehub-web. Destination application security groups: asg-servicehub-data.
3. Service: Custom. Destination port ranges: 22. Protocol: TCP. Action: Allow. Priority: 300. Name: Allow-SSH-Web-To-Data-Troubleshooting. Select Add.

### 2.2 Who reaches SSH now

**Sign in as:** ADMIN, your admin account. **Where:** page 2 (Network Watcher, Connection troubleshoot).

1. Go to page 2: run Connectivity from vm-servicehub-web to 10.55.16.6, TCP 22. Wait for the run to finish.
2. Run Connectivity from vm-platform-scan to 10.55.16.6, TCP 22. Select See details and confirm Deny-Other-VNet-Inbound.

### 2.3 Kim's two admin rules

**Sign in as:** ADMIN, your admin account. **Where:** page 6 (Network manager avnm-sc500-l05).

1. Go to page 6: avnm-sc500-l05. Select Settings > Configurations > sac-contoso-platform-baseline > Rule collections > rc-platform-remote-access.
2. Confirm AlwaysAllow-PlatformScanner-SSH: Always allow, priority 100, TCP 22 from 10.55.0.0/27.
3. Confirm Deny-RemoteAdmin-Elsewhere: Deny, priority 200, TCP 22 and 3389 from any source.

### 2.4 Deploy it to the region

**Sign in as:** ADMIN, your admin account. **Where:** page 6 (Network manager avnm-sc500-l05).

1. In avnm-sc500-l05, select Settings > Deployments, then Deploy configurations > Security admin configuration.
2. On the Goal state tab, Security admin configurations: sac-contoso-platform-baseline. Target regions: East US 2.
3. Select Next. On Review + deploy, select Deploy.
4. Back on Deployments, confirm the East US 2 row and its Deployment status.

### 2.5 The rules as the spoke sees them

**Sign in as:** ADMIN, your admin account. **Where:** page 7 (ServiceHub VNet vnet-sc500-l05-servicehub).

1. Go to page 7: vnet-sc500-l05-servicehub. Select Settings > Network manager.
2. Select the Security admin configurations tab. Confirm AlwaysAllow-PlatformScanner-SSH and Deny-RemoteAdmin-Elsewhere.

### 2.6 Test the precedence

**Sign in as:** ADMIN, your admin account. **Where:** page 2 (Network Watcher, Connection troubleshoot).

1. Wait one minute after Deployed. Admin rules roll out eventually, not instantly.
2. Go to page 2: run Connectivity from vm-servicehub-web to 10.55.16.6, TCP 22. Select See details and confirm Deny-RemoteAdmin-Elsewhere.
3. Run Connectivity from vm-platform-scan to 10.55.16.6, TCP 22.
4. Go to page 3: nsg-servicehub, Inbound security rules. Confirm Allow-SSH-Web-To-Data-Troubleshooting, still at 300.

## Demo 3: Secure branch and remote access

### 3.1 Why the branch tunnel is down

**Sign in as:** ADMIN, your admin account. **Where:** page 8 (Hub connection conn-hub-to-field-branch).

1. Go to page 8: conn-hub-to-field-branch, Overview. Confirm Status: Not connected.
2. Select Settings > Configuration. Confirm IKE AES256, SHA256, DHGroup14 and IPsec GCMAES256 with PFS14.
3. Go to page 9: conn-field-branch-to-hub, Configuration. Confirm IKE AES128, SHA1, DHGroup2 and IPsec AES128, SHA1, PFS None.

### 3.2 Bring the branch up to baseline

**Sign in as:** ADMIN, your admin account. **Where:** page 9 (Branch connection conn-field-branch-to-hub, Configuration).

1. On conn-field-branch-to-hub, Configuration, keep IPsec / IKE policy: Custom.
2. IKE Phase 1: Encryption AES256. Integrity/PRF SHA256. DH Group DHGroup14.
3. IKE Phase 2 (IPsec): IPsec Encryption GCMAES256. IPsec Integrity GCMAES256. PFS Group PFS14. Leave the SA lifetimes and DPD timeout as they are.
4. Select Save. Refresh Overview until Status reads Connected (about four minutes).

### 3.3 Prove the branch path

**Sign in as:** ADMIN, your admin account. **Where:** page 2 (Network Watcher, Connection troubleshoot).

1. Go to page 2: Connection troubleshoot. Source type: Virtual machine. Virtual machine: vm-branch-client.
2. Destination type: Specify manually. URI, FQDN, or IP address: 10.55.0.4.
3. Protocol: TCP. Destination port: 22. Diagnostic tests: Connectivity only (clear NSG diagnostic, Next hop and Port scanner).
4. Select Run diagnostic tests. Wait until the result shows (25 to 85 seconds).
5. Confirm the Connectivity test row: Status and Details. If it reads Unreachable, select See details and confirm the rule it names.

### 3.4 The technicians' VPN settings

**Sign in as:** ADMIN, your admin account. **Where:** page 10 (Hub VPN gateway vgw-contoso-platform-hub, Point-to-site configuration).

1. Go to page 10: vgw-contoso-platform-hub, Point-to-site configuration (Basics tab).
2. Confirm Address pool 172.16.55.0/24, Tunnel type OpenVPN (SSL), Authentication type Microsoft Entra ID, and Audience c632b3df-fb67-4d84-bdcf-b95ad541b5c8.
3. Select Download VPN client and save the ZIP to Downloads.

### 3.5 Import the profile and connect

**Sign in as:** ADMIN, your admin account. **Where:** File Explorer, then Azure VPN Client.

1. In File Explorer, open Downloads. Right-click the VPN client ZIP, select Extract All, then Extract.
2. Open Azure VPN Client. Select + (bottom left), then Import. Open the extracted AzureVPN folder, select azurevpnconfig.xml, select Open, then Save.
3. Select the profile, select Connect, and sign in as `<your-admin-upn>`.
4. Confirm Connection status: Connected and the VPN IP address from 172.16.55.0/24.

### 3.6 Test with the tunnel, then without it

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7, then Azure VPN Client.

1. Open PowerShell 7 and run the command below. Confirm TcpTestSucceeded: True and the VPN InterfaceAlias.
2. In Azure VPN Client, select Disconnect.
3. Run the same command again. Confirm TcpTestSucceeded: False.

```powershell
Test-NetConnection -ComputerName 10.55.0.4 -Port 22 -InformationLevel Detailed
```

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
