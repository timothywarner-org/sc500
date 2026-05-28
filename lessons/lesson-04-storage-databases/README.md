# Lesson 04: Secure Storage and Databases

**Maps to:** FG2.1, FG2.2
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Implement and configure security for Azure Storage accounts (network rules, encryption, SAS, identity-based access)
- Implement Microsoft Defender for Storage threat protection
- Implement platform-level security configurations in Azure SQL (authentication, auditing, TDE)
- Configure Microsoft Defender for Databases across Azure SQL Database, SQL Managed Instance, PostgreSQL, MySQL, and Cosmos DB

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **04.1** — Implement and configure security for Azure Storage accounts (network rules, encryption, SAS, identity-based access)
- [ ] **04.2** — Implement Microsoft Defender for Storage threat protection
- [ ] **04.3** — Implement platform-level security configurations in Azure SQL (authentication, auditing, TDE)
- [ ] **04.4** — Configure Microsoft Defender for Databases across Azure SQL Database, SQL Managed Instance, PostgreSQL, MySQL, and Cosmos DB

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l04`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
