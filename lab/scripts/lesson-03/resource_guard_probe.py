"""Exercise Resource Guard using a managed identity independent of the human subscription owner."""
import argparse
import base64
import json
import time
import urllib.error
import urllib.parse
import urllib.request

parser=argparse.ArgumentParser()
parser.add_argument('--client',required=True)
parser.add_argument('--principal',required=True)
parser.add_argument('--vault',required=True)
parser.add_argument('--proxy',required=True)
parser.add_argument('--guard-request',required=True)
parser.add_argument('--phase',choices=['Denied','Allowed'],required=True)
args=parser.parse_args()
if not args.vault.endswith('/Microsoft.RecoveryServices/vaults/rsv-sc500-l03') or not args.proxy.startswith(args.vault+'/backupResourceGuardProxies/'):
    raise RuntimeError('Unexpected recovery vault scope.')
if '/resourcegroups/rg-sc500-l03-policy/providers/microsoft.dataprotection/resourceguards/guard-sc500-l03/' not in args.guard_request.lower():
    raise RuntimeError('Unexpected Resource Guard scope.')
query=urllib.parse.urlencode({'api-version':'2018-02-01','resource':'https://management.core.windows.net/','client_id':args.client})
req=urllib.request.Request('http://169.254.169.254/metadata/identity/oauth2/token?'+query,headers={'Metadata':'true'})
with urllib.request.urlopen(req,timeout=30) as response: token=json.load(response)['access_token']
part=token.split('.')[1]
claims=json.loads(base64.urlsafe_b64decode(part+'='*(-len(part)%4)))
if claims.get('oid') != args.principal: raise RuntimeError('Unexpected managed identity.')

def request(path,method='GET',body=None):
    """Record only service status and error metadata; credentials remain in memory."""
    req=urllib.request.Request('https://management.azure.com'+path,method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=60) as response:
            raw=response.read();return response.status,json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw=error.read();return error.code,json.loads(raw) if raw else {}

read_status,_=request(args.proxy+'?api-version=2026-05-01')
if read_status != 200: raise RuntimeError('Operator cannot read the configured MUA mapping yet.')
body={'resourceGuardOperationRequests':[args.guard_request],'resourceToBeDeleted':args.proxy}
status,reply=request(args.proxy+'/unlockDelete?api-version=2026-05-01','POST',body)
attempts=1
# RBAC propagation is asynchronous. Retry only the known linked-role denial, never unrelated failures.
while args.phase == 'Allowed' and status == 403 and reply.get('error',{}).get('code') == 'LinkedAuthorizationFailed' and attempts < 25:
    time.sleep(20)
    status,reply=request(args.proxy+'/unlockDelete?api-version=2026-05-01','POST',body)
    attempts+=1
record={'operation':'resource-guard-'+args.phase.lower(),'success':True,'principalId':claims['oid'],
        'proxyReadStatus':read_status,'unlockStatus':status,'unlockReply':reply,'protectionRemoved':False,'attempts':attempts}
# An allowed phase finishes the critical operation; the controller must restore MUA in finally.
if args.phase == 'Allowed' and status == 200:
    delete_status,delete_reply=request(args.proxy+'?api-version=2026-05-01','DELETE')
    record.update(deleteStatus=delete_status,deleteReply=delete_reply,protectionRemoved=delete_status in (200,204))
token=None
print('SC500_L03_COMPLETION='+json.dumps(record))
