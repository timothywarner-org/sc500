"""Send one authorized Key Vault request through Tor to exercise Microsoft's documented detector."""
import argparse
import base64
import json
import subprocess
import time
import urllib.parse
import urllib.request

parser=argparse.ArgumentParser()
parser.add_argument('--vault', required=True)
parser.add_argument('--principal', required=True)
args=parser.parse_args()
if not args.vault.startswith('kv-sc500-l03-'):
    raise RuntimeError('Only Lesson 3 vaults are in scope.')
# Tor is used only for the documented threat-detection validation, never an inbound listener.
subprocess.run(['apt-get','update','-qq'], check=True, capture_output=True, timeout=180)
subprocess.run(['apt-get','install','-y','-qq','tor','curl'], check=True, capture_output=True, timeout=180)
subprocess.run(['systemctl','start','tor@default'], check=True, capture_output=True)
try:
    query=urllib.parse.urlencode({'api-version':'2018-02-01','resource':'https://vault.azure.net'})
    request=urllib.request.Request('http://169.254.169.254/metadata/identity/oauth2/token?'+query,headers={'Metadata':'true'})
    with urllib.request.urlopen(request, timeout=30) as response:
        token=json.load(response)['access_token']
    part=token.split('.')[1]
    claims=json.loads(base64.urlsafe_b64decode(part+'='*(-len(part)%4)))
    if claims.get('oid') != args.principal:
        raise RuntimeError('Unexpected managed identity.')
    tor_info=None
    for attempt in range(12):
        probe=subprocess.run(['curl','--silent','--show-error','--max-time','20','--socks5-hostname','127.0.0.1:9050','https://check.torproject.org/api/ip'],capture_output=True,text=True)
        if probe.returncode == 0:
            tor_info=json.loads(probe.stdout)
            if tor_info.get('IsTor'): break
        time.sleep(10)
    if not tor_info or not tor_info.get('IsTor'):
        raise RuntimeError('Tor route was not established; no validation request was sent.')
    # Bearer material travels over TLS to Azure and enters curl via stdin, never process arguments or logs.
    config='header = "Authorization: Bearer '+token+'"\n'
    sent_at=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
    call=subprocess.run(['curl','--silent','--show-error','--max-time','45','--socks5-hostname','127.0.0.1:9050','--config','-',
                         '--write-out','\n%{http_code}','https://'+args.vault+'.vault.azure.net/secrets/servicehub-maintenance-demo?api-version=7.4'],
                        input=config,capture_output=True,text=True)
    token=None;config=None
    if call.returncode: raise RuntimeError('Vault validation transport failed.')
    body,status=call.stdout.rsplit('\n',1)
    reply=json.loads(body)
    error=reply.get('error',{})
    print('SC500_L03_COMPLETION='+json.dumps({'operation':'vault-detection-trigger','success':True,'sentAt':sent_at,
        'vault':args.vault,'principalId':claims['oid'],'torExitIp':tor_info['IP'],'httpStatus':int(status),
        'errorCode':error.get('code'),'innerCode':error.get('innererror',{}).get('code'),
        'alertObserved':False,'vaultNetworkControlsUnchanged':True}))
finally:
    subprocess.run(['systemctl','stop','tor@default'],check=False,capture_output=True)
