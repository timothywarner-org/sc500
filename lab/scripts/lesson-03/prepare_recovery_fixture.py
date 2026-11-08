"""Create fictional ServiceHub data whose hash can prove a usable Azure Backup restore."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

directory = Path('/opt/contoso/servicehub')
directory.mkdir(parents=True, exist_ok=True)
record = directory / 'maintenance-record.json'
payload = {'company':'Contoso, Ltd.', 'application':'ServiceHub', 'recordId':'CT-500-003',
           'asset':'Cooling system 03', 'status':'Maintenance complete', 'engineer':'Debra Garcia',
           'fictionalTrainingData':True}
encoded = (json.dumps(payload, sort_keys=True, indent=2)+'\n').encode()
# Refuse to overwrite unexpected data; the fixture must remain independently resettable.
if record.exists() and record.read_bytes() != encoded:
    raise RuntimeError('Existing maintenance record differs from the expected fixture.')
record.write_bytes(encoded)
os.chmod(record, 0o644)
key = directory / 'legacy-ssh.pem'
if not key.exists():
    # This generated canary is never authorized on any host. Only the scanner sees its plaintext form.
    subprocess.run(['ssh-keygen','-q','-t','rsa','-b','2048','-m','PEM','-N','','-f',str(key)],check=True)
    os.chmod(key,0o600)
os.sync()
print('SC500_L03_COMPLETION='+json.dumps({'operation':'prepare-recovery-fixture','success':True,
    'recordPath':str(record),'sha256':hashlib.sha256(encoded).hexdigest(),'bytes':len(encoded),
    'canaryPath':str(key),'canaryAuthorizedOnAnyHost':False}))
