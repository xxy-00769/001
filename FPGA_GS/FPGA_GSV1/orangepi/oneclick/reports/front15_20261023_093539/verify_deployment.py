"""Read-only release identity and retained source checks; no UDP client/restart."""
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import urllib.request

root = Path('/home/orangepi/fpga_gs_m401_v0_1_2_20261021')
manifest = json.loads((root/'front15_release.json').read_text())
checks = {}
for name, expected in manifest['sha256'].items():
    remote = name.replace('oneclick/', 'operator_v1/')
    path = root/remote
    if path.exists():
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        checks[name] = dict(actual=actual, expected=expected, matches=actual == expected)
unchanged = {}
with tarfile.open(root/manifest['backup']) as archive:
    for name, expected in manifest['unchanged_sha256'].items():
        current = hashlib.sha256((root/name).read_bytes()).hexdigest()
        old = hashlib.sha256(archive.extractfile(name).read()).hexdigest()
        unchanged[name] = dict(current=current, backup=old, matches=current == old == expected)
with urllib.request.urlopen('http://127.0.0.1:8080/status.json?t=release-check', timeout=5) as response:
    status = json.load(response)
service = json.loads((root/'operator_v1/state/service.json').read_text())
tests = subprocess.run([str(root/'.venv/bin/python'), str(root/'operator_v1/test_front_fps.py')],
                       capture_output=True, text=True, cwd=root)
result = dict(version=manifest['version'], checks=checks, unchanged=unchanged,
              service=service, status=status, targeted_tests=dict(exit_code=tests.returncode,
              stdout=tests.stdout, stderr=tests.stderr),
              rmem_max=Path('/proc/sys/net/core/rmem_max').read_text().strip())
print(json.dumps(result, ensure_ascii=False, indent=2))
assert all(x['matches'] for x in checks.values())
assert all(x['matches'] for x in unchanged.values())
assert tests.returncode == 0
