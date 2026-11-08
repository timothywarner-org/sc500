"""Read the recovered Contoso record from the explicitly attached recovery disk, without writes."""
import hashlib
import json
from pathlib import Path
import subprocess

device=Path('/dev/disk/azure/scsi1/lun10')
mount=Path('/mnt/sc500-l03-recovery')
if not device.exists():
    raise RuntimeError('The dedicated restore disk is not present at LUN 10.')
# Device paths, not filesystem UUIDs, distinguish the restored copy from the running OS disk.
# Request the hierarchy explicitly; PATH without NAME otherwise yields a flat JSON list on this image.
listing=json.loads(subprocess.check_output(['lsblk','--json','--tree','--paths','-o','PATH,TYPE,FSTYPE,MOUNTPOINTS',str(device)],text=True))
disk=listing['blockdevices'][0]
parts=[p for p in disk.get('children',[]) if p.get('fstype')=='ext4']
if not parts or any(any(p.get('mountpoints') or []) for p in parts):
    raise RuntimeError('Expected unmounted ext4 partitions on the recovery disk.')
mount.mkdir(parents=True,exist_ok=True)
if subprocess.run(['mountpoint','-q',str(mount)]).returncode==0:
    raise RuntimeError('Recovery mount path is already in use.')
subprocess.run(['blockdev','--setro',disk['path']],check=True)
mounted=False
try:
    # noload prevents ext4 journal replay from changing the evidence copy.
    # Ubuntu images can have a separate ext4 boot partition. Inspect each read-only, never assume numbering.
    recovered=[]
    for partition in parts:
        subprocess.run(['mount','-o','ro,noload',partition['path'],str(mount)],check=True)
        mounted=True
        target=mount/'opt/contoso/servicehub/maintenance-record.json'
        if target.exists():recovered.append(target.read_bytes())
        subprocess.run(['umount',str(mount)],check=True)
        mounted=False
    if len(recovered)!=1:raise RuntimeError('Expected exactly one restored maintenance record.')
    content=recovered[0]
    record=json.loads(content)
    digest=hashlib.sha256(content).hexdigest()
    expected='8fc264a553402cc4daa5885c2ba0516a62b22b14d76cd86708bdd349bbd18897'
    passed=digest==expected and record.get('recordId')=='CT-500-003' and record.get('fictionalTrainingData') is True
    result={'operation':'restored-record','success':passed,'source':'restored-disk-lun10','mountedReadOnly':True,
            'bytes':len(content),'sha256':digest,'expectedSha256':expected,'record':record,
            'scope':'Recovered file content and schema; no full application or dependency recovery claim.'}
finally:
    if mounted:subprocess.run(['umount',str(mount)],check=True)
    subprocess.run(['blockdev','--setrw',disk['path']],check=True)
print('SC500_L03_COMPLETION='+json.dumps(result))
raise SystemExit(0 if passed else 1)
