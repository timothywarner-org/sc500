# Contributing

Thanks for helping make this course companion better! This repo accepts fixes from anyone working through the SC-500 course or the SC-500 exam itself.

## What to submit

**Yes please:**

- Typos, broken links, dead Microsoft Learn URLs
- Demo scripts that no longer work because a service changed
- Clarifications on Microsoft Defender for Cloud, Microsoft Sentinel, or Microsoft Foundry behavior you discovered while studying
- Additional `az` / `Az` / Bicep / Terraform equivalents for the same demo
- Exam-realistic practice scenarios (no live exam content — see below)

**Please don't submit:**

- Verbatim or paraphrased exam questions from any live or beta SC-500 exam. This violates the [Microsoft Certification Exam Policies](https://learn.microsoft.com/credentials/certifications/certification-exam-policies) and the Pearson VUE NDA you accepted when sitting the exam.
- Promotional content for other courses or products
- Off-topic Azure content that doesn't map to a published SC-500 sub-domain

## How to submit

1. **For small fixes** (typos, broken links): open an issue using the *Typo or broken link* template, or send a pull request directly.
2. **For demo fixes or new content**: open an issue first using the *Content question or demo issue* template so we can scope the change before you spend time on it.
3. **For larger contributions**: ping [@timothywarner](https://github.com/timothywarner) on the issue thread before opening a PR.

## Style

- Demo scripts in PowerShell follow the project conventions: `Verb-Noun` cmdlet naming, `[CmdletBinding()]`, comment-based help, parameter validation, idempotent.
- Bash and Azure CLI demos use `set -euo pipefail` and the parameter block at the top of the file.
- Bicep and Terraform follow Microsoft's [Azure naming convention](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming).
- Markdown uses GitHub-flavored Markdown. Tables for lists of three or more items. Code fences with language hints.
- All demos are **idempotent and self-cleaning**. Include a `Remove-` / `az ... delete` block at the end of every demo so learners don't accumulate orphan resources.

## Code of conduct

Be kind. Assume good faith. Disagree with ideas, not with people. The full [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/) applies.
