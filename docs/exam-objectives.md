# SC-500 Exam Objectives — Full Map

This document mirrors Microsoft's published **Skills Measured** for Exam SC-500 and shows exactly which lesson in this course covers which sub-domain. Use it as a self-assessment checklist while you study.

> **Source:** [Microsoft Skills Measured — SC-500](https://learn.microsoft.com/credentials/certifications/exams/sc-500/)
> **Beta exam window:** May 2026
> **General availability:** July 2026
> **Successor to:** AZ-500 (retires August 31, 2026)

---

## FG1: Manage identity, access, and governance (20-25%)

### FG1.1 Manage Microsoft Entra ID identity, authentication, and access — *Lessons 1, 2*

- Implement and configure Microsoft Entra Privileged Identity Management for Azure resources and Microsoft Entra roles → **Lesson 1**
- Implement and configure authentication methods → **Lesson 2**
- Design and implement Conditional Access policies → **Lesson 2**
- Implement and configure identity for applications → **Lesson 2**
- Implement and configure system-assigned and user-assigned managed identities, and apply Workload Identity Federation → **Lesson 2**

### FG1.2 Manage Azure Key Vault — *Lesson 3*

- Deploy and configure Azure Key Vault → **Lesson 3**
- Scan for exposed secrets using Microsoft Defender Cloud Security Posture Management → **Lesson 3**

### FG1.3 Manage Azure governance and compliance — *Lessons 1, 3*

- Manage Azure built-in role assignments and create custom Azure roles → **Lesson 1**
- Manage Microsoft Entra directory roles → **Lesson 1**
- Evaluate and remediate overprivileged access; apply resource locks → **Lesson 1**
- Implement security controls using Azure Policy → **Lesson 3**
- Evaluate compliance and security recommendations in Microsoft Defender for Cloud → **Lesson 3**
- Configure Azure Backup security features → **Lesson 3**
- Implement security controls using Infrastructure as Code with Azure Policy guardrails → **Lesson 3**

---

## FG2: Secure storage, databases, and networking (25-30%)

### FG2.1 Implement security for Azure Storage — *Lesson 4*

- Implement and configure security for Azure Storage accounts → **Lesson 4**
- Implement Microsoft Defender for Storage threat protection → **Lesson 4**

### FG2.2 Implement security for Azure databases — *Lesson 4*

- Implement platform-level security configurations in Azure SQL → **Lesson 4**
- Configure Microsoft Defender for Databases across Azure SQL, PostgreSQL, MySQL, Cosmos DB → **Lesson 4**

### FG2.3 Implement security for Azure networking — *Lessons 5, 6, 7*

- Implement and manage NSGs and ASGs → **Lesson 5**
- Implement network access policies using Azure Virtual Network Manager → **Lesson 5**
- Configure security for Azure Virtual WAN → **Lesson 5**
- Implement and configure security for VPN connections → **Lesson 5**
- Configure Azure Private Endpoints; disable public network access → **Lesson 6**
- Configure Azure Private Link services → **Lesson 6**
- Implement Microsoft Entra Private Access → **Lesson 6**
- Manage Private DNS zones for hybrid and multi-region topologies → **Lesson 6**
- Implement and configure Azure Firewall → **Lesson 7**
- Design hub-and-spoke perimeter architectures → **Lesson 7**
- Evaluate effective security rules with Azure Network Watcher → **Lesson 7**
- Apply Zero Trust segmentation principles → **Lesson 7**

---

## FG3: Secure compute (20-25%)

### FG3.1 Secure AI workloads — *Lessons 10, 11*

- Identify SharePoint data overexposure and Microsoft Copilot risks via Microsoft Purview DSPM → **Lesson 10**
- Enable real-time protection for Microsoft Copilot Studio agents → **Lesson 10**
- Manage AI agents in the Microsoft 365 admin center → **Lesson 10**
- Implement Conditional Access for Microsoft Entra Agent ID → **Lesson 10**
- Analyze blast radius for Entra Agent ID risks using Microsoft Defender XDR → **Lesson 10**
- Configure and deploy AI Gateway in Azure API Management for Microsoft Foundry → **Lesson 11**
- Enable Microsoft Defender for AI Service → **Lesson 11**
- Configure guardrails for agent security in Microsoft Foundry → **Lesson 11**
- Monitor AI security with the Data and AI security dashboard; correlate with Microsoft Sentinel → **Lesson 11**

### FG3.2 Secure servers and virtual machines — *Lesson 8*

- Implement disk encryption (Azure Disk Encryption, host-based) and VM security features → **Lesson 8**
- Plan Azure Bastion for RDP/SSH; enable JIT VM access via Defender for Cloud → **Lesson 8**
- Extend controls with Azure Arc; onboard Defender for Servers Plan 1/2; configure vulnerability scanning, agentless scanning, EDR with Defender for Endpoint → **Lesson 8**
- Enforce config via Azure Machine Configuration; tune Defender Vulnerability Management → **Lesson 8**

### FG3.3 Secure application platform services — *Lesson 9*

- Detect container misconfigurations with Defender for Containers; secure AKS, ACR, ACI, Container Apps → **Lesson 9**
- Implement security controls for Azure Functions and Azure Logic Apps → **Lesson 9**
- Implement security controls for Azure App Service; Azure WAF on Front Door and Application Gateway → **Lesson 9**
- Implement back-end API security with Azure API Management → **Lesson 9**

---

## FG4: Manage and monitor security posture (20-25%)

### FG4.1 Manage posture with Microsoft Defender for Cloud — *Lesson 12*

- Identify risks via Defender CSPM; evaluate compliance against frameworks → **Lesson 12**
- Enable Defender for Cloud workload protection plans → **Lesson 12**
- Connect hybrid and multicloud (AWS, GCP) environments → **Lesson 12**
- Discover unprotected assets with Microsoft Defender External Attack Surface Management → **Lesson 12**

### FG4.2 Manage security operations with Microsoft Sentinel — *Lessons 13, 14*

- Create and connect Microsoft Sentinel workspaces → **Lesson 13**
- Implement content hub solutions; configure connectors for Azure, Entra, M365, Defender XDR → **Lesson 13**
- Implement syslog, CEF, and Windows Security event collection via DCRs and WEF → **Lesson 13**
- Create custom log tables; implement data retention policies → **Lesson 13**
- Create and tune analytics rules → **Lesson 14**
- Implement automation rules and Logic Apps playbooks → **Lesson 14**
- Write KQL queries for threat hunting; deploy custom workbooks and notebooks → **Lesson 14**
- Query Microsoft Purview Audit in Defender XDR; manage incidents end-to-end → **Lesson 14**

### FG4.3 Manage security with Microsoft Security Copilot — *Lesson 15*

- Configure workspaces for Microsoft Security Copilot → **Lesson 15**
- Manage permissions and roles → **Lesson 15**
- Enable plugins for Defender XDR, Sentinel, Intune, Entra, and third-party products → **Lesson 15**
- Enable Microsoft agents and Security Store agents for AI-assisted response → **Lesson 15**

---

## Self-assessment

Copy the table below into your notes and rate each sub-domain on a **1-5 confidence scale** before you sit the exam. Anything under a 4 needs more hands-on time.

| Sub-domain | Confidence (1-5) | Notes |
|---|---|---|
| FG1.1 Entra ID identity / auth / access | | |
| FG1.2 Azure Key Vault | | |
| FG1.3 Azure governance and compliance | | |
| FG2.1 Azure Storage | | |
| FG2.2 Azure databases | | |
| FG2.3 Azure networking | | |
| FG3.1 AI workloads | | |
| FG3.2 Servers and VMs | | |
| FG3.3 Application platform services | | |
| FG4.1 Defender for Cloud posture | | |
| FG4.2 Microsoft Sentinel | | |
| FG4.3 Microsoft Security Copilot | | |
