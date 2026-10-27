"""Temporary, audited receive-buffer sysctl; no persistent system configuration."""
import argparse
import fcntl
import json
from pathlib import Path
import subprocess
import time

TARGET = 8 * 1024 * 1024
REQUEST = 4 * 1024 * 1024  # Existing Link setsockopt request, unchanged.


def control(root, restore=False):
    state = Path(root) / 'operator_v1/state'
    state.mkdir(parents=True, exist_ok=True)
    record = state / 'receive_buffer_sysctl.json'
    with (state / 'receive_buffer.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
        current = int(Path('/proc/sys/net/core/rmem_max').read_text())
        old = json.loads(record.read_text()) if record.exists() else {}
        if restore:
            if not old or old.get('boot_id') != boot or old.get('restored'):
                return dict(ok=True, message='无需恢复：没有本次启动的临时修改', actual=current)
            if current != old['applied']:
                return dict(ok=False, message='当前rmem_max已被其他操作改变，拒绝覆盖', actual=current, record=old)
            target = old['original']
        else:
            if current >= TARGET:
                return dict(ok=True, message='接收缓冲内核上限已满足，无需修改', actual=current)
            target = TARGET
            if not old or old.get('boot_id') != boot or old.get('restored'):
                old = dict(boot_id=boot, original=current, applied=target, restored=False,
                           created_unix=time.time())
                record.write_text(json.dumps(old, indent=2))
        print('仅临时设置 net.core.rmem_max=%d；需要时请在终端输入sudo密码。' % target, flush=True)
        p = subprocess.run(['sudo', 'sysctl', '-w', 'net.core.rmem_max=%d' % target])
        actual = int(Path('/proc/sys/net/core/rmem_max').read_text())
        ok = p.returncode == 0 and actual == target
        if ok:
            old['restored'] = restore
            old['last_change_unix'] = time.time()
            record.write_text(json.dumps(old, indent=2))
        return dict(ok=ok, actual=actual, record=old,
                    message='已核实实际内核值；没有写永久sysctl配置' if ok else '权限不足或设置未生效，未确认修复')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=['set', 'restore'])
    p.add_argument('--root', required=True)
    a = p.parse_args()
    result = control(a.root, a.action == 'restore')
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(0 if result['ok'] else 1)
