# Lesson 14: Microsoft Sentinel II: Analytics, Automation, KQL Hunting, and Purview Audit

**Exam SC-500 domain:** Manage and monitor security posture (20-25%)  
**Study guide sections:** Implement activity and event collection in Microsoft Sentinel

## Learning objectives

- 14.1 Create and tune analytics rules to support the investigation workflow
- 14.2 Implement Microsoft Sentinel automation rules and Logic Apps playbooks
- 14.3 Write Kusto Query Language (KQL) queries for threat hunting, and use workbooks and notebooks to support investigation and reporting
- 14.4 Query Microsoft Purview Audit in Defender XDR and use the results in end-to-end incident investigation

## Hands-on practice

Every demo in this lesson is work you can repeat in your own subscription, mostly in the Azure portal or the Microsoft admin centers. Do each one yourself after you watch it, because clicking through a configuration sticks far better than reading about it.

**Step by step:** the [lab guide](lab-guide.md) lists every portal step and command from this lesson's demos, in the order the video runs them.

The scripts and Bicep templates from this lesson's demos are published: [`demos/`](demos/) lists them by stage and links to their folders under `lab/`. Do the [one-time lab setup](../../lab/README.md) first.

## Before you start

- An Azure subscription you control, ideally a dedicated sandbox with a budget alert
- A resource group just for this lesson, so cleanup is a single delete
- This lesson builds on your Lesson 13 Microsoft Sentinel workspace. Logic Apps playbooks bill per run.
- The Purview Audit demo needs auditing turned on for your tenant. [Turning it on](https://learn.microsoft.com/purview/audit-log-enable-disable#turn-on-auditing) can take up to 60 minutes to take effect, and a new activity can take longer still to reach search, so stage the audit file well ahead.

## Go deeper

- [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500)
- [Curated Microsoft Learn links for this course](../../docs/resources.md)

[Course README](../../README.md) | [Exam objective map](../../docs/exam-objectives.md)
