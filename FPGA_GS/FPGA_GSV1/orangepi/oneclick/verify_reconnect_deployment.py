"""Read-only release hash and service identity check; no UDP client or restart."""
import hashlib
import json
import tarfile
from pathlib import Path
from collect_freeze import process, http_status

root=Path(__file__).resolve().parent.parent
release=json.loads((root/'reconnect_release.json').read_text())
checks={}
for name,expected in {**release['sha256'],**release['unchanged_sha256']}.items():
    target=root/('operator_v1/'+name[len('oneclick/'):] if name.startswith('oneclick/') else name)
    actual=hashlib.sha256(target.read_bytes()).hexdigest()
    checks[name]=dict(expected=expected,actual=actual,match=expected==actual)
with tarfile.open(root/release['backup']) as archive:
    unchanged={name:hashlib.sha256(archive.extractfile(name).read()).hexdigest()==digest
               for name,digest in release['unchanged_sha256'].items()}
identity=json.loads((root/'operator_v1/state/service.json').read_text())['identity']
current=process(identity['pid'])
same=bool(current and all(current[k]==identity[k] for k in ('pid','start_ticks','cwd','argv')))
status=http_status(8080)
status.get('data',{}).pop('control_token',None)
result=dict(version=release['version'],checks=checks,unchanged_against_before_archive=unchanged,
            same_running_process=same,process=current,status=status,
            ok=all(x['match'] for x in checks.values()) and all(unchanged.values()) and same
               and status.get('data',{}).get('release')==release['version'])
out=root/'operator_v1/reconnect_backup_20261023/deployment_check.json'
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(dict(ok=result['ok'],same_running_process=same,pid=identity['pid'],output=str(out))))
raise SystemExit(0 if result['ok'] else 1)
