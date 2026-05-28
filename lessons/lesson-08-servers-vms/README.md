# Lesson 08: Secure Servers and Virtual Machines

**Maps to:** FG3.2, FG4.1
**Estimated runtime:** ~40 minutes (video) + ~30-60 minutes (hands-on)

---

## Learning objectives

By the end of this lesson you can:

- Implement disk encryption (Azure Disk Encryption, host-based) and VM security features
- Plan Azure Bastion for RDP/SSH without public IPs, and enable JIT VM access through Defender for Cloud
- Extend controls to hybrid/multicloud servers using Azure Arc, onboard Defender for Servers Plan 1/2, configure vulnerability scanning, agentless scanning, and EDR with Defender for Endpoint
- Enforce config via Azure Machine Configuration and tune Defender Vulnerability Management

---

## Why this lesson matters on the exam

The SC-500 exam tests these objectives in scenario-based items. Expect questions that give you a business requirement and ask you to pick the right Microsoft service, the right configuration, or the right remediation. The demos in this folder are designed to make those decisions feel obvious.

---

## Demo runbook

The `demos/` subfolder will contain hands-on scripts as the video course is recorded. Planned demos:

- [ ] **08.1** — Implement disk encryption (Azure Disk Encryption, host-based) and VM security features
- [ ] **08.2** — Plan Azure Bastion for RDP/SSH without public IPs, and enable JIT VM access through Defender for Cloud
- [ ] **08.3** — Extend controls to hybrid/multicloud servers using Azure Arc, onboard Defender for Servers Plan 1/2, configure vulnerability scanning, agentless scanning, and EDR with Defender for Endpoint
- [ ] **08.4** — Enforce config via Azure Machine Configuration and tune Defender Vulnerability Management

Each demo lands as an idempotent script (PowerShell + Azure CLI equivalents) with cleanup at the end. Watch this repo's [CHANGELOG](../../CHANGELOG.md) for the publication schedule.

---

## Prerequisites for the demos

- Azure subscription with Owner or Contributor at the subscription scope
- A resource group dedicated to this lesson (the demos will create one named `rg-sc500-l08`)
- Tools: Azure CLI 2.60+, Azure PowerShell Az 11+, the active subscription set to your sandbox

---

## Further reading

See [docs/resources.md](../../docs/resources.md) for the curated Microsoft Learn links that back this lesson.

---

[← Course README](../../README.md) · [Full objective map →](../../docs/exam-objectives.md)
