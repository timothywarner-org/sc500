# SC-500: Cloud and AI Security Engineer Associate — Course Companion

> **Exam companion repository for the Pearson / Microsoft Press video course taught by [Tim Warner](https://timw.info), Microsoft MVP.**
>
> 15 lessons · ~10 hours runtime · 100% aligned to the official Microsoft *Skills Measured* document for **Exam SC-500**.

[![Microsoft Learn](https://img.shields.io/badge/Microsoft%20Learn-SC--500-0078D4?logo=microsoft)](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/sc-500)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Course Status](https://img.shields.io/badge/status-in%20production-yellow)]()
[![Beta Exam](https://img.shields.io/badge/Beta%20Exam-May%202026-blue)]()

---

## About this repository

This repo is the **optional but recommended companion** to the video course *Exam SC-500: Cloud and AI Security Engineer Associate (Video)*, published by Pearson under the Microsoft Press imprint. The course teaches every published objective on Microsoft's SC-500 exam, the successor to AZ-500.

Inside, you will find:

- A folder per lesson with hands-on demo scripts, Azure CLI / PowerShell commands, and ARM / Bicep / Terraform snippets
- A consolidated objectives map showing exactly which lesson covers which Microsoft Functional Group (FG) sub-domain
- Curated links to Microsoft Learn, Microsoft Defender for Cloud documentation, Microsoft Sentinel content hub solutions, and Microsoft Security Copilot guidance
- Practice scenarios and a study schedule template you can copy into your tool of choice

> **Heads up:** This repo is in active development alongside the course recording. Content lands lesson by lesson as the videos are produced. Star and watch the repo to track updates.

---

## Exam at a glance

| | |
|---|---|
| **Exam code** | SC-500 |
| **Full title** | Microsoft Certified: Cloud and AI Security Engineer Associate |
| **Successor to** | AZ-500 (retires August 31, 2026) |
| **Beta exam window** | May 2026 |
| **General availability** | July 2026 |
| **Format** | Multiple choice, case studies, scenario-based |
| **Official study guide** | [SC-500 Skills Measured (Microsoft)](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/sc-500) |

### Skills measured (published weights)

| Functional group | Weight | Lessons |
|---|---|---|
| Manage identity, access, and governance | 20-25% | 1, 2, 3 |
| Secure storage, databases, and networking | 25-30% | 4, 5, 6, 7 |
| Secure compute (including AI workloads) | 20-25% | 8, 9, 10, 11 |
| Manage and monitor security posture | 20-25% | 12, 13, 14, 15 |

---

## Course outline

| # | Lesson | Maps to |
|---|---|---|
| 1 | [Identity Foundations: PIM, RBAC, Custom Roles, and Governance Scope](lessons/lesson-01-identity-foundations/) | FG1.1, FG1.3 |
| 2 | [Entra ID Access: MFA, Conditional Access, Apps, and Managed Identities](lessons/lesson-02-entra-id-access/) | FG1.1 |
| 3 | [Key Vault, Azure Policy, Compliance, Backup, and IaC](lessons/lesson-03-keyvault-policy-iac/) | FG1.2, FG1.3 |
| 4 | [Secure Storage and Databases](lessons/lesson-04-storage-databases/) | FG2.1, FG2.2 |
| 5 | [Network Segmentation: NSGs, ASGs, AVNM, Virtual WAN, VPN](lessons/lesson-05-network-segmentation/) | FG2.3 |
| 6 | [Private Connectivity: Private Link, Private Endpoints, Entra Private Access](lessons/lesson-06-private-connectivity/) | FG2.3 |
| 7 | [Perimeter Protection: Azure Firewall and Network Watcher](lessons/lesson-07-perimeter-protection/) | FG2.3 |
| 8 | [Secure Servers and Virtual Machines](lessons/lesson-08-servers-vms/) | FG3.2, FG4.1 |
| 9 | [Secure Application Platform Services: Containers, Serverless, App Service, WAF, APIM](lessons/lesson-09-app-platform/) | FG3.3 |
| 10 | [Secure AI Workloads I: Data Overexposure, Copilot, Entra Agent ID](lessons/lesson-10-ai-workloads-i/) | FG3.1 |
| 11 | [Secure AI Workloads II: Foundry, AI Gateway, Defender for AI](lessons/lesson-11-ai-workloads-ii/) | FG3.1 |
| 12 | [Manage Posture with Defender for Cloud and Multicloud](lessons/lesson-12-defender-cloud-multicloud/) | FG4.1 |
| 13 | [Microsoft Sentinel I: Workspace, Connectors, Log Ingestion](lessons/lesson-13-sentinel-i/) | FG4.2 |
| 14 | [Microsoft Sentinel II: Analytics, Automation, KQL, Purview Audit](lessons/lesson-14-sentinel-ii/) | FG4.2 |
| 15 | [Microsoft Security Copilot for Cloud and AI Defenders](lessons/lesson-15-security-copilot/) | FG4.3 |

See the full mapping in [`docs/exam-objectives.md`](docs/exam-objectives.md).

---

## How to use this repo

### If you're watching the videos

1. Open the lesson folder that matches the video you're watching.
2. Use the `README.md` in that lesson folder as your hands-on guide.
3. The demo scripts are idempotent and parameterized — clone them into your own sandbox subscription and run them as written, or modify the parameters at the top of each file.

### If you're prepping for the exam without the videos

1. Start with [`docs/exam-objectives.md`](docs/exam-objectives.md) and self-rate each sub-domain on a 1-5 confidence scale.
2. For any sub-domain below a 4, open the matching lesson folder and work through the demo scripts on your own subscription.
3. Use [`docs/study-plan-template.md`](docs/study-plan-template.md) as a 30-, 60-, or 90-day study calendar.

### If you're a corporate L&D buyer

Tim's content is licensed for individual learner use under MIT (see [LICENSE](LICENSE)). For enterprise team licensing through Pearson, ACM Learning Center, or O'Reilly, contact your account representative or reach Tim directly via [timw.info](https://timw.info).

---

## Prerequisites

To run the demos in your own subscription you need:

- An **Azure subscription** with Owner or Contributor at the subscription scope (sandbox or pay-as-you-go is fine; budget alerts strongly recommended)
- **Azure CLI** 2.60+ ([install](https://learn.microsoft.com/cli/azure/install-azure-cli))
- **Azure PowerShell** Az 11+ ([install](https://learn.microsoft.com/powershell/azure/install-azps-windows))
- **Microsoft Entra ID** P1 or P2 license for Conditional Access and Privileged Identity Management demos
- **Microsoft Defender for Cloud** enabled (Free tier is fine for posture management; certain demos require enhanced security features)
- **Microsoft Sentinel** workspace (a Log Analytics workspace plus the Sentinel solution)
- A working knowledge of Azure resource hierarchy, networking, and identity at the AZ-104 level

---

## Repository structure

```
sc500/
├── README.md                          ← you are here
├── LICENSE                            ← MIT
├── CONTRIBUTING.md                    ← how to report issues and submit fixes
├── CHANGELOG.md                       ← lesson-by-lesson publication log
├── docs/
│   ├── exam-objectives.md             ← full SC-500 objective domain map
│   ├── study-plan-template.md         ← 30/60/90 day calendar template
│   └── resources.md                   ← curated Microsoft Learn and external links
├── lessons/
│   ├── lesson-01-identity-foundations/
│   ├── lesson-02-entra-id-access/
│   ├── ... (one folder per lesson)
│   └── lesson-15-security-copilot/
├── demos/
│   └── (demo scripts and ARM/Bicep/Terraform artifacts)
└── .github/
    └── ISSUE_TEMPLATE/                ← typo, broken link, content question
```

---

## Author

**Tim Warner** is a Microsoft MVP in **Azure AI** and **Cloud and Datacenter Management**, Principal Staff Author at Pluralsight (200+ courses, 1M+ learners), Live Learning Instructor at O'Reilly, and Senior Content Developer at Pearson. He has trained Microsoft certification candidates since the days when 70-290 was a thing.

- Website: [timw.info](https://timw.info)
- YouTube: [@TechTrainerTim](https://www.youtube.com/@TechTrainerTim)
- Bluesky: [@techtrainertim.bsky.social](https://bsky.app/profile/techtrainertim.bsky.social)
- LinkedIn: [in/timothywarner](https://www.linkedin.com/in/timothywarner/)

---

## How to study (the three-pillar method)

Tim tells every certification student to balance three pillars:

1. **Theoretical knowledge** — this course, Microsoft Learn, the published study guide
2. **Hands-on experience** — your own Azure sandbox, the demo scripts in this repo
3. **Practice exam review** — [MeasureUp](https://www.measureup.com/) is Microsoft's official practice exam vendor

This repo gives you pillar 2. The video course gives you pillar 1. MeasureUp closes pillar 3.

---

## License

MIT — see [LICENSE](LICENSE). Course videos and Pearson-branded materials are separately licensed by Pearson and not redistributable.

---

## Acknowledgments

- **Microsoft Press** and **Pearson** for publishing this title
- **Laura Lewin** for editorial steering
- The Microsoft Defender, Sentinel, Foundry, and Entra teams for shipping the products this exam actually tests
- The thousands of certification candidates who have taken Tim's courses and asked the questions that made this material better

---

*Go earn that badge.* 🎯
