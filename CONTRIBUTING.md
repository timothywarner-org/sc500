# Contributing

Thank you for helping make this course companion better. Fixes are welcome from anyone working through the SC-500 course or preparing for the exam.

## What to submit

**Yes, please:**

- Typos, broken links, and dead Microsoft Learn URLs
- Walkthrough steps that no longer match the portal because a service changed
- Clarifications about Microsoft Defender for Cloud, Microsoft Sentinel, Microsoft Foundry, or Microsoft Entra behavior you found while studying
- Optional command-line equivalents (Azure CLI, Azure PowerShell, or Bicep) for a portal step, clearly labeled as optional
- Exam-style practice scenarios that you wrote yourself (see the next section)

**Please do not submit:**

- Verbatim or paraphrased questions from any SC-500 exam, live or beta. That violates the [Microsoft certification exam policies](https://learn.microsoft.com/credentials/certifications/certification-exam-policies) and the agreement you accepted when you sat the exam.
- Promotional content for other courses or products
- Azure content that does not map to a skill in the [exam objective map](docs/exam-objectives.md)

## How to submit

1. **Small fixes** (typos, broken links): open an issue with the *Typo or broken link* template, or send a pull request.
2. **Walkthrough fixes or new content**: open an issue with the *Content question or demo issue* template first, so the change is scoped before you spend time on it.
3. **Larger contributions**: mention [@timothywarner](https://github.com/timothywarner) on the issue before you open a pull request.

## Style

- Walkthroughs lead with portal steps. Command-line steps are optional and say so.
- Every name, region, and subscription a learner would change lives in one settings block at the top of the walkthrough or script, never buried in a later step.
- PowerShell uses approved `Verb-Noun` names, `[CmdletBinding()]`, comment-based help, and parameter validation. Bash uses `set -euo pipefail`.
- Every walkthrough and script ends with cleanup, so learners do not pay for leftover resources.
- No secrets, keys, connection strings, or real tenant data in any file.
- Markdown is GitHub-flavored, plain ASCII, with language hints on code fences. Bicep follows the [Azure resource naming guidance](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming).

## Code of conduct

Be kind. Assume good faith. Disagree with ideas, not with people. The [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/) applies.
