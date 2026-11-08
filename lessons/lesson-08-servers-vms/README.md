# Lesson 08: Secure Servers and Virtual Machines

**Exam SC-500 domain:** Secure compute (20-25%); Manage and monitor security posture (20-25%)  
**Study guide sections:** Implement security for servers and virtual machines (VMs); Manage security posture by using Defender for Cloud

## Learning objectives

- 8.1 Implement and configure disk encryption, prioritizing encryption at host for new VMs. Configure secure boot, vTPM, integrity monitoring, and VM security type; explain the migration context for existing Azure Disk Encryption deployments
- 8.2 Plan and implement Azure Bastion for secure RDP and SSH access without public IPs, and enable and enforce JIT VM access through Defender for Cloud
- 8.3 Extend security controls to hybrid and multicloud servers using Azure Arc. Onboard them to Defender for Servers and configure vulnerability scanning, endpoint detection and response (EDR), and agentless VM scanning
- 8.4 Enforce security configuration of Azure-managed servers using Azure Machine Configuration, and configure Microsoft Defender Vulnerability Management settings for Azure VMs

## Hands-on practice

Every demo in this lesson is work you can repeat in your own subscription, mostly in the Azure portal or the Microsoft admin centers. Do each one yourself after you watch it, because clicking through a configuration sticks far better than reading about it.

The scripts and Bicep templates from this lesson's demos are published: [`demos/`](demos/) lists them by stage and links to their folders under `lab/`. Do the [one-time lab setup](../../lab/README.md) first.

## Before you start

- An Azure subscription you control, ideally a dedicated sandbox with a budget alert
- A resource group just for this lesson, so cleanup is a single delete
- Defender for Servers Plan 2 for just-in-time VM access and agentless scanning. Azure Arc onboarding needs a machine that runs outside Azure.

## Go deeper

- [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500)
- [Curated Microsoft Learn links for this course](../../docs/resources.md)

[Course README](../../README.md) | [Exam objective map](../../docs/exam-objectives.md)
