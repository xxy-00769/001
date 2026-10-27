"""Read-only, bounded front-camera freeze evidence collector (stdlib, no UDP bind).

Never starts/stops a service, changes a NIC/sysctl, or attaches a debugger.
Use collect_freeze.ps1 to copy evidence back through the existing SSH identity.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import urllib.request


def read(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return None


def number(path):
    try:
        return int(read(path))
    except (TypeError, ValueError):
        return None


def run(args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=2)
        return dict(code=p.returncode, stdout=p.stdout, stderr=p.stderr)
    except (OSError, subprocess.TimeoutExpired) as e:
        return dict(code=None, error=str(e))


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def process(pid):
    p = Path('/proc') / str(pid)
    try:
        stat = (p / 'stat').read_text().split(') ', 1)[1].split()
        return dict(pid=int(pid), start_ticks=stat[19], state=stat[0],
                    cwd=str((p / 'cwd').resolve(strict=True)),
                    argv=(p / 'cmdline').read_bytes().decode().rstrip('\0').split('\0'))
    except (OSError, ValueError):
        return None


def processes(root):
    result = []
    for path in Path('/proc').iterdir():
        if not path.name.isdigit():
            continue
        p = process(path.name)
        if (p and p['cwd'] == str(root) and len(p['argv']) > 1
                and Path(p['argv'][1]).name == 'main.py'):
            result.append(p)
    return result


def threads(pid):
    result = []
    try:
        for task in (Path('/proc') / str(pid) / 'task').iterdir():
            s = read(task / 'stat')
            if not s:
                continue
            f = s.split(') ', 1)[1].split()
            result.append(dict(tid=int(task.name), name=read(task / 'comm'),
                               state=f[0], wchan=read(task / 'wchan'),
                               user_ticks=int(f[11]), system_ticks=int(f[12])))
    except OSError:
        pass
    return result


def socket_rows(pids, port, family='udp'):
    owned = {}
    for pid in pids:
        try:
            for fd in (Path('/proc') / str(pid) / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:['):
                    owned.setdefault(target[8:-1], []).append(dict(pid=pid, fd=fd.name))
        except OSError:
            continue
    rows = []
    for proto in (family, family + '6'):
        data = read('/proc/net/' + proto)
        for line in (data or '').splitlines()[1:]:
            f = line.split()
            if int(f[1].rsplit(':', 1)[1], 16) != port:
                continue
            if family == 'tcp' and f[3] != '0A':
                continue
            tx, rx = f[4].split(':')
            rows.append(dict(protocol=proto, local_hex=f[1], inode=f[9],
                             owners=owned.get(f[9], []),
                             service_owned=f[9] in owned,
                             rx_queue_bytes=int(rx, 16), tx_queue_bytes=int(tx, 16),
                             drops=int(f[12]) if len(f) > 12 else None,
                             raw=line))
    return rows


def udp_global():
    lines = (read('/proc/net/snmp') or '').splitlines()
    for a, b in zip(lines, lines[1:]):
        if a.startswith('Udp:') and b.startswith('Udp:'):
            return {k: int(v) for k, v in zip(a.split()[1:], b.split()[1:])}
    return {}


def http_status(port):
    start = time.monotonic()
    try:
        # Direct loopback: no proxy and no access via the Wi-Fi/SSH tunnel.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open('http://127.0.0.1:%d/status.json' % port, timeout=.6) as r:
            data = r.read(1024 * 1024)
            return dict(ok=True, code=r.status, data=json.loads(data),
                        elapsed_ms=round((time.monotonic() - start) * 1000, 2))
    except Exception as e:
        return dict(ok=False, error=str(e), elapsed_ms=round((time.monotonic() - start) * 1000, 2))


def hardware(interface):
    r = run(['ethtool', '-S', interface])
    values = {}
    for line in r.get('stdout', '').splitlines():
        k, sep, v = line.strip().partition(':')
        if sep:
            try:
                values[k] = int(v.strip())
            except ValueError:
                pass
    return dict(command=r, counters=values)


def sample(c, root):
    start = time.monotonic()
    ps = processes(root)
    nic = Path('/sys/class/net') / c['interface']
    statdir = nic / 'statistics'
    counters = {p.name: number(p) for p in statdir.iterdir()} if statdir.exists() else {}
    return dict(monotonic=start, wall_time=dt.datetime.now().astimezone().isoformat(),
                boot_id=read('/proc/sys/kernel/random/boot_id'), uptime=read('/proc/uptime'),
                processes=ps, threads={str(p['pid']): threads(p['pid']) for p in ps},
                sockets=socket_rows([p['pid'] for p in ps], int(c['udp_port'])),
                http_listeners=socket_rows([p['pid'] for p in ps], int(c['web_port']), 'tcp'),
                carrier=number(nic / 'carrier'), operstate=read(nic / 'operstate'),
                speed_mbps=number(nic / 'speed'), nic=counters,
                udp_global=udp_global(), status=http_status(int(c['web_port'])),
                capture_end_monotonic=time.monotonic())


def delta(a, b):
    if not isinstance(a, (float, int)) or not isinstance(b, (float, int)) or b < a:
        return None
    return b - a


def deltas(a, b):
    return {k: delta(a.get(k), b.get(k)) for k in sorted(set(a) | set(b))}


def compare(a, b, ha, hb):
    da, db = a['status'].get('data', {}), b['status'].get('data', {})
    la, lb = da.get('link') or {}, db.get('link') or {}
    ia = [(p['pid'], p['start_ticks']) for p in a['processes']]
    ib = [(p['pid'], p['start_ticks']) for p in b['processes']]
    # Confirm both HTTP listeners belong to the same service in the saved ss output
    # before interpreting these as service statistics. Unknown values remain null.
    same_process = bool(len(ia) == 1 and ia == ib and a['boot_id'] == b['boot_id'])
    http_owned = all(any(s['service_owned'] for s in x['http_listeners']) for x in (a, b))
    same_session = bool(same_process and http_owned and la.get('session') and la.get('session') == lb.get('session'))
    keys = ('heartbeat_tx', 'heartbeat_or_welcome', 'rx_packets', 'front_fragments',
            'complete_frames', 'bad_packets', 'wrong_session', 'wrong_peer',
            'send_errors', 'receive_errors', 'assembly_dropped', 'assembly_duplicates')
    # Counter omissions mean zero only in this implementation and the same readable session.
    link_delta = {k: delta(la.get(k, 0), lb.get(k, 0)) if same_session else None for k in keys}
    sa = {s['inode']: s for s in a['sockets'] if s['service_owned']}
    sb = {s['inode']: s for s in b['sockets'] if s['service_owned']}
    drops = {inode: delta(sa[inode]['drops'], sb[inode]['drops'])
             for inode in sa.keys() & sb.keys()} if same_process else {}
    return dict(window_seconds=b['monotonic'] - a['monotonic'], same_process=same_process,
                same_session=same_session, nic_delta=deltas(a['nic'], b['nic']),
                udp_global_delta=deltas(a['udp_global'], b['udp_global']),
                hardware_delta=deltas(ha['counters'], hb['counters']),
                service_socket_drop_delta_by_inode=drops,
                link_delta=link_delta,
                processed_delta=delta(da.get('processed'), db.get('processed')) if same_session else None)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--seconds', type=float, default=30)
    args = parser.parse_args()
    c = json.loads(Path(args.config).read_text(encoding='utf-8-sig'))
    root = Path(c['remote_dir']).resolve(strict=True)
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=False)
    preserved = {}
    for name, rel in [('service.console.log', 'operator_v1/state/service.console.log'),
                      ('service.json', 'operator_v1/state/service.json'),
                      ('events.jsonl', c['output'] + '/events.jsonl')]:
        p = root / rel
        try:
            shutil.copyfile(p, out / name)
            preserved[name] = dict(source=str(p), mtime=p.stat().st_mtime, bytes=p.stat().st_size)
        except OSError as e:
            preserved[name] = dict(source=str(p), error=str(e))
    hashes = {}
    for rel in ('main.py', 'link.py', 'vendor/protocol.py', 'manifest.json'):
        try:
            hashes[rel] = hashlib.sha256((root / rel).read_bytes()).hexdigest()
        except OSError:
            hashes[rel] = None
    meta = dict(directory=str(root), preserved=preserved, sha256=hashes,
                uname=run(['uname', '-a']), boot_time=run(['uptime', '-s']),
                address=run(['ip', '-j', 'address', 'show', 'dev', c['interface']]),
                route=run(['ip', '-j', 'route', 'get', c['fpga_ip']]),
                neighbors=run(['ip', '-j', 'neigh', 'show', 'dev', c['interface']]),
                rmem_max=number('/proc/sys/net/core/rmem_max'),
                rmem_default=number('/proc/sys/net/core/rmem_default'),
                ss_start=run(['ss', '-uanpem', 'sport = :%d' % c['udp_port']]),
                listeners_start=run(['ss', '-ltnup']))
    save(out / 'metadata.json', meta)
    h0 = hardware(c['interface'])
    a = sample(c, root)
    save(out / 'status_initial.json', a['status'])
    samples = [a]
    duration = min(60, max(1, args.seconds))
    deadline = a['monotonic'] + duration
    with (out / 'samples.jsonl').open('w', encoding='utf-8') as log:
        log.write(json.dumps(a, ensure_ascii=False) + '\n')
        log.flush()
        due = a['monotonic'] + 1
        while True:
            time.sleep(max(0, min(due, deadline) - time.monotonic()))
            s = sample(c, root)
            samples.append(s)
            log.write(json.dumps(s, ensure_ascii=False) + '\n')
            log.flush()
            if s['monotonic'] >= deadline:
                break
            due = max(due + 1, s['capture_end_monotonic'])
    h1 = hardware(c['interface'])
    b = samples[-1]
    result = compare(a, b, h0, h1)
    result.update(first=a, last=b, hardware_start=h0, hardware_end=h1,
                  ss_end=run(['ss', '-uanpem', 'sport = :%d' % c['udp_port']]),
                  listeners_end=run(['ss', '-ltnup']), config=c, sample_count=len(samples))
    notes = ['只读采样：没有启动/停止服务，没有绑定业务UDP端口，没有sudo、抓包或网络/sysctl修改。',
             '全机UDP计数仅作旁证；服务丢包仅归属于同PID/start_ticks、同socket inode。',
             '缺失服务/会话/socket的增量为null或空映射，不当作0；heartbeat_tx为发送轮次。',
             'hardware_delta涵盖ethtool窗口（包围主采样窗，边缘有命令耗时），NIC/UDP/link主窗严格对齐。',
             '既有版本未暴露接收线程native_id、缺片位置/当前组帧frame_id；仅凭OS线程清单不能确认接收线程身份。']
    conclusions = []
    if not a['processes'] and not b['processes']:
        conclusions.append('当前30秒窗口服务未运行，接收线程未运行；不能还原重启前socket丢包、组帧及处理阻塞原因。')
    if all(s['carrier'] == 0 for s in samples):
        conclusions.append('本窗口eth0持续无载波；与历史千兆链路现场不同。')
    if not a['status']['ok'] and not b['status']['ok']:
        conclusions.append('板上127.0.0.1状态接口不可访问；不经过Wi-Fi/SSH，不能归因为浏览器或Wi-Fi超时。')
    if result['same_session']:
        ld = result['link_delta']
        if any((v or 0) > 0 for v in result['service_socket_drop_delta_by_inode'].values()):
            conclusions.append('同一服务socket的drops增长，已有主机socket丢包证据；需结合实际缓冲/接收速率定位。')
        if ld['heartbeat_or_welcome'] and not ld['front_fragments']:
            conclusions.append('同会话心跳/欢迎回包增长，但视频分片没有增长；需查视频上传/分发。')
        if ld['front_fragments'] and not ld['complete_frames']:
            conclusions.append('分片持续但无完整帧；本版本未记录缺片位置，不能确定丢片环节或组帧规则错误。')
        if ld['complete_frames'] and result['processed_delta'] == 0:
            conclusions.append('完整帧增长而processed不变，应查处理线程。')
    result.update(notes=notes, conclusions=conclusions)
    save(out / 'window.json', result)
    lines = ['M4-01 前摄冻结只读采样', '目录：' + str(root),
             '开始：' + a['wall_time'], '结束：' + b['wall_time'],
             '窗口：%.3f秒，样本：%d' % (result['window_seconds'], len(samples)),
             'rmem_max：' + str(meta['rmem_max']),
             'NIC增量：' + json.dumps(result['nic_delta'], ensure_ascii=False),
             '全机UDP增量（非服务专属）：' + json.dumps(result['udp_global_delta']),
             '服务socket drops增量：' + json.dumps(result['service_socket_drop_delta_by_inode']),
             '同session协议增量：' + json.dumps(result['link_delta']),
             *conclusions, *notes]
    (out / 'window.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(json.dumps(dict(ok=True, output=str(out), conclusions=conclusions), ensure_ascii=False))


if __name__ == '__main__':
    main()
