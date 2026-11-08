# Lesson 12: Manage Posture with Microsoft Defender for Cloud and Multicloud

**Exam SC-500 domain:** Manage identity, access, and governance (20-25%); Manage and monitor security posture (20-25%)  
**Study guide sections:** Implement governance to enforce security and regulatory compliance; Manage security posture by using Defender for Cloud

## Learning objectives

- 12.1 Identify security risks using Defender CSPM and evaluate compliance against security frameworks in Defender for Cloud
- 12.2 Enable and configure Defender for Cloud workload protection plans
- 12.3 Connect hybrid cloud and multicloud environments to Defender for Cloud, including both external cloud providers specified by the current SC-500 study guide
- 12.4 Discover unprotected assets and vulnerabilities using Microsoft Defender EASM

## Hands-on practice

Every demo in this lesson is work you can repeat in your own subscription, mostly in the Azure portal or the Microsoft admin centers. Do each one yourself after you watch it, because clicking through a configuration sticks far better than reading about it.

The scripts and Bicep templates from this lesson's demos are published: [`demos/`](demos/) lists them by stage and links to their folders under `lab/`. Do the [one-time lab setup](../../lab/README.md) first.

## Before you start

- An Azure subscription you control, ideally a dedicated sandbox with a budget alert
- A resource group just for this lesson, so cleanup is a single delete
- Connecting AWS and GCP needs accounts in those clouds. Defender CSPM and Defender EASM are paid, so check current pricing before you enable them.

## Go deeper

- [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500)
- [Curated Microsoft Learn links for this course](../../docs/resources.md)

[Course README](../../README.md) | [Exam objective map](../../docs/exam-objectives.md)
