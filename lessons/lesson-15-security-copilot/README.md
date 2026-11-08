# Lesson 15: Microsoft Security Copilot for Cloud and AI Defenders

**Exam SC-500 domain:** Manage and monitor security posture (20-25%)  
**Study guide sections:** Implement Microsoft Security Copilot

## Learning objectives

- 15.1 Configure workspaces for Microsoft Security Copilot
- 15.2 Manage permissions and roles in Microsoft Security Copilot
- 15.3 Enable and configure Security Copilot plugins for Microsoft Defender XDR, Microsoft Sentinel, Microsoft Intune, Microsoft Entra, and selected third-party security products
- 15.4 Enable and configure Microsoft agents and Security Store agents in Security Copilot for triage, KQL generation, incident summarization, and assisted response

## Hands-on practice

Every demo in this lesson is work you can repeat in your own subscription, mostly in the Azure portal or the Microsoft admin centers. Do each one yourself after you watch it, because clicking through a configuration sticks far better than reading about it.

**Step by step:** the [lab guide](lab-guide.md) lists every portal step and command from this lesson's demos, in the order the video runs them.

The scripts and Bicep templates from this lesson's demos are published: [`demos/`](demos/) lists them by stage and links to their folders under `lab/`. Do the [one-time lab setup](../../lab/README.md) first.

## Before you start

- An Azure subscription you control, ideally a dedicated sandbox with a budget alert
- A resource group just for this lesson, so cleanup is a single delete
- Microsoft Security Copilot runs on Security Compute Units (SCUs). Find out how your organization gets capacity before you provision any, because provisioned SCUs bill by the hour.
- This lesson investigates the incident your Lesson 14 lab raises, in your Lesson 13 workspace, so build those first.
- Deploy the lesson's guard first (`Deploy-L15Lab.ps1`), then create one provisioned SCU with overage at 0 and run `Start-L15CopilotSession.ps1` to put a deadline on it. A small logic app deletes the capacity once the deadline passes, so a forgotten capacity stops billing on its own. Run `Stop-L15CopilotSession.ps1` the moment you finish.

## Go deeper

- [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500)
- [Curated Microsoft Learn links for this course](../../docs/resources.md)

[Course README](../../README.md) | [Exam objective map](../../docs/exam-objectives.md)
