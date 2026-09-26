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

The workflow is pinned to the instructor's lab. A learner fork requires its own Azure identity, exact repository/environment trust, variables, target, and boundary checks. Forking this repository does not grant access to the instructor's subscription.

## Demonstrate the boundary

1. Inspect the managed identity's federated credential and the job's environment. Compare all three token-matching claims.
2. Dispatch **SC-500 Lesson 02 workload federation** from main.
3. Read the completed job's result: ARM resource-group read **200**, attempted tag write **403 AuthorizationFailed**.
4. Explain the distinction: federation authenticates the caller; the role assignment authorizes its actions. This management-plane result does not establish access to application data.

The deliberate denied write targets one lab marker. If unexpected broad privileges allow it, the workflow attempts to remove only that marker and fails the run. No successful run should leave the marker behind. Tokens stay in memory and are not printed or uploaded. No recurring schedule or retained compute is created.

Sources: [Microsoft Entra federation setup](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust-user-assigned-managed-identity), [GitHub OIDC for Azure](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure), and [Azure Reader role](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general#reader).
