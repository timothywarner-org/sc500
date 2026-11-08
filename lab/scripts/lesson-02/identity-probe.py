"""Prove each Contoso workload identity can read its target but cannot change tags.

The Azure token stays in this process. Logs contain only principal IDs and status
codes so the same evidence can safely support a recorded demonstration.
"""

import base64
import ctypes
import json
import os
import random
import time
import urllib.error
import urllib.parse
import urllib.request


def secure_process():
    """Drop the base image's root identity before acquiring tokens or making requests."""
    # Standard ACI currently accepts only securityContext.privileged. Fail closed
    # unless the Linux process can shed root, capabilities and future elevation.
    if os.getuid() == 0:
        os.setgroups([])
        os.setgid(10001)
        os.setuid(10001)
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(38, 1, 0, 0, 0) != 0:  # PR_SET_NO_NEW_PRIVS prevents setuid/file-capability elevation.
        raise RuntimeError("Linux no-new-privileges could not be set.")
    with open("/proc/self/status", encoding="utf-8") as status_file:
        status = dict(line.split(":", 1) for line in status_file if ":" in line)
    facts = {"uid": os.getuid(), "gid": os.getgid(), "effectiveCapabilities": status["CapEff"].strip(), "noNewPrivileges": status["NoNewPrivs"].strip()}
    if facts["uid"] != 10001 or facts["gid"] != 10001 or int(facts["effectiveCapabilities"], 16) != 0 or facts["noNewPrivileges"] != "1":
        raise RuntimeError("The probe did not reach the required nonroot security state.")
    print("SC500_L02_SECURITY " + json.dumps(facts), flush=True)


def request_json(url, *, headers=None, method="GET", body=None):
    """Return HTTP status and JSON without ever logging request authorization."""
    payload = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(url, data=payload, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            status, raw = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, raw = error.code, error.read()
    except urllib.error.URLError:
        # A token endpoint can be temporarily unavailable during identity provisioning.
        return 503, {"error": {"code": "TransportUnavailable"}}
    try:
        return status, json.loads(raw or b"{}")
    except json.JSONDecodeError:
        # Never print an unparsed response body because this same helper handles tokens.
        if raw.decode(errors="replace").strip() == "Received invalid token. Please try again.":
            return status, {"error": {"code": "IdentityEndpointInvalidToken"}}
        return status, {"error": {"code": "NonJsonResponse"}, "responseBytes": len(raw)}


def run_probe(identity_kind, client_id=None):
    """Wait only for initial Reader propagation, then perform one denial probe."""
    target = os.environ["TARGET_GROUP_ID"]
    if not target.endswith("/resourceGroups/rg-sc500-l02-target"):
        raise RuntimeError("Probe target must be the dedicated Lesson 2 target group.")
    # Use Azure CLI's ARM token audience consistently for local and federated probes.
    # The REST host remains management.azure.com; token audience and request host are distinct.
    query = {"api-version": "2018-02-01", "resource": "https://management.core.windows.net/"}
    if client_id:
        query["client_id"] = client_id
    token_url = "http://169.254.169.254/metadata/identity/oauth2/token?" + urllib.parse.urlencode(query)
    read_url = "https://management.azure.com" + target + "?api-version=2021-04-01"
    deadline = time.monotonic() + 480
    token_deadline = time.monotonic() + 120
    delay = 2
    while True:
        token_status, token_reply = request_json(token_url, headers={"Metadata": "true"})
        if token_status != 200 or "access_token" not in token_reply:
            if time.monotonic() >= token_deadline:
                raise RuntimeError(f"{identity_kind} token request failed: HTTP {token_status}, {token_reply.get('error', {}).get('code', 'TokenMissing')}.")
            time.sleep(min(delay, 15) + random.random())
            delay *= 2
            continue
        token = token_reply["access_token"]
        # ARM validates the token. Decoding here only identifies the principal in the evidence.
        claims_part = token.split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(claims_part + "=" * (-len(claims_part) % 4)))
        if claims.get("tid") != os.environ["EXPECTED_TENANT_ID"]:
            raise RuntimeError("Managed identity token belongs to an unexpected tenant.")
        auth = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
        read_status, group = request_json(read_url, headers=auth)
        if read_status == 200:
            break
        if read_status not in (401, 403, 429, 500, 502, 503, 504) or time.monotonic() >= deadline:
            raise RuntimeError(f"{identity_kind} target read returned HTTP {read_status}.")
        # New RBAC grants can lag deployment. This bounded setup retry never hides write success.
        time.sleep(min(delay, 15) + random.random())
        delay *= 2

    probe_tag = "sc500-l02-authorization-probe"
    if probe_tag in group.get("tags", {}):
        raise RuntimeError("Probe tag already exists; inspect the previous failed test first.")
    tags_url = "https://management.azure.com" + target + "/providers/Microsoft.Resources/tags/default?api-version=2021-04-01"
    write_status, write_reply = request_json(tags_url, headers=auth, method="PATCH", body={
        "operation": "Merge", "properties": {"tags": {probe_tag: "denied-expected"}}
    })
    result = {
        "identity": identity_kind,
        "principalId": claims.get("oid"),
        "tokenAudience": claims.get("aud"),
        "readStatus": read_status,
        "writeStatus": write_status,
        "writeErrorCode": write_reply.get("error", {}).get("code"),
        "passed": read_status == 200 and write_status == 403 and write_reply.get("error", {}).get("code") == "AuthorizationFailed",
    }
    if 200 <= write_status < 300:
        # Remove only this test's marker if unexpected broad privileges allowed the write.
        cleanup_status, _ = request_json(tags_url, headers=auth, method="PATCH", body={
            "operation": "Delete", "properties": {"tags": {probe_tag: "denied-expected"}}
        })
        result["unexpectedWriteCleanupStatus"] = cleanup_status
    print("SC500_L02_RESULT " + json.dumps(result), flush=True)
    if not result["passed"]:
        raise RuntimeError("The expected Reader boundary was not demonstrated.")


def main():
    """Keep import free of Azure operations so boundary-failure handling can be tested offline."""
    try:
        secure_process()
        mode = os.environ.get("PROBE_IDENTITY", "Both")
        if mode not in ("Both", "UserAssigned", "SystemAssigned"):
            raise RuntimeError("Unsupported identity probe mode.")
        # Testing one attachment at a time isolates ACI token issuance from ARM authorization.
        if mode in ("Both", "UserAssigned"):
            run_probe("user-assigned", os.environ["USER_IDENTITY_CLIENT_ID"])
        if mode in ("Both", "SystemAssigned"):
            run_probe("system-assigned")
        print("SC500_L02_COMPLETE", flush=True)
        # A short bounded hold gives the controller time to collect logs and explicitly stop billing.
        time.sleep(600)
    except Exception as error:
        print("SC500_L02_FAILED " + type(error).__name__ + ": " + str(error), flush=True)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
