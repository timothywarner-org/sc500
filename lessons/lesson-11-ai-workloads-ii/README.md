# Lesson 11: Secure AI Workloads II: Microsoft Foundry, AI Gateway, and Defender for AI

**Exam SC-500 domain:** Secure compute (20-25%)  
**Study guide sections:** Implement security for AI

## Learning objectives

- 11.1 Configure and deploy AI Gateway in Azure API Management for Microsoft Foundry to protect model endpoints
- 11.2 Enable Defender for AI Service in the Cloud Workload Protection plans of Defender for Cloud
- 11.3 Configure guardrails for agent security in Microsoft Foundry, including content filters, custom blocklists, and prompt-injection protections
- 11.4 Monitor AI security using the Data and AI security dashboard in Defender for Cloud; inspect AI security events and audit evidence, and correlate relevant alerts with Sentinel incidents

## Hands-on practice

Every demo in this lesson is work you can repeat in your own subscription, mostly in the Azure portal or the Microsoft admin centers. Do each one yourself after you watch it, because clicking through a configuration sticks far better than reading about it.

**Step by step:** the [lab guide](lab-guide.md) lists every portal step and command from this lesson's demos, in the order the video runs them.

The scripts and Bicep templates from this lesson's demos are published: [`demos/`](demos/) lists them by stage and links to their folders under `lab/`. Do the [one-time lab setup](../../lab/README.md) first.

## Before you start

- An Azure subscription you control, ideally a dedicated sandbox with a budget alert
- A resource group just for this lesson, so cleanup is a single delete
- A Microsoft Foundry project with a model deployment, an Azure API Management instance for AI Gateway, and the Defender for AI Services plan.

## Go deeper

- [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500)
- [Curated Microsoft Learn links for this course](../../docs/resources.md)

[Course README](../../README.md) | [Exam objective map](../../docs/exam-objectives.md)
