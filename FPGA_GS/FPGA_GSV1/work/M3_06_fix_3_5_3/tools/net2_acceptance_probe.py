"""Read-only sampling of existing LIVE_FRONT and NIC hardware counters.

Executed in memory through the existing SSH connection. No UDP socket, sudo,
network changes, remote files, service start, or vision code is used.
"""
import argparse
import base64
import datetime
import json
import re
import subprocess
import time
import urllib.request


def command(args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=4)
        return dict(ok=p.returncode == 0, returncode=p.returncode,
                    stdout=p.stdout, stderr=p.stderr)
    except (OSError, subprocess.TimeoutExpired) as e:
        return dict(ok=False, error=str(e))


def sample(c):
    out = dict(monotonic=time.monotonic())
    out['hardware_command'] = command(['ethtool', '-S', c['interface']])
    out['hardware'] = {}
    if out['hardware_command']['ok']:
        out['hardware'] = {k: int(v) for k, v in re.findall(
            r'^\s*(mmc_rx_(?:framecount_gb|crc_error|octetcount_g)):\s*(\d+)\s*$',
            out['hardware_command']['stdout'], re.M)}
    out['neighbor_command'] = command(['ip', '-j', 'neigh', 'show', 'to',
                                      c['fpga_ip'], 'dev', c['interface']])
    out['neighbors'] = None
    if out['neighbor_command']['ok']:
        try:
            out['neighbors'] = json.loads(out['neighbor_command']['stdout'])
        except ValueError as e:
            out['neighbor_parse_error'] = str(e)
    try:
        with urllib.request.urlopen('http://127.0.0.1:%d/status.json' %
                                    int(c['web_port']), timeout=3) as r:
            out['status'] = dict(ok=True, data=json.load(r))
    except Exception as e:
        out['status'] = dict(ok=False, error=str(e))
    return out


def summarize(a, b, c):
    seconds = b['monotonic'] - a['monotonic']
    hw = {}
    for k in ('mmc_rx_framecount_gb', 'mmc_rx_crc_error', 'mmc_rx_octetcount_g'):
        x, y = a['hardware'].get(k), b['hardware'].get(k)
        hw[k] = y - x if x is not None and y is not None and y >= x else None
    la = a['status'].get('data', {}).get('link', {})
    lb = b['status'].get('data', {}).get('link', {})
    same = bool(a['status']['ok'] and b['status']['ok'] and
                la.get('session') is not None and la.get('session') == lb.get('session'))
    delta = {}
    for k in ('heartbeat_or_welcome', 'front_fragments', 'complete_frames',
              'rx_packets', 'bad_packets'):
        x, y = la.get(k, 0), lb.get(k, 0)
        delta[k] = y - x if same and y >= x else None
    arp = None if b['neighbors'] is None else False
    permanent = False
    for n in b['neighbors'] or []:
        states = n.get('state', [])
        if isinstance(states, str):
            states = [states]
        states = {s.upper() for s in states}
        if n.get('dst') == c['fpga_ip']:
            permanent |= 'PERMANENT' in states or 'NOARP' in states
            if (n.get('lladdr', '').lower() == c['fpga_mac'].lower() and
                    states & {'REACHABLE', 'STALE', 'DELAY', 'PROBE'} and
                    not states & {'PERMANENT', 'NOARP', 'INCOMPLETE', 'FAILED'}):
                arp = True
    checks = dict(automatic_arp=arp, online=lb.get('online'),
                  heartbeat_received=(delta['heartbeat_or_welcome'] > 0
                                      if delta['heartbeat_or_welcome'] is not None else None),
                  new_complete_front=(delta['complete_frames'] > 0
                                      if delta['complete_frames'] is not None else None),
                  hardware_crc_not_growing=(hw['mmc_rx_crc_error'] == 0
                                           if hw['mmc_rx_crc_error'] is not None else None))
    return dict(version='M3-06 3.5.3 TX acceptance / read only',
                utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                window_seconds=round(seconds, 3), session_unchanged=same,
                checks=checks, pass_all=all(v is True for v in checks.values()),
                temporary_static_neighbor_detected=permanent,
                hardware_delta=hw, protocol_delta=delta,
                front_receive_fps=(round(delta['complete_frames'] / seconds, 3)
                                   if same and seconds > 0 else None),
                notes=['Missing/unreadable hardware counter is unknown, never zero.',
                       'Protocol missing Counter keys mean zero only in one readable session.',
                       'Dynamic neighbor is observed; this probe never deletes or adds neighbors.',
                       'Historical nonzero CRC total is allowed; acceptance requires delta zero.'],
                samples=[a, b])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    c = json.loads(base64.b64decode(args.config))
    a = sample(c)
    time.sleep(max(2, min(10, float(c.get('diagnostic_seconds', 4)))))
    b = sample(c)
    print(json.dumps(summarize(a, b, c), ensure_ascii=True))


if __name__ == '__main__':
    main()
