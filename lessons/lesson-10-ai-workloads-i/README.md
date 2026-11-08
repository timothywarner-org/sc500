# Lesson 10: Secure AI Workloads I: Data Overexposure, Copilot, and Microsoft Entra Agent ID

**Exam SC-500 domain:** Secure compute (20-25%)  
**Study guide sections:** Implement security for AI

## Learning objectives

- 10.1 Identify data overexposure in SharePoint and risks related to Microsoft Copilot and AI apps using Microsoft Purview DSPM
- 10.2 Enable and configure real-time protection for Microsoft Copilot Studio agents, and manage agents in the Microsoft 365 admin center
- 10.3 Implement Conditional Access for Microsoft Entra Agent ID, and manage Entra Agent ID access throughout the agent lifecycle
- 10.4 Analyze the blast radius of security risks related to Entra Agent ID using Microsoft Defender XDR

## Hands-on practice

Every demo in this lesson is work you can repeat in your own subscription, mostly in the Azure portal or the Microsoft admin centers. Do each one yourself after you watch it, because clicking through a configuration sticks far better than reading about it.

The scripts and Bicep templates from this lesson's demos are published: [`demos/`](demos/) lists them by stage and links to their folders under `lab/`. Do the [one-time lab setup](../../lab/README.md) first.

## Before you start

- An Azure subscription you control, ideally a dedicated sandbox with a budget alert
- A resource group just for this lesson, so cleanup is a single delete
- This lesson spans Microsoft 365, Microsoft Purview, Copilot Studio, and Microsoft Entra, so you need a Microsoft 365 tenant with matching licenses. Applying Microsoft Entra security features such as Conditional Access to agents also requires Microsoft Agent 365. Check the licensing section of each Microsoft Learn page before you start.

## Go deeper

- [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500)
- [Curated Microsoft Learn links for this course](../../docs/resources.md)

[Course README](../../README.md) | [Exam objective map](../../docs/exam-objectives.md)
