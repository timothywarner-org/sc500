# Exam SC-500: Cloud and AI Security Engineer Associate (Video)

[![Study guide checked](https://img.shields.io/badge/study%20guide-checked%202026--11--08-0078D4?style=for-the-badge)](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500)
[![License: MIT](https://img.shields.io/badge/license-MIT-2EA44F?style=for-the-badge)](LICENSE)
[![Website](https://img.shields.io/badge/website-TechTrainerTim.com-24292F?style=for-the-badge)](https://techtrainertim.com)
[![GitHub](https://img.shields.io/badge/GitHub-timothywarner--org-24292F?style=for-the-badge&logo=github)](https://github.com/timothywarner-org)

Tim Warner | Pearson video course, Microsoft Press imprint | Companion repository

**Secure Azure, hybrid, multicloud, and AI workloads end to end, and walk into Exam SC-500 knowing why each control exists.**

How do you prove that a managed identity can read a resource group but not change it? What stops a Copilot agent from reading a SharePoint site it should never see? When Microsoft Sentinel fires an incident at 2:00 AM, what runs before a human wakes up? This course answers those questions with working demos, and this repository is where you practice them.

**Watching the videos?** Open the lesson folder that matches the lesson you are on. Each folder lists the exact objectives, the study guide sections they cover, and what to line up before you start.

**Studying without the videos?** Start with the [exam objective map](docs/exam-objectives.md). Rate yourself on every skill, then spend your time on anything below a 4.

**Want the code?** Every script and Bicep template from the demos in all 15 lessons is in [`lab/`](lab/). Do the [one-time setup](lab/README.md), then open a lesson's `demos/` page for its scripts. The [changelog](CHANGELOG.md) tracks every change.

## Course outline

| Lesson | Title | Study guide domain |
| --- | --- | --- |
| 1 | [Identity Foundations: PIM, RBAC, Custom Roles, and Governance Scope](lessons/lesson-01-identity-foundations/) | Manage identity, access, and governance |
| 2 | [Entra ID Access: MFA, Conditional Access, Apps, and Managed Identities](lessons/lesson-02-entra-id-access/) | Manage identity, access, and governance |
| 3 | [Key Vault, Azure Policy, Compliance, Backup, and Infrastructure as Code](lessons/lesson-03-keyvault-policy-iac/) | Manage identity, access, and governance |
| 4 | [Secure Storage and Databases](lessons/lesson-04-storage-databases/) | Secure storage, databases, and networking |
| 5 | [Network Segmentation: NSGs, ASGs, Virtual Network Manager, Virtual WAN, and VPN](lessons/lesson-05-network-segmentation/) | Secure storage, databases, and networking |
| 6 | [Private Connectivity: Private Link, Private Endpoints, and Microsoft Entra Private Access](lessons/lesson-06-private-connectivity/) | Secure storage, databases, and networking |
| 7 | [Perimeter Protection: Azure Firewall and Network Watcher Diagnostics](lessons/lesson-07-perimeter-protection/) | Secure storage, databases, and networking |
| 8 | [Secure Servers and Virtual Machines](lessons/lesson-08-servers-vms/) | Secure compute; Manage and monitor security posture |
| 9 | [Secure Application Platform Services: Containers, Serverless, App Service, WAF, and API Management](lessons/lesson-09-app-platform/) | Secure compute |
| 10 | [Secure AI Workloads I: Data Overexposure, Copilot, and Microsoft Entra Agent ID](lessons/lesson-10-ai-workloads-i/) | Secure compute |
| 11 | [Secure AI Workloads II: Microsoft Foundry, AI Gateway, and Defender for AI](lessons/lesson-11-ai-workloads-ii/) | Secure compute |
| 12 | [Manage Posture with Microsoft Defender for Cloud and Multicloud](lessons/lesson-12-defender-cloud-multicloud/) | Manage and monitor security posture; Manage identity, access, and governance |
| 13 | [Microsoft Sentinel I: Workspace, Connectors, and Log Ingestion](lessons/lesson-13-sentinel-i/) | Manage and monitor security posture |
| 14 | [Microsoft Sentinel II: Analytics, Automation, KQL Hunting, and Purview Audit](lessons/lesson-14-sentinel-ii/) | Manage and monitor security posture |
| 15 | [Microsoft Security Copilot for Cloud and AI Defenders](lessons/lesson-15-security-copilot/) | Manage and monitor security posture |

The [exam objective map](docs/exam-objectives.md) goes one level deeper and ties every skill in Microsoft's study guide to the lesson that teaches it.

## Exam at a glance

| Item | Detail |
| --- | --- |
| Exam | SC-500: Implementing End-to-End Security Controls for Cloud and AI Workloads |
| Certification | Microsoft Certified: Cloud and AI Security Engineer Associate |
| Replaces | AZ-500, which retired on August 31, 2026 |
| Passing score | 700 |
| Official study guide | [Exam SC-500 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/sc-500) (Microsoft's page shows "Last updated on 2026-05-13") |
| Free practice assessment | Not available yet (checked November 8, 2026). Check the [certification page](https://learn.microsoft.com/credentials/certifications/cloud-and-ai-security-engineer-associate/) for updates. |

### Skills measured

| Domain | Weight | Lessons |
| --- | --- | --- |
| Manage identity, access, and governance | 20-25% | 1, 2, 3, 12 |
| Secure storage, databases, and networking | 25-30% | 4, 5, 6, 7 |
| Secure compute | 20-25% | 8, 9, 10, 11 |
| Manage and monitor security posture | 20-25% | 8, 12, 13, 14, 15 |

Lesson 8 shows up twice because Defender Vulnerability Management for Azure VMs sits in the posture domain. Lesson 12 shows up twice because regulatory compliance in Defender for Cloud sits in the governance domain.

## How the hands-on work runs

Most demos happen in the Azure portal and the Microsoft admin centers, because that is where you build the muscle memory the exam rewards. When a demo uses a Bicep template or a script, you get the same file the lesson runs on screen, and its help says what it reads and what it changes. Your tenant, subscription, domain, and a short name suffix go in once with [`lab/Set-LabConfig.ps1`](lab/Set-LabConfig.ps1), and every resource name comes from the lesson's `config.json`.

Every lesson has a `Remove-` script that deletes what its lab created. Several lessons use paid Defender plans and hourly resources, so each lesson README lists what to watch before you start.

## Before you start

- An **Azure subscription** where you hold Owner at the subscription scope. A dedicated sandbox with a budget alert is the right call.
- A **Microsoft Entra tenant** you administer. Privileged Identity Management needs Microsoft Entra ID P2 or Microsoft Entra ID Governance, and Conditional Access needs P1 or P2.
- A **Microsoft 365 tenant** for Lesson 10 (SharePoint, Microsoft Purview, Copilot Studio, and the Microsoft 365 admin center).
- **Microsoft Defender for Cloud** on your subscription. Foundational CSPM is free; the workload protection plans and Defender CSPM are paid.
- Optional: [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and [Azure PowerShell](https://learn.microsoft.com/powershell/azure/install-azure-powershell) for the steps that use them.
- Working knowledge of Azure resources, networking, and identity at roughly the AZ-104 level.

## How to study: the three pillars

Every study week, touch all three:

1. **Theory**: the video course, Microsoft Learn, and the official study guide.
2. **Hands-on experience**: your own sandbox and the lab files in this repository.
3. **Practice questions**: timed questions with a full review of every miss. Microsoft's free practice assessment for SC-500 was not available when this page was checked, so watch the certification page.

The [study plan template](docs/study-plan-template.md) lays out 30-, 60-, and 90-day schedules that each come to about 40 hours.

## What is in this repository

- [`lessons/`](lessons/): one folder per lesson, each with a README and a `demos/` page that lists its lab files
- [`lab/`](lab/): every script and Bicep template from the demos in all 15 lessons, plus the one-time setup
- [`docs/exam-objectives.md`](docs/exam-objectives.md): every study guide skill mapped to a lesson, with a self-rating column
- [`docs/study-plan-template.md`](docs/study-plan-template.md): 30-, 60-, and 90-day schedules
- [`docs/resources.md`](docs/resources.md): curated Microsoft Learn links by exam domain
- [`demos/`](demos/): demo material that spans more than one lesson
- [`CHANGELOG.md`](CHANGELOG.md): what changed and when
- [`CONTRIBUTING.md`](CONTRIBUTING.md): how to report a problem or send a fix
- [`NOTICE.md`](NOTICE.md) and [`LICENSE`](LICENSE): license, publisher, and trademark notices

## About the author

**Tim Warner** is a Microsoft MVP, a Microsoft Certified Trainer since 1997, and a Principal Staff Author at Pluralsight with more than 200 courses and over a million learners. He teaches live courses for Pearson and O'Reilly, and he builds and ships MCP servers. His teaching model comes from Richard Feynman: start from first principles, prove the idea with a working demo, and keep the examples close to real enterprise work.

You can find his video courses on [Pluralsight](https://www.pluralsight.com/authors/tim-warner), short tutorials on [YouTube](https://www.youtube.com/@TechTrainerTim), more course repositories on [GitHub](https://github.com/timothywarner-org), and everything else at [TechTrainerTim.com](https://techtrainertim.com). Connect with him on [LinkedIn](https://www.linkedin.com/in/timothywarner).

## Acknowledgments

- **Microsoft Press** and **Pearson** for publishing this title
- **Laura Lewin** for editorial steering
- The Microsoft Entra, Defender, Sentinel, Purview, and Foundry teams for shipping the products this exam tests
- Every certification candidate who asked the question that made this material better

## License

The code and documentation in this repository are released under the [MIT License](LICENSE). The course videos and Pearson materials are licensed separately by Pearson. See [NOTICE.md](NOTICE.md) for publisher and trademark notices.

*Go earn that badge.*
