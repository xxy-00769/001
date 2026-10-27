"""Restore the preserved M4-02-r1 source only after the owned service has stopped."""
import tarfile
import urllib.request
import argparse
import os
from pathlib import Path

root=Path(__file__).resolve().parent.parent
args=argparse.ArgumentParser()
args.add_argument('--check',action='store_true',help='validate the preserved archive without restoring or stopping anything')
check=args.parse_args().check
names=('main.py','link.py','feedback.py','preview.html','m402_release.json',
       'operator_v1/ops_manager.py','operator_v1/launcher.ps1')
with tarfile.open(root/'operator_v1/reconnect_backup_20261023/before.tgz') as archive:
    saved={name:archive.extractfile(name).read() for name in names}
if check:
    print('回退归档完整；只读核验通过，未停止服务或覆盖源码。')
    raise SystemExit(0)
# HTTP failure does not prove process exit. Refuse even an unresponsive owned app.
for directory in Path('/proc').iterdir():
    if not directory.name.isdigit():continue
    try:
        argv=(directory/'cmdline').read_bytes().decode().rstrip('\0').split('\0')
        if (directory.stat().st_uid==os.getuid() and (directory/'cwd').resolve()==root
                and len(argv)>1 and Path(argv[1]).name=='main.py'):
            raise SystemExit('本项目服务进程仍在运行，拒绝覆盖；请先使用停止入口。')
    except (OSError,ValueError):pass
try:urllib.request.urlopen('http://127.0.0.1:8080/status.json',timeout=2).close()
except OSError:pass
else:raise SystemExit('服务仍响应，拒绝覆盖。请先使用停止入口。')
for name,content in saved.items():(root/name).write_bytes(content)
release=root/'reconnect_release.json'
if release.exists():release.replace(root/'reconnect_release.inactive.json')
print('已恢复M4-02-r1，服务保持停止；保留fps配置、8MiB缓冲和全部日志。旧版不具备自动重连修复。')
