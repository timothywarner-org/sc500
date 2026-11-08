# Lesson 2: prove workload identity federation

This instructor demonstration follows Contoso ServiceHub's deployment identity from a GitHub Actions job to Azure Resource Manager. An exact federated credential permits the token exchange. A separate **Reader** assignment determines the Azure operations the identity can perform.

The [workflow](../.github/workflows/sc500-lesson02-oidc.yml) is manually dispatched, restricted to this repository's main branch, and bounded to five minutes. It uses no client secret and deploys no resources.

## Trust and access

| Boundary | Required configuration |
| --- | --- |
| Issuer | `https://token.actions.githubusercontent.com` |
| Subject | `repo:timothywarner-org/sc500:environment:sc500-lesson02` |
| Audience | `api://AzureADTokenExchange` |
| GitHub environment | `sc500-lesson02`, main branch only |
| Environment variables | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`; nonsecret identifiers |
| Azure role | Reader on the instructor's dedicated `rg-sc500-l02-target` resource group |

The workflow is pinned to the instructor's lab. Forking this repository does not grant access to the instructor's subscription. To run the same proof against your own subscription, follow [Run it in your own fork](#run-it-in-your-own-fork).

## Demonstrate the boundary

1. Inspect the managed identity's federated credential and the job's environment. Compare all three token-matching claims.
2. Dispatch **SC-500 Lesson 02 workload federation** from main.
3. Read the completed job's result: ARM resource-group read **200**, attempted tag write **403 AuthorizationFailed**.
4. Explain the distinction: federation authenticates the caller; the role assignment authorizes its actions. This management-plane result does not establish access to application data.

The deliberate denied write targets one lab marker. If unexpected broad privileges allow it, the workflow attempts to remove only that marker and fails the run. No successful run should leave the marker behind. Tokens stay in memory and are not printed or uploaded. No recurring schedule or retained compute is created.

## Run it in your own fork

Your Lesson 2 lab already trusts `repo:<your-github-owner>/sc500:environment:sc500-lesson02`, because `Set-LabConfig.ps1 -GitHubOwner` wrote your owner into `lab/infra/lesson-02/workload.bicep`. What's left is a fork for that subject to match, the environment, and two guard lines in the workflow.

1. Fork `timothywarner-org/sc500` to your GitHub account, then point your clone at the fork:

   ```powershell
   git -C C:\github\sc500 remote set-url origin https://github.com/<your-github-owner>/sc500.git
   ```

2. Deploy the lab with the federated credential, then create the `sc500-lesson02` environment and its three variables in your fork. Both scripts preview by default; read the preview, then apply.

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Deploy-L02Workload.ps1 -Mode Apply -IncludeFederation
   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Set-L02FederationEnvironment.ps1
   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\github\sc500\lab\scripts\lesson-02\Set-L02FederationEnvironment.ps1 -Apply
   ```

3. In your fork's `.github/workflows/sc500-lesson02-oidc.yml`, change the two guards that pin the instructor's lab:
   - `if: github.repository == 'timothywarner-org/sc500' ...` becomes `if: github.repository == '<your-github-owner>/sc500' ...`
   - In the boundary check, the subscription ID and tenant ID become yours.
4. Commit and push to `main` in your fork. On the fork's **Actions** tab, enable workflows (forks start with them off), then run **SC-500 Lesson 02 workload federation**.
5. Read the result the same way as above: ARM read **200**, tag write **403 AuthorizationFailed**.

Sources: [Microsoft Entra federation setup](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust-user-assigned-managed-identity), [GitHub OIDC for Azure](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure), and [Azure Reader role](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general#reader).
