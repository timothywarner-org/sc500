# Lesson 03: Key Vault, Azure Policy, Compliance, Backup, and Infrastructure as Code

**Exam SC-500 domain:** Manage identity, access, and governance (20-25%)  
**Study guide sections:** Secure secrets and keys by using Azure Key Vault; Implement governance to enforce security and regulatory compliance

## Learning objectives

- 3.1 Deploy Azure Key Vault; configure its settings, access permissions, and firewall rules; and manage keys, secrets, and certificates
- 3.2 Scan for exposed secrets using Defender Cloud Security Posture Management (Defender CSPM), and implement Defender for Key Vault
- 3.3 Implement Azure Policy controls using built-in and custom policy definitions. Evaluate regulatory compliance and implement and configure Defender for Cloud security controls, including security standards and recommendations
- 3.4 Configure Azure Backup security features and implement security controls using infrastructure as code integrated with Azure Policy guardrails

## Hands-on practice

Every demo in this lesson is work you can repeat in your own subscription, mostly in the Azure portal or the Microsoft admin centers. Do each one yourself after you watch it, because clicking through a configuration sticks far better than reading about it.

**Step by step:** the [lab guide](lab-guide.md) lists every portal step and command from this lesson's demos, in the order the video runs them.

The scripts and Bicep templates from this lesson's demos are published: [`demos/`](demos/) lists them by stage and links to their folders under `lab/`. Do the [one-time lab setup](../../lab/README.md) first.

## Before you start

- An Azure subscription you control, ideally a dedicated sandbox with a budget alert
- Two resource groups just for this lesson; [Clean up](#clean-up) covers the backup vault, which needs care
- Defender CSPM and Defender for Key Vault are paid Defender for Cloud plans, so turn them off when you finish.

## Clean up

Lesson 3 has no `Remove-` script, so cleanup is by hand.

1. When you finish the demos, close the lesson's window. This deallocates the runner VM, removes the temporary NAT gateway and its public IP, and sets the two paid Defender plans back to their parked state. Run it with `-WhatIf` first to see each change.

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Set-L03ScanWindow.ps1 -State Close -WhatIf
   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-03\Set-L03ScanWindow.ps1 -State Close
   ```

2. When you no longer need the lab, empty the Recovery Services vault `rsv-sc500-l03` before you delete anything else. Open the vault's **Overview**, select **Delete**, and follow the steps it lists to stop backup and delete the backup data. If you protected the vault with the lesson's Resource Guard, you need that guard's permissions first. The vault can't be deleted while a backup item is soft-deleted, which lasts 14 days by default. See [Delete an Azure Backup Recovery Services vault](https://learn.microsoft.com/azure/backup/backup-azure-delete-vault).
3. Then delete both resource groups. Each command asks you to confirm.

   ```powershell
   az group delete --name rg-sc500-l03-platform --subscription <your-subscription-id>
   az group delete --name rg-sc500-l03-policy --subscription <your-subscription-id>
   ```

## Go deeper

- [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500)
- [Curated Microsoft Learn links for this course](../../docs/resources.md)

[Course README](../../README.md) | [Exam objective map](../../docs/exam-objectives.md)
