# Exam SC-500 objective map

This map lists Microsoft's published skills measured for **Exam SC-500: Implementing End-to-End Security Controls for Cloud and AI Workloads** and the lesson in this course that teaches each one. Rate yourself 1 to 5 on every row, then spend your study time on anything below a 4.

> **Source:** [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500). Microsoft's page shows "Last updated on 2026-05-13." When Microsoft revises the study guide, its list wins over this one.

## Manage identity, access, and governance (20-25%)

### Secure access to resources by using Microsoft Entra ID

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Implement and configure Privileged Identity Management (PIM) | [Lesson 1](../lessons/lesson-01-identity-foundations/) |  |
| Implement conditional access policies | [Lesson 2](../lessons/lesson-02-entra-id-access/) |  |
| Implement and configure authentication methods, including multifactor authentication (MFA) and passwordless | [Lesson 2](../lessons/lesson-02-entra-id-access/) |  |
| Implement and configure identity for applications, including enterprise applications and app registrations | [Lesson 2](../lessons/lesson-02-entra-id-access/) |  |
| Manage OAuth permission grants and consent settings | [Lesson 2](../lessons/lesson-02-entra-id-access/) |  |
| Implement and configure managed identities for Azure resources | [Lesson 2](../lessons/lesson-02-entra-id-access/) |  |

### Secure secrets and keys by using Azure Key Vault

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Deploy Key Vault | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/) |  |
| Configure Key Vault settings | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/) |  |
| Configure access to Key Vault | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/) |  |
| Configure firewall settings on Key Vault | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/) |  |
| Manage keys, secrets, and certificates | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/) |  |
| Scan for secrets by using Defender Cloud Security Posture Management (Defender CSPM) | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/) |  |
| Implement Defender for Key Vault | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/) |  |

### Implement governance to enforce security and regulatory compliance

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Implement and configure security controls by using Azure Policy, including built-in and custom policy definitions | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/) |  |
| Evaluate regulatory compliance by using Microsoft Defender for Cloud | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/), [Lesson 12](../lessons/lesson-12-defender-cloud-multicloud/) |  |
| Implement and configure security controls in Defender for Cloud, including security standards and recommendations | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/) |  |
| Implement resource locks | [Lesson 1](../lessons/lesson-01-identity-foundations/) |  |
| Manage Azure built-in role assignments | [Lesson 1](../lessons/lesson-01-identity-foundations/) |  |
| Manage custom roles, including Azure roles and Microsoft Entra roles | [Lesson 1](../lessons/lesson-01-identity-foundations/) |  |
| Evaluate and remediate overprivileged access assignments by using Azure role-based access control (RBAC) | [Lesson 1](../lessons/lesson-01-identity-foundations/) |  |
| Configure security controls for backup protection by using Azure Backup security features | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/) |  |
| Implement and configure security controls by using infrastructure as code | [Lesson 3](../lessons/lesson-03-keyvault-policy-iac/) |  |

## Secure storage, databases, and networking (25-30%)

### Implement security for storage accounts

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Implement and configure security for storage accounts | [Lesson 4](../lessons/lesson-04-storage-databases/) |  |
| Configure Azure Storage firewall rules | [Lesson 4](../lessons/lesson-04-storage-databases/) |  |
| Implement Defender for Storage threat protection configurations | [Lesson 4](../lessons/lesson-04-storage-databases/) |  |
| Manage access to storage, including access policies | [Lesson 4](../lessons/lesson-04-storage-databases/) |  |

### Implement security for databases

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Implement platform-level security configurations in Azure SQL | [Lesson 4](../lessons/lesson-04-storage-databases/) |  |
| Configure database auditing for Azure SQL Database and Azure SQL Managed Instance | [Lesson 4](../lessons/lesson-04-storage-databases/) |  |
| Configure Defender for Databases protection across Azure database services | [Lesson 4](../lessons/lesson-04-storage-databases/) |  |

### Implement security for Azure network services

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Implement and manage network security groups (NSGs) and application security groups (ASGs) | [Lesson 5](../lessons/lesson-05-network-segmentation/) |  |
| Implement and configure network access policies by using Azure Virtual Network Manager | [Lesson 5](../lessons/lesson-05-network-segmentation/) |  |
| Configure security for an Azure Virtual WAN | [Lesson 5](../lessons/lesson-05-network-segmentation/) |  |
| Implement and configure security for virtual private network (VPN) connections | [Lesson 5](../lessons/lesson-05-network-segmentation/) |  |
| Implement and configure Microsoft Entra Private Access | [Lesson 6](../lessons/lesson-06-private-connectivity/) |  |
| Configure Azure private endpoints to secure access to Azure platform as a service (PaaS) resources | [Lesson 6](../lessons/lesson-06-private-connectivity/) |  |
| Configure Azure Private Link services to secure access to network resources | [Lesson 6](../lessons/lesson-06-private-connectivity/) |  |
| Implement and configure Azure Firewall | [Lesson 7](../lessons/lesson-07-perimeter-protection/) |  |
| Evaluate effective security rules by using Azure Network Watcher diagnostics | [Lesson 7](../lessons/lesson-07-perimeter-protection/) |  |

## Secure compute (20-25%)

### Implement security for AI

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Identify overexposure of data in SharePoint | [Lesson 10](../lessons/lesson-10-ai-workloads-i/) |  |
| Identify risks related to Microsoft Copilot and AI apps by using Microsoft Purview Data Security Posture Management (DSPM) | [Lesson 10](../lessons/lesson-10-ai-workloads-i/) |  |
| Enable and configure real-time protection for Microsoft Copilot Studio agents | [Lesson 10](../lessons/lesson-10-ai-workloads-i/) |  |
| Implement conditional access for Microsoft Entra Agent ID | [Lesson 10](../lessons/lesson-10-ai-workloads-i/) |  |
| Analyze blast radius for security risks related to Entra Agent ID by using Defender XDR | [Lesson 10](../lessons/lesson-10-ai-workloads-i/) |  |
| Manage Entra Agent ID access | [Lesson 10](../lessons/lesson-10-ai-workloads-i/) |  |
| Configure and deploy AI Gateway in Azure API Management for Microsoft Foundry | [Lesson 11](../lessons/lesson-11-ai-workloads-ii/) |  |
| Enable Defender for AI Service in Cloud Workload Protection in Defender for Cloud | [Lesson 11](../lessons/lesson-11-ai-workloads-ii/) |  |
| Configure guardrails for agent security in Foundry | [Lesson 11](../lessons/lesson-11-ai-workloads-ii/) |  |
| Monitor AI security by using the Data and AI security dashboard in Defender for Cloud | [Lesson 11](../lessons/lesson-11-ai-workloads-ii/) |  |
| Manage agents in Microsoft 365 admin center | [Lesson 10](../lessons/lesson-10-ai-workloads-i/) |  |

### Implement security for servers and virtual machines (VMs)

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Implement and configure disk encryption | [Lesson 8](../lessons/lesson-08-servers-vms/) |  |
| Plan and implement Azure Bastion | [Lesson 8](../lessons/lesson-08-servers-vms/) |  |
| Enable and enforce use of just-in-time (JIT) VM access | [Lesson 8](../lessons/lesson-08-servers-vms/) |  |
| Extend security controls to hybrid and multicloud servers by using Azure Arc | [Lesson 8](../lessons/lesson-08-servers-vms/) |  |
| Onboard servers to Defender for Servers in Defender for Cloud, including hybrid and multicloud scenarios | [Lesson 8](../lessons/lesson-08-servers-vms/) |  |
| Configure Defender for Servers settings, including vulnerability scanning, and endpoint detection and response (EDR) | [Lesson 8](../lessons/lesson-08-servers-vms/) |  |
| Implement and manage agentless scanning for VMs in Defender for Servers | [Lesson 8](../lessons/lesson-08-servers-vms/) |  |
| Configure security features on a VM, including secure boot, virtual Trusted Platform Module (vTPM), integrity monitoring, and security type | [Lesson 8](../lessons/lesson-08-servers-vms/) |  |
| Enforce security configuration of Azure-managed servers by using Azure Machine Configuration | [Lesson 8](../lessons/lesson-08-servers-vms/) |  |

### Implement security for application platform services

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Detect misconfigurations and runtime risks in container workloads by using Defender for Containers | [Lesson 9](../lessons/lesson-09-app-platform/) |  |
| Implement and configure security controls for Azure Kubernetes Service (AKS) | [Lesson 9](../lessons/lesson-09-app-platform/) |  |
| Implement and configure security controls for Azure Container Registry | [Lesson 9](../lessons/lesson-09-app-platform/) |  |
| Implement and configure security controls for Azure Container Instances and Azure Container Apps | [Lesson 9](../lessons/lesson-09-app-platform/) |  |
| Implement and configure security controls for Azure Functions, including authentication and network access | [Lesson 9](../lessons/lesson-09-app-platform/) |  |
| Implement and configure security controls for Azure Logic Apps | [Lesson 9](../lessons/lesson-09-app-platform/) |  |
| Implement and configure security controls for Azure App Service | [Lesson 9](../lessons/lesson-09-app-platform/) |  |
| Implement and configure Azure Web Application Firewall | [Lesson 9](../lessons/lesson-09-app-platform/) |  |
| Implement security policies for back-end API protection by using API Management | [Lesson 9](../lessons/lesson-09-app-platform/) |  |

## Manage and monitor security posture (20-25%)

### Manage security posture by using Defender for Cloud

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Identify security risks by using Defender CSPM | [Lesson 12](../lessons/lesson-12-defender-cloud-multicloud/) |  |
| Evaluate compliance against security frameworks by using Defender for Cloud | [Lesson 12](../lessons/lesson-12-defender-cloud-multicloud/) |  |
| Enable and configure Defender for Cloud workload protection plans | [Lesson 12](../lessons/lesson-12-defender-cloud-multicloud/) |  |
| Connect hybrid cloud and multicloud environments to Defender for Cloud, including Amazon Web Services (AWS) and Google Cloud Platform (GCP) | [Lesson 12](../lessons/lesson-12-defender-cloud-multicloud/) |  |
| Configure Microsoft Defender Vulnerability Management settings for Azure VMs | [Lesson 8](../lessons/lesson-08-servers-vms/) |  |
| Discover unprotected assets and vulnerabilities by using Microsoft Defender External Attack Surface Management (EASM) | [Lesson 12](../lessons/lesson-12-defender-cloud-multicloud/) |  |

### Implement activity and event collection in Microsoft Sentinel

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Create and connect workspaces in Microsoft Sentinel | [Lesson 13](../lessons/lesson-13-sentinel-i/) |  |
| Assign roles in Microsoft Sentinel | [Lesson 13](../lessons/lesson-13-sentinel-i/) |  |
| Implement and use content hub solutions | [Lesson 13](../lessons/lesson-13-sentinel-i/) |  |
| Configure and use Microsoft data connectors for Azure resources | [Lesson 13](../lessons/lesson-13-sentinel-i/) |  |
| Implement and configure syslog and Common Event Format (CEF) event collections | [Lesson 13](../lessons/lesson-13-sentinel-i/) |  |
| Implement and configure collection of Windows Security events by using data collection rules, including Windows Event Forwarding (WEF) | [Lesson 13](../lessons/lesson-13-sentinel-i/) |  |
| Create custom log tables in the workspace to store ingested data | [Lesson 13](../lessons/lesson-13-sentinel-i/) |  |
| Implement automation rules and playbooks in Microsoft Sentinel | [Lesson 14](../lessons/lesson-14-sentinel-ii/) |  |
| Implement data retention in Microsoft Sentinel data stores | [Lesson 13](../lessons/lesson-13-sentinel-i/) |  |
| Query Microsoft Purview Audit in Defender XDR | [Lesson 14](../lessons/lesson-14-sentinel-ii/) |  |

### Implement Microsoft Security Copilot

| Skill | Lesson | Confidence (1-5) |
| --- | --- | --- |
| Configure workspaces for Security Copilot | [Lesson 15](../lessons/lesson-15-security-copilot/) |  |
| Manage permissions and roles in Security Copilot | [Lesson 15](../lessons/lesson-15-security-copilot/) |  |
| Enable and configure plugins | [Lesson 15](../lessons/lesson-15-security-copilot/) |  |
| Enable and configure Microsoft agents and Security Store agents | [Lesson 15](../lessons/lesson-15-security-copilot/) |  |

## Beyond the study guide

A few lesson objectives go a step past the study guide's wording because an engineer needs them on the job: hub-and-spoke perimeter design and DDoS protection (Lesson 7), private DNS for private endpoints (Lesson 6), and analytics rules, KQL hunting, workbooks, and notebooks in Microsoft Sentinel (Lesson 14).

[Course README](../README.md)
