"""Stream the official harmless EICAR fixture to the pinned SC-500 intake, without a local copy."""
import hashlib
import json
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from azure.core.credentials import AccessToken
from azure.storage.blob import BlobClient

LAB = Path(__file__).resolve().parents[2]
CONFIG = json.loads((LAB / "infra/lesson-04/config.json").read_text(encoding="utf-8-sig"))


def az(*args):
    """Capture CLI output privately so credentials never enter the terminal or evidence."""
    result = subprocess.run([sys.executable, "-Im", "azure.cli", *args,
                             "--subscription", CONFIG["subscriptionId"], "--only-show-errors", "-o", "json"],
                            capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise RuntimeError("Azure CLI request failed; check the current course sign-in.")
    return json.loads(result.stdout)


class CourseCredential:
    """Use only the existing token for the pinned course subscription and tenant."""
    def get_token(self, *scopes, **kwargs):
        token = az("account", "get-access-token", "--resource", "https://storage.azure.com/")
        return AccessToken(token["accessToken"], int(token["expires_on"]))


def main():
    """Require the known lab destination, upload 68 test bytes, and save only the receipt."""
    context = az("account", "show")
    if context["tenantId"] != CONFIG["tenantId"] or context["id"] != CONFIG["subscriptionId"]:
        raise RuntimeError("Wrong Azure context.")
    deployment = az("deployment", "sub", "show", "--name", CONFIG["deploymentName"])
    state = deployment["properties"]
    output = state["outputs"]["lab"]["value"]
    if state["provisioningState"] != "Succeeded" or output["resourceGroup"] != CONFIG["resourceGroup"]:
        raise RuntimeError("Lesson deployment identity or state mismatch.")
    # The fixed official URL supplies a standardized, non-executable antivirus test fixture.
    source = "https://secure.eicar.org/eicar.com.txt"
    with urllib.request.urlopen(source, timeout=30) as response:
        payload = response.read(1024)
    if len(payload) != 68 or hashlib.md5(payload, usedforsecurity=False).hexdigest() != "44d88612fea8a8f36de82e1278abb02f":
        raise RuntimeError("Official EICAR fixture differs from its published 68-byte test value.")
    name = "CTSO-UPLOAD-7732-eicar-test.txt"
    with BlobClient(f"https://{output['intakeAccount']}.blob.core.windows.net",
                    CONFIG["intakeContainer"], name, credential=CourseCredential(), retry_total=0) as blob:
        uploaded = blob.upload_blob(payload, overwrite=True, metadata={"purpose": "sc500-l04-harmless-antivirus-test"})
    now = datetime.now(timezone.utc)
    receipt = dict(timeUtc=now.isoformat(), source=source, account=output["intakeAccount"],
                   container=CONFIG["intakeContainer"], blob=name, bytes=len(payload),
                   sha256=hashlib.sha256(payload).hexdigest(), etag=uploaded["etag"],
                   fixture="harmless EICAR antivirus test", localFileCreated=False)
    evidence = LAB / ".azure/lesson-04/evidence" / f"{now:%Y%m%dT%H%M%SZ}-eicar-upload.json"
    evidence.write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(f"UPLOADED: {name}, {len(payload)} bytes. Read ScanResults for detection evidence.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        # SDK tracebacks can include request details. Return a bounded error without tokens.
        print(f"FAILED: {type(exc).__name__}; no successful upload claimed.", file=sys.stderr)
        sys.exit(1)
