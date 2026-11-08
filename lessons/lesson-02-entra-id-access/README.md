# Lesson 02: Entra ID Access: MFA, Conditional Access, Apps, and Managed Identities

**Exam SC-500 domain:** Manage identity, access, and governance (20-25%)  
**Study guide sections:** Secure access to resources by using Microsoft Entra ID

## Learning objectives

- 2.1 Implement and configure authentication methods, including MFA, passwordless authentication, and phishing-resistant credentials
- 2.2 Design and implement Conditional Access policies for user and workload access
- 2.3 Implement and configure identity for applications, including enterprise applications and app registrations, and manage OAuth permission grants and consent settings
- 2.4 Implement and configure system-assigned and user-assigned managed identities for Azure resources, and apply workload identity federation

## Hands-on practice

Every demo in this lesson is work you can repeat in your own subscription, mostly in the Azure portal or the Microsoft admin centers. Do each one yourself after you watch it, because clicking through a configuration sticks far better than reading about it.

**Step by step:** the [lab guide](lab-guide.md) lists every portal step and command from this lesson's demos, in the order the video runs them.

The scripts and Bicep templates from this lesson's demos are published: [`demos/`](demos/) lists them by stage and links to their folders under `lab/`. Do the [one-time lab setup](../../lab/README.md) first.

## Before you start

- An Azure subscription you control, ideally a dedicated sandbox with a budget alert
- Two resource groups and a few tenant objects just for this lesson; [Clean up](#clean-up) lists them all
- Microsoft Entra ID P1 or P2 for Conditional Access. Conditional Access for workload identities also needs Microsoft Entra Workload ID Premium.

## Clean up

Lesson 2 has no `Remove-` script, so cleanup is by hand. Lesson 10 uses Garth as an agent sponsor, so keep his account until you finish Lesson 10.

1. When you finish the demos, stop the container compute. This keeps the resource groups and both managed identities.

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Stop-L02Workload.ps1
   ```

2. When you no longer need the lab, delete its two resource groups. Each command asks you to confirm.

   ```powershell
   az group delete --name rg-sc500-l02-identity --subscription <your-subscription-id>
   az group delete --name rg-sc500-l02-target --subscription <your-subscription-id>
   ```

3. In the Microsoft Entra admin center, delete the tenant objects the lesson created:
   - Conditional Access policies `SC500-L02-Garth-PhishingResistant-REPORTONLY` and `SC500-L02-Workload-Risk-REPORTONLY`
   - App registrations `SC500-L02-Contoso-ServiceHub-API` and `SC500-L02-Contoso-ServiceHub-Client`
   - Group `SC500-L02-Passkey-Pilot`
   - User `sc500.garth@<your-domain>`, after Lesson 10
4. If you ran the [workload federation proof](../../demos/lesson-02-federation.md) in your fork, delete the `sc500-lesson02` environment under your fork's **Settings > Environments**.

## Go deeper

- [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500)
- [Curated Microsoft Learn links for this course](../../docs/resources.md)

[Course README](../../README.md) | [Exam objective map](../../docs/exam-objectives.md)
