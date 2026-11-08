# Changelog

All notable changes to this course companion repository are tracked here. This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses [Semantic Versioning](https://semver.org/) loosely, scoped to course content rather than software.

## [Unreleased]

### Added (2026-11-08, Lessons 14 and 15)
- `lab/scripts/lesson-14`, `lab/infra/lesson-14`: the Microsoft Sentinel analytics rule, automation rule, response playbook, hunting queries, workbook, and Purview Audit demo scripts.
- `lab/scripts/lesson-15`, `lab/infra/lesson-15`: the Security Copilot cost guard (a deadline tag plus a reaper logic app that deletes an expired capacity), the ServiceHub KQL plugin manifest, and the read-only demo readouts.
- A `demos/README.md` page for Lessons 14 and 15.

### Changed (2026-11-08, easier to adapt)
- `Set-LabConfig.ps1` takes a required `-NameSuffix` (3 to 5 lowercase letters or digits). Storage accounts, key vaults, container registries, App Service and Functions apps, API Management, and Foundry accounts now end in `<your-name-suffix>` instead of `001`, so two learners can't collide on a name Azure requires to be unique across all customers. Names Azure scopes to your subscription keep `001` and match the video.
- `lab/README.md` covers the name suffix, Security Copilot and Sentinel costs, and how to change a lab's region.
- Script help and comments speak to you. The instructor's subscription name is gone, and recording-session wording such as takes and demo cards now reads as demo steps.

### Added (2026-11-08, lab files)
- `lab/`: the scripts and Bicep templates from the demos in Lessons 1 through 13, as the lessons promise. Tenant, subscription, domain, and account values are placeholders.
- `lab/Set-LabConfig.ps1`: writes your own values into every lab file in one step, with `-WhatIf`.
- `lab/README.md`: one-time setup, tools, placeholders, and cost warnings.
- A `demos/README.md` page for each of Lessons 1 through 13 that lists its scripts by stage, with each script's own synopsis.

### Changed (2026-11-08)
- Lesson READMEs regenerated from the frozen course outline: exact lesson titles and objectives, the study guide sections each lesson covers, and setup and cost notes.
- Exam objective map rebuilt from Microsoft's current study guide (last updated 2026-05-13), with every skill mapped to a lesson.
- README updated with the official exam and certification names, the AZ-500 retirement, practice assessment status, the standard author bio, and TechTrainerTim.com.
- Study plan rebalanced so the 30-, 60-, and 90-day schedules each total about 40 hours.
- Resources regrouped by exam domain, with links for Defender for Key Vault, Defender for Storage, Azure Backup security, Microsoft Entra Private Access, just-in-time VM access, Azure Machine Configuration, and Sentinel automation.
- Demo and contribution conventions now describe portal-first walkthroughs with one settings block for learner values.

### Removed (2026-11-08)
- Beta exam and "in production" badges, the beta and general availability rows, and the corporate licensing section.
- An unverified claim about an official SC-500 practice exam vendor.

### Added
- NOTICE.md with license, publisher, trademark, and fictional-data notices (2026-11-08).
- Lesson 2 instructor federation proof: manually dispatched OIDC exchange, resource-group read, and rejected tag write.
- Initial repository scaffold: README, license, contribution guide, exam objective map
- Lesson folders 1 through 15
- Issue templates for typos, broken links, and content questions
- Study plan template for 30-, 60-, and 90-day schedules

### Notes
- Walkthroughs and lab files land lesson by lesson after each lesson publishes.
