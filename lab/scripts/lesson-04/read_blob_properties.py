"""Return the Blob service's actual HTTP status, error code and request ID for one HEAD."""
import json
import sys
from azure.core.credentials import AccessToken
from azure.core.exceptions import HttpResponseError
from azure.storage.blob import BlobClient


class OneRequestCredential:
    """Supply the short-lived Entra token received privately on stdin."""
    def __init__(self, value):
        self.value = value

    def get_token(self, *scopes, **kwargs):
        return AccessToken(self.value["accessToken"], int(self.value["expires_on"]))


def main():
    """Keep credentials off command-line arguments and report no blob content."""
    request = json.load(sys.stdin)
    credential = OneRequestCredential(request["credential"]) if request["auth"] == "login" else request["credential"]
    observed = {}
    def capture(response):
        # Capture service headers before the SDK/CLI turns failures into friendly advice.
        wire = response.http_response
        observed.update(status=wire.status_code, code=wire.headers.get("x-ms-error-code"),
                        requestId=wire.headers.get("x-ms-request-id"))
    try:
        with BlobClient(request["accountUrl"], request["container"], request["blob"],
                        credential=credential, retry_total=0) as blob:
            blob.get_blob_properties(raw_response_hook=capture)
    except HttpResponseError:
        if not observed.get("requestId"):
            raise RuntimeError("No Blob service request ID was returned.") from None
    if not observed:
        raise RuntimeError("No service response captured.")
    print(json.dumps(observed))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Client failure: {type(exc).__name__}; no service denial asserted.", file=sys.stderr)
        sys.exit(1)
