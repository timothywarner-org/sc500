"""Request only ServiceHub Maintenance.Read and retain nonsecret correlation evidence."""
import datetime
import json
import sys
from pathlib import Path
import msal

def main():
    """The human completes all credential entry in Microsoft's system-browser flow."""
    state_path=Path(sys.argv[1])
    state=json.loads(state_path.read_text(encoding='utf-8-sig'))
    app=msal.PublicClientApplication(state['clientId'],authority='https://login.microsoftonline.com/'+state['tenantId'])
    result=app.acquire_token_interactive(scopes=[f"api://{state['apiClientId']}/Maintenance.Read"],login_hint=state['userPrincipalName'],prompt='select_account',timeout=600)
    if 'access_token' not in result:
        print(json.dumps({k:result.get(k) for k in ['error','error_description','correlation_id']}))
        return 1
    # MSAL validates the authentication response. Read only identity claims from its validated ID token.
    claims=result.get('id_token_claims',{})
    if claims.get('oid')!=state['userId'] or claims.get('tid')!=state['tenantId']:
        raise RuntimeError('The returned account is not Garth in the course tenant.')
    # An access token is for the resource to validate. Do not decode it as an authorization decision.
    record={'checkedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'userId':claims['oid'],'tenantId':claims['tid'],'requestedResource':state['apiClientId'],'requestedScope':'Maintenance.Read','returnedScope':result.get('scope'),'correlationId':result.get('correlation_id'),'tokenIssued':True,'backendCalled':False,'enforcementProven':False}
    folder=state_path.parent/'evidence'
    folder.mkdir(exist_ok=True)
    path=folder/(datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S')+'-garth-signin.json')
    path.write_text(json.dumps(record,indent=2),encoding='utf-8')
    print(json.dumps(record,indent=2))
    print('Read the matching Garth / ServiceHub sign-in in Entra logs. Report-only is not enforcement.')
    return 0

if __name__=='__main__':sys.exit(main())
