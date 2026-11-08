# Lab files

This folder holds every script and Bicep template from the demos in Lessons 1 through 13. These are the same files the course runs on screen, with the instructor's tenant values swapped for placeholders you fill in once. Lessons 14 and 15 land here after they publish.

- [`scripts/`](scripts/): PowerShell and Python, one folder per lesson. Lesson 1 sits in the `scripts` root.
- [`infra/`](infra/): Bicep templates and one `config.json` per lesson. Every resource name comes from that lesson's `config.json`, so a rename is one edit in one file.
- [`Set-LabConfig.ps1`](Set-LabConfig.ps1): writes your tenant, subscription, domain, and account into every lab file.

Each lesson folder under [`lessons/`](../lessons/) has a `demos/README.md` that lists that lesson's scripts in run order.

> **Cost warning:** these scripts create real Azure resources, and some of them bill by the hour (Azure Firewall, VPN gateways, Virtual WAN hubs, API Management, Defender plans). Use a dedicated sandbox subscription with a budget alert, and run the lesson's `Remove-` script when you finish.

## One-time setup

1. **Use Windows 11.** The scripts protect generated lab passwords with Windows DPAPI, and they call the Windows build of Azure CLI directly.

2. **Install the tools.** Run these in an elevated PowerShell 7 window:

   ```powershell
   winget install --id Microsoft.PowerShell --exact
   winget install --id Microsoft.AzureCLI --exact
   winget install --id GitHub.cli --exact
   az bicep install
   az aks install-cli
   Install-Module Microsoft.Graph.Authentication -MinimumVersion 2.36.1 -Scope CurrentUser
   python -m pip install msal azure-storage-blob
   ```

   You need Python 3.11 or later for the `pip` line. GitHub CLI is only for Lesson 2, and `kubectl` (from `az aks install-cli`) is only for Lesson 9.

3. **Clone the repository to `C:\github\sc500`.** Every command in the lesson pages uses full paths that start there.

   ```powershell
   git clone https://github.com/timothywarner-org/sc500.git C:\github\sc500
   ```

4. **Sign in to Azure CLI** with the account you run the labs as.

   ```powershell
   az login --tenant <your-tenant-id>
   ```

5. **Preview your values, then write them.** The first command changes nothing and lists every file it would change. The second one writes.

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\Set-LabConfig.ps1 -SubscriptionId <your-subscription-id> -TenantId <your-tenant-id> -Domain <your-domain> -AdminUpn <your-admin-upn> -GitHubOwner <your-github-owner> -WhatIf
   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\Set-LabConfig.ps1 -SubscriptionId <your-subscription-id> -TenantId <your-tenant-id> -Domain <your-domain> -AdminUpn <your-admin-upn> -GitHubOwner <your-github-owner>
   ```

   To change your values later, restore the originals with `git -C C:\github\sc500 checkout -- lab` and run it again.

## Placeholders

| Placeholder | Your value | Filled by |
| --- | --- | --- |
| `<your-subscription-id>` | The sandbox subscription for the labs | `Set-LabConfig.ps1` |
| `<your-tenant-id>` | The Microsoft Entra tenant that owns it | `Set-LabConfig.ps1` |
| `<your-domain>` | A verified domain in that tenant. Lab users become `sc500.<name>@<your-domain>`, and Lesson 12 uses it as the Defender EASM discovery seed, so only use a domain you own. | `Set-LabConfig.ps1` |
| `<your-admin-upn>` | The account you run the labs as | `Set-LabConfig.ps1` |
| `<your-github-owner>` | Your GitHub user or organization (Lesson 2 federation subject) | `Set-LabConfig.ps1` |
| `<your-access-review-id>` | The ID of the Lesson 1 access review, after you create it | You, by hand |
| `<your-lab-user-object-id>` | The object ID of the Lesson 1 lab user that the access review fixture targets | You, by hand |

## How the scripts behave

- **They check before they change.** Each lesson's common file pins the subscription and tenant from `config.json` and refuses to run against anything else.
- **Read the help first.** Every script starts with comment-based help that says what it reads and what it changes. Run `Get-Help C:\github\sc500\lab\scripts\lesson-05\Deploy-L05Lab.ps1 -Full` for any of them.
- **Local state stays local.** Evidence files and deployment outputs land in `lab\.azure\`, which Git ignores. Generated passwords go to `%LOCALAPPDATA%`, protected with DPAPI, and are never printed.
- **Data is fictional.** Contoso, Fabrikam, and the ServiceHub app are made up. See [NOTICE.md](../NOTICE.md).

Found a script that no longer matches the portal or the API? Open an issue with the *Content question or demo issue* template.
