# Lesson 9 lab guide

**Secure Application Platform Services: Containers, Serverless, App Service, WAF, and API Management**

These are the steps from this lesson's demos, in the order the video runs them. Watch a demo, then do it yourself in your own lab. A step that starts with **Confirm** is a check: find that value on your screen and make sure it matches before you move on, the same way a performance-based exam item grades you.

## Before you start

1. Do the [one-time lab setup](../../lab/README.md) once for the whole course.
2. Deploy this lesson's lab with the **Build** scripts on the [lab files page](demos/README.md).
3. Read this lesson's [Before you start](README.md#before-you-start) list for licenses, costs, and lead times.

> **Your values will differ from the video.** Incident numbers, IDs, times, and generated name endings (shown as `<unique>`) come from the course's lab. Names Azure makes unique across all customers end in your name suffix, and values in angle brackets are yours to fill in.

> **Portals change.** If a menu or label has moved since the course was recorded, the video says so where it matters. If a step no longer matches what you see, open an issue with the *Content question or demo issue* template.

## Portal pages

The steps refer to these pages by number. Open each one in its own browser tab.

| Page | Opens |
| --- | --- |
| 1 | AKS cluster aks-servicehub-prod-eastus2-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-appplatform-prod-eastus2/providers/Microsoft.ContainerService/managedClusters/aks-servicehub-prod-eastus2-001/overview` |
| 2 | Registry `crservicehubprod<your-name-suffix>` access keys: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-appplatform-prod-eastus2/providers/Microsoft.ContainerRegistry/registries/crservicehubprod<your-name-suffix>/accessKey` |
| 3 | Container app ca-status-prod-001 ingress: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-appplatform-prod-eastus2/providers/Microsoft.App/containerApps/ca-status-prod-001/ingress` |
| 4 | Function app `func-partsapi-prod-<your-name-suffix>` authentication: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-appplatform-prod-eastus2/providers/Microsoft.Web/sites/func-partsapi-prod-<your-name-suffix>/eauth` |
| 5 | Logic app logic-intake-prod-eastus2-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-appplatform-prod-eastus2/providers/Microsoft.Logic/workflows/logic-intake-prod-eastus2-001/overview` |
| 6 | Web app `app-servicehub-prod-<your-name-suffix>` networking: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-appplatform-prod-eastus2/providers/Microsoft.Web/sites/app-servicehub-prod-<your-name-suffix>/networkingHub` |
| 7 | WAF policy waf-agw-servicehub-prod-eastus2-001 (Application Gateway): `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-appplatform-prod-eastus2/providers/Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies/waf-agw-servicehub-prod-eastus2-001/overview` |
| 8 | WAF policy wafafdservicehubprod001 (Front Door): `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-appplatform-prod-eastus2/providers/Microsoft.Network/FrontDoorWebApplicationFirewallPolicies/wafafdservicehubprod001/overview` |
| 9 | Log workspace log-appplatform-prod-eastus2-001: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-appplatform-prod-eastus2/providers/Microsoft.OperationalInsights/workspaces/log-appplatform-prod-eastus2-001/logs` |
| 10 | API Management `apim-servicehub-prod-<your-name-suffix>` APIs: `https://portal.azure.com/#@<your-domain>/resource/subscriptions/<your-subscription-id>/resourceGroups/rg-appplatform-prod-eastus2/providers/Microsoft.ApiManagement/service/apim-servicehub-prod-<your-name-suffix>/apim-apis` |

## Demo 1: Sneak a privileged pod past the gate

### 1.1 The cluster's sign-in and network settings

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (AKS cluster aks-servicehub-prod-eastus2-001).

1. Switch to **page 1** (the AKS cluster). On **Overview**, click the **Properties** tab.
2. Under **Security configuration**, confirm **Microsoft Entra ID authentication with Azure RBAC**, then **Local accounts**: **Disabled**.
3. Under **Networking**, confirm **Authorized IP ranges**: **Enabled**, and the one range, your IP.

### 1.2 The registry: no shared password

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 2 (Registry `crservicehubprod<your-name-suffix>` access keys).

1. Switch to **page 2** (the registry's **Access keys**).
2. Confirm **Admin user**: unchecked.

### 1.3 Deploy ServiceHub from the registry

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (AKS cluster aks-servicehub-prod-eastus2-001).

1. Switch to **page 1**. In the left menu, under **Kubernetes resources**, click **Run command**. If a Copilot tip appears, close it.
2. Click **Copy command** below. Click in the command box at the bottom, press **Ctrl+V**, then **Enter**.
3. Confirm **namespace/servicehub created** and the two **deployment.apps** lines.
4. Type `kubectl get pods --namespace servicehub`, then press **Enter**. Confirm both pods **Running** (about 20 seconds).

```powershell
kubectl create namespace servicehub && kubectl create deployment servicehub-status --namespace servicehub --image=crservicehubprod<your-name-suffix>.azurecr.io/servicehub/status:1.0 && kubectl create deployment servicehub-web-legacy --namespace servicehub --image=crservicehubprod<your-name-suffix>.azurecr.io/servicehub/web:legacy
```

### 1.4 Try a privileged pod

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 1 (AKS cluster aks-servicehub-prod-eastus2-001).

1. Click **Copy command** below. Click in the command box at the bottom, press **Ctrl+V**, then **Enter**.
2. Confirm **denied the request**, then **Privileged container is not allowed**.

```powershell
kubectl run servicehub-debug --namespace servicehub --image=crservicehubprod<your-name-suffix>.azurecr.io/servicehub/status:1.0 --overrides='{"spec":{"containers":[{"name":"servicehub-debug","image":"crservicehubprod<your-name-suffix>.azurecr.io/servicehub/status:1.0","securityContext":{"privileged":true}}]}}'
```

### 1.5 Defender reads the images

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal.

1. Top search box: type `Defender for Cloud`. Click **Microsoft Defender for Cloud**, then **Recommendations**.
2. In **Search by title/resource**, type `Update musl`. Confirm the row for the image **web**.
3. Click it, then the **Associated CVEs** tab. Confirm one **CVE** and its **CVSS** score.

### 1.6 The allow list, from both sides

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal in Edge, then PowerShell 7 in Terminal, page 3 (Container app ca-status-prod-001 ingress).

1. Switch to **page 3** (the container app's **Ingress**). Under **IP Restrictions**, confirm **Allow traffic from IPs configured below, deny all other traffic** and **allow-operator**.
2. Switch to **page 1** (Run command). Click the first **Copy command** below.
3. Click in the command box, press **Ctrl+V**, then **Enter**. Confirm **403**.
4. Switch to **Terminal**. Run the second command below. Confirm **200**.

```powershell
curl -sS -o /dev/null -w '%{http_code}\n' https://ca-status-prod-001.whitemoss-e0652baa.eastus2.azurecontainerapps.io/
```

```powershell
curl.exe -sS -o NUL -w "%{http_code}\n" https://ca-status-prod-001.whitemoss-e0652baa.eastus2.azurecontainerapps.io/
```

## Demo 2: Call it without, with, and wrong

### 2.1 Who the function lets in

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal in Edge, then PowerShell 7 in Terminal, page 4 (Function app `func-partsapi-prod-<your-name-suffix>` authentication).

1. Switch to **page 4** (the function app's **Authentication**). Confirm **Require authentication** and **Return HTTP 401 Unauthorized**.
2. In the **Microsoft** provider row, click the pencil icon under **Edit**. Confirm **Allowed token audiences**, then **Allow requests from specific client applications** and its one client ID. Close the pane without saving.
3. Switch to **Terminal**. Run the first command below. Confirm **401**.
4. Run the second command below. Confirm **403**.

```powershell
$func = "https://func-partsapi-prod-<your-name-suffix>.azurewebsites.net/api/parts/PN-1001"; curl.exe -sS -o NUL -w "%{http_code}\n" $func
```

```powershell
$token = az account get-access-token --resource api://<id-from-your-lab> --query accessToken --output tsv; curl.exe -sS -o NUL -w "%{http_code}\n" -H "Authorization: Bearer $token" $func
```

### 2.2 The workflow's own sign-in rule

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal in Edge, then PowerShell 7 in Terminal, page 5 (Logic app logic-intake-prod-eastus2-001).

1. Switch to **page 5** (the logic app). In the left menu, under **Settings**, click **Authorization**.
2. Confirm the policy **servicehub**: **Issuer** `https://sts.windows.net/f74b1450-...`, then **Audience** `api://4a9b667a-...`. Don't click **Save**.
3. Switch to **Terminal**. Run the first command below. Confirm **DirectApiAuthorizationRequired** and **401**.
4. Run the second command below. Confirm **accepted** and **200**.

```powershell
$logic = "https://<your-logic-app-host>/workflows/<your-workflow-id>/triggers/manual/paths/invoke?api-version=2019-05-01"; curl.exe -sS -w " %{http_code}\n" -X POST -H "Content-Type: application/json" -d '{"partId":"PN-1001"}' $logic
```

```powershell
curl.exe -sS -w " %{http_code}\n" -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $token" -d '{"partId":"PN-1001"}' $logic
```

### 2.3 Run history that doesn't leak

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 5 (Logic app logic-intake-prod-eastus2-001).

1. On **page 5**, click **Overview** in the left menu, then the **Run history** tab.
2. Click the top run, then the **manual** trigger.
3. Confirm **Inputs** and **Outputs**: **Content not shown due to security configuration**.

## Demo 3: Every way in

### 3.1 Who the origin admits

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal in Edge, then PowerShell 7 in Terminal, page 6 (Web app `app-servicehub-prod-<your-name-suffix>` networking).

1. Switch to **page 6** (the web app's **Networking**). Click **Enabled with access restrictions**.
2. Confirm **Unmatched rule action**: **Deny**, then **allow-app-gateway**, **20.65.69.39/32**, then **allow-this-front-door**, **AzureFrontDoor.Backend**, with **HTTP headers**: **Configured**.
3. Switch to **Terminal**. Click **Copy command** below.
4. Press **Ctrl+V**, then **Enter**. Confirm **403**.

```powershell
curl.exe -sS -o NUL -w "%{http_code}\n" https://app-servicehub-prod-<your-name-suffix>.azurewebsites.net/
```

### 3.2 The gateway's firewall, then two requests

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal in Edge, then PowerShell 7 in Terminal, page 7 (WAF policy waf-agw-servicehub-prod-eastus2-001 (Application Gateway)).

1. Switch to **page 7** (the WAF policy **waf-agw-servicehub-prod-eastus2-001**). On **Overview**, confirm **Policy mode**: **Prevention**.
2. In the left menu, under **Settings**, click **Managed rules**. Confirm **Microsoft_DefaultRuleSet_2.1**.
3. Switch to **Terminal**. Click **Copy command** below.
4. Press **Ctrl+V**, then **Enter**. Confirm **200**, then **403**.

```powershell
curl.exe -sS -o NUL -w "%{http_code}\n" "http://20.65.69.39/?part=PN-1001"; curl.exe -sS -o NUL -w "%{http_code}\n" "http://20.65.69.39/?part=PN-1001'%20OR%20'1'='1"
```

### 3.3 Front Door's firewall, then two requests

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal in Edge, then PowerShell 7 in Terminal, page 8 (WAF policy wafafdservicehubprod001 (Front Door)).

1. Switch to **page 8** (the WAF policy **wafafdservicehubprod001**). On **Overview**, confirm **Policy mode**: **Prevention**.
2. In the left menu, under **Settings**, click **Custom rules**. Confirm **BlockScannerProbes**, priority **100**.
3. Switch to **Terminal**. Click **Copy command** below.
4. Press **Ctrl+V**, then **Enter**. Confirm **200**, then **403**.

```powershell
curl.exe -sS -o NUL -w "%{http_code}\n" "https://fde-servicehub-prod-001-bwc4dsfgauane5hs.z03.azurefd.net/?part=PN-1001"; curl.exe -sS -o NUL -w "%{http_code}\n" https://fde-servicehub-prod-001-bwc4dsfgauane5hs.z03.azurefd.net/.env
```

### 3.4 Both firewalls, one query

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 9 (Log workspace log-appplatform-prod-eastus2-001).

1. Switch to **page 9** (the workspace's **Logs**). In the top-right dropdown, choose **KQL mode**.
2. Click **Copy command** below. Click in the query editor, press **Ctrl+V**, then click **Run**.
3. Confirm **Application Gateway**, **Blocked**, **949110**, then **Front Door**, **Block**, **BlockScannerProbes**.

```powershell
union
    (AGWFirewallLogs
     | where Action == 'Blocked'
     | project TimeGenerated, Firewall = 'Application Gateway', Action, Rule = RuleId, RequestUri),
    (AzureDiagnostics
     | where Category == 'FrontDoorWebApplicationFirewallLog' and action_s == 'Block'
     | project TimeGenerated, Firewall = 'Front Door', Action = action_s, Rule = ruleName_s, RequestUri = requestUri_s)
| where TimeGenerated > ago(30m)
| order by TimeGenerated desc
```

### 3.5 The whole contract, in one policy

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal, page 10 (API Management `apim-servicehub-prod-<your-name-suffix>` APIs).

1. Switch to **page 10** (API Management **APIs**). Click **ServiceHub parts**, then **All operations**.
2. In **Inbound processing**, click the **</>** icon. If a Copilot tip appears, click **Maybe later**.
3. Confirm **validate-azure-ad-token**, **rate-limit**, **set-header**, then **authentication-managed-identity**. Don't click **Save**.

### 3.6 Two locked doors

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal in Edge, then PowerShell 7 in Terminal, page 10 (API Management `apim-servicehub-prod-<your-name-suffix>` APIs).

1. On **page 10**, in the left menu, under **APIs**, click **Subscriptions**.
2. Confirm **ServiceHub lab caller**: scope **API**, **servicehub-parts**, state **Active**. Don't open its keys.
3. Switch to **Terminal**. Run the first command below. Confirm **missing subscription key** and **401**.
4. Run the second command below. Confirm **A ServiceHub access token is required** and **401**.

```powershell
$api = "https://apim-servicehub-prod-<your-name-suffix>.azure-api.net/servicehub/parts/PN-1001"; curl.exe -sS -w " %{http_code}\n" $api
```

```powershell
$key = az rest --method post --url "/subscriptions/{subscriptionId}/resourceGroups/rg-appplatform-prod-eastus2/providers/Microsoft.ApiManagement/service/apim-servicehub-prod-<your-name-suffix>/subscriptions/servicehub-lab/listSecrets?api-version=2024-05-01" --query primaryKey --output tsv; curl.exe -sS -w " %{http_code}\n" -H "Ocp-Apim-Subscription-Key: $key" $api
```

### 3.7 A key and a token, then a burst

**Sign in as:** ADMIN, your admin account. **Where:** Azure portal in Edge, then PowerShell 7 in Terminal, page 4 (Function app `func-partsapi-prod-<your-name-suffix>` authentication).

1. Switch to **Terminal**. Run the first command below. Confirm **200**, then **calledBy**.
2. Switch to **page 4** (the function's **Authentication**). Open the **Microsoft** provider's **Edit** pane and confirm the allowed client ID: it's the same as **calledBy**. Close the pane without saving.
3. Switch to **Terminal**. Run the second command below. Confirm the first **429**.

```powershell
$token = az account get-access-token --resource api://<id-from-your-lab> --query accessToken --output tsv; curl.exe -sS -w " %{http_code}\n" -H "Ocp-Apim-Subscription-Key: $key" -H "Authorization: Bearer $token" $api
```

```powershell
1..6 | ForEach-Object { curl.exe -sS -o NUL -w "%{http_code}\n" -H "Ocp-Apim-Subscription-Key: $key" -H "Authorization: Bearer $token" $api }
```

### 3.8 Skip the gateway

**Sign in as:** ADMIN, your admin account. **Where:** PowerShell 7 in Terminal, any folder.

1. Click **Copy command** below. In **Terminal**, press **Ctrl+V**, then **Enter**.
2. Confirm **403**.

```powershell
curl.exe -sS -o NUL -w "%{http_code}\n" -H "Authorization: Bearer $token" https://func-partsapi-prod-<your-name-suffix>.azurewebsites.net/api/parts/PN-1001
```

---

[Lesson README](README.md) | [Lab files](demos/README.md) | [Lab setup](../../lab/README.md) | [Course README](../../README.md)
