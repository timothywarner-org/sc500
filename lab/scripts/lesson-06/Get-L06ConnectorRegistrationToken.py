"""Acquire the documented connector registration scope with a human device sign-in.

Called only by a parent process that captures stdout privately. The short-lived token
is returned to that process for DPAPI protection, never to a terminal or source file.
Reference: Microsoft Learn, how-to-register-connector-powershell.
"""
import json
import sys
import msal

def main():
    """Send only the human sign-in challenge to stderr; keep credentials on the private pipe."""
    app=msal.PublicClientApplication('55747057-9b5d-4bd4-b387-abf52a8bd489',authority='https://login.microsoftonline.com/<your-tenant-id>')
    flow=app.initiate_device_flow(scopes=['https://proxy.cloudwebappproxy.net/registerapp/user_impersonation'])
    if 'user_code' not in flow:raise RuntimeError(flow.get('error_description','No device code returned'))
    print(flow['message'],file=sys.stderr,flush=True)
    result=app.acquire_token_by_device_flow(flow)
    if 'access_token' not in result:raise RuntimeError(result.get('error_description','Registration sign-in failed'))
    print(json.dumps({'access_token':result['access_token'],'expires_in':result['expires_in']}),flush=True)

if __name__=='__main__':main()
