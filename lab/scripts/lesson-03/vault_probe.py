"""Exercise only synthetic L3 Key Vault objects over the private endpoint.

Tokens and synthetic secret values stay in memory. Output contains metadata and
operation status only, because this output will be used in a recorded lesson.
"""
import argparse,base64,ipaddress,json,secrets,socket,time,urllib.error,urllib.parse,urllib.request

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--vault',required=True)
parser.add_argument('--mode',choices=['Objects','ReadBoundary'],required=True)
parser.add_argument('--bootstrap-client-id')
args=parser.parse_args()
if not args.vault.startswith('kv-sc500-l03-') or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in args.vault):
    raise SystemExit('Unexpected vault name')
host=args.vault+'.vault.azure.net'
ips=sorted({r[4][0] for r in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)})
if not ips or not all(ipaddress.ip_address(x).is_private for x in ips):raise SystemExit('Vault DNS did not resolve exclusively to private addresses')
query={'api-version':'2018-02-01','resource':'https://vault.azure.net'}
if args.mode=='Objects':
    if not args.bootstrap_client_id:raise SystemExit('Object operations require the separate bootstrap identity')
    query['client_id']=args.bootstrap_client_id
imds='http://169.254.169.254/metadata/identity/oauth2/token?'+urllib.parse.urlencode(query)
# IMDS is link-local. Proxy bypass prevents forwarding a token request to an outbound proxy.
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
with opener.open(urllib.request.Request(imds,headers={'Metadata':'true'}),timeout=20) as r:token=json.load(r)['access_token']
payload=token.split('.')[1]
claims=json.loads(base64.urlsafe_b64decode(payload+'='*(-len(payload)%4)))
events=[]
def request(method,path,body=None):
    """Return bounded service metadata; never echo the token or raw response on failure."""
    url='https://'+host+'/'+path.lstrip('/')+('?api-version=7.4' if '?' not in path else '')
    req=urllib.request.Request(url,data=None if body is None else json.dumps(body).encode(),method=method,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
    try:
        with opener.open(req,timeout=30) as r:
            raw=r.read();return r.status,json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw=e.read()
        try:data=json.loads(raw)
        except ValueError:data={}
        return e.code,data

def operation(label,method,path,body=None,expected=(200,),retry=False,ready=None):
    # RBAC and recovery are eventually consistent. Bound retries and retain the final service outcome.
    for attempt in range(25 if retry else 1):
        code,data=request(method,path,body)
        complete=code in expected and (ready is None or ready(data))
        if complete:break
        if data.get('status','').lower() in ('failed','canceled'):break
        if not retry or (code not in expected and code not in (403,404,409,429,500,503)):break
        time.sleep(5)
    error=data.get('error',{}).get('innererror',{}).get('code') or data.get('error',{}).get('code')
    event={'operation':label,'http':code,'error':error}
    if ready is not None:event['ready']=bool(complete)
    if 'id' in data:event['objectId']=data['id']
    if 'kid' in data.get('key',{}):event['objectId']=data['key']['kid']
    events.append(event)
    if not complete:raise RuntimeError(f'{label}: HTTP {code}, {error or "expected object state not ready"}')
    return data

tags={'course':'SC500','lesson':'03','purpose':'synthetic-training-only'}
result={'mode':args.mode,'vault':args.vault,'privateAddresses':ips,'principalId':claims.get('oid'),'events':events,'success':False}
try:
    if args.mode=='Objects':
        operation('check-bootstrap-data-access','GET','secrets',retry=True)
        # Resume a run interrupted between delete and recover instead of colliding with a soft-deleted name.
        # Listing active secrets can succeed before the separate deleted-object permission propagates.
        prior=operation('inspect-deleted-fixture','GET','deletedsecrets/servicehub-maintenance-demo',expected=(200,404),retry=True)
        if not prior.get('error'):
            if prior.get('tags',{}).get('purpose')!='synthetic-training-only':
                raise RuntimeError('The deleted object is not the expected training fixture')
            operation('recover-interrupted-take','POST','deletedsecrets/servicehub-maintenance-demo/recover',{},retry=True)
        # These values grant no access to another service; they are disposable teaching data.
        for version in (1,2):
            operation('create-secret-version-'+str(version),'PUT','secrets/servicehub-maintenance-demo',{'value':secrets.token_urlsafe(32),'tags':tags,'attributes':{'enabled':True,'exp':int(time.time())+30*86400}},retry=True)
        versions=operation('list-secret-versions','GET','secrets/servicehub-maintenance-demo/versions')
        result['secretVersionCount']=len(versions.get('value',[]))
        operation('delete-recoverable-demo-secret','DELETE','secrets/servicehub-maintenance-demo')
        operation('recover-demo-secret','POST','deletedsecrets/servicehub-maintenance-demo/recover',{},retry=True)
        operation('read-recovered-secret','GET','secrets/servicehub-maintenance-demo',retry=True)
        operation('create-software-key','POST','keys/servicehub-signing-demo/create',{'kty':'RSA','key_size':2048,'key_ops':['sign','verify'],'tags':tags})
        operation('set-key-rotation-policy','PUT','keys/servicehub-signing-demo/rotationpolicy',{'attributes':{'expiryTime':'P90D'},'lifetimeActions':[{'trigger':{'timeAfterCreate':'P60D'},'action':{'type':'Rotate'}}]})
        operation('rotate-key-now','POST','keys/servicehub-signing-demo/rotate',{})
        cert=operation('request-self-signed-lab-certificate','POST','certificates/servicehub-tls-demo/create',{'policy':{'issuer':{'name':'Self'},'key_props':{'exportable':False,'kty':'RSA','key_size':2048,'reuse_key':False},'secret_props':{'contentType':'application/x-pkcs12'},'x509_props':{'subject':'CN=servicehub.contoso.com','validity_months':1}},'tags':tags},expected=(200,202),retry=True)
        # HTTP 200 can describe an incomplete certificate. Wait for issuance and the related object links.
        operation('wait-for-certificate-issuance','GET','certificates/servicehub-tls-demo/pending',retry=True,ready=lambda d:d.get('status','').lower()=='completed')
        cert=operation('read-issued-lab-certificate','GET','certificates/servicehub-tls-demo/',retry=True,ready=lambda d:all(d.get(k) for k in ['id','kid','sid','cer']))
        result['certificateObjects']={k:cert.get(k) for k in ['id','kid','sid']}
    else:
        doc=operation('read-secret-as-workload','GET','secrets/servicehub-maintenance-demo',retry=True)
        result['valuePresent']=bool(doc.get('value'))
        # A separate harmless object keeps the denial probe from changing the application's current value.
        operation('write-secret-as-workload','PUT','secrets/servicehub-write-denied',{'value':secrets.token_urlsafe(32),'tags':tags},expected=(403,))
        if events[-1]['error']!='ForbiddenByRbac':
            raise RuntimeError('The write failed, but the response did not establish an RBAC denial')
    result['success']=True
except Exception as exc:
    result['failure']=str(exc)
finally:
    token=None
    print('SC500_L03_RESULT='+json.dumps(result,separators=(',',':')))
raise SystemExit(0 if result['success'] else 1)
