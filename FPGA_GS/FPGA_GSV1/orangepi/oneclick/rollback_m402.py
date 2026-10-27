"""Restore only the preserved front15 source after the operator has stopped its service."""
import json
from pathlib import Path
import tarfile
import urllib.request
import urllib.error

root = Path(__file__).resolve().parent.parent
try:
    urllib.request.urlopen('http://127.0.0.1:8080/status.json', timeout=2).close()
except (OSError, urllib.error.URLError):
    pass
else:
    raise SystemExit('8080仍有服务响应；拒绝覆盖运行中的源码，请先使用停止入口')
with tarfile.open(root/'operator_v1/m402_backup_20261023/front15_before.tgz') as archive:
    for name in ('main.py','link.py','preview.html','front15_release.json','operator_v1/ops_manager.py'):
        (root/name).write_bytes(archive.extractfile(name).read())
release = root/'m402_release.json'
if release.exists() and json.loads(release.read_text())['version']=='M4-02-r1':
    release.unlink()
print('已恢复front15-r1；保留15fps/5fps配置与8MiB缓冲，服务保持停止。新增feedback.py保留但旧版不会导入。')
