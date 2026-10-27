"""One controlled ARP/CRC sample. Standard library; no configuration writes."""
import argparse
import json
import os
from pathlib import Path
import re
import select
import socket
import struct
import subprocess
import time

BOARD_IP = '192.168.60.2'
HOST_IP = '192.168.60.1'
BOARD_MAC = bytes.fromhex('020047535632')


def command(args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=3)
        return dict(code=p.returncode, stdout=p.stdout, stderr=p.stderr)
    except (OSError, subprocess.TimeoutExpired) as e:
        return dict(code=None, stdout='', stderr=str(e))


def snapshot(interface):
    stats = command(['ethtool', '-S', interface])
    hw = {m[1]: int(m[2]) for m in re.finditer(r'^\s*(\S+):\s*(\d+)\s*$', stats['stdout'], re.M)}
    sys = {}
    for name in ('rx_packets', 'rx_bytes', 'rx_errors', 'rx_crc_errors', 'tx_packets'):
        try:
            sys[name] = int(Path('/sys/class/net', interface, 'statistics', name).read_text())
        except OSError:
            sys[name] = None
    return dict(time=time.time(), hardware=hw, sysfs=sys, ethtool_error=stats['stderr'])


def delta(a, b):
    return {k: (b[k] - v if isinstance(v, int) and isinstance(b.get(k), int) and b[k] >= v else None)
            for k, v in a.items() if k in b}


def parse_board_arp(packet):
    if len(packet) < 42 or packet[12:14] != b'\x08\x06':
        return None
    if packet[14:20] != bytes.fromhex('000108000604'):
        return None
    if packet[6:12] != BOARD_MAC or packet[22:28] != BOARD_MAC:
        return None
    if packet[28:32] != socket.inet_aton(BOARD_IP):
        return None
    if packet[38:42] != socket.inet_aton(HOST_IP):
        return None
    op = int.from_bytes(packet[20:22], 'big')
    return op if op in (1, 2) else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--interface', default='eth0')
    ap.add_argument('--seconds', type=float, default=10)
    args = ap.parse_args()
    if os.geteuid() != 0:
        raise SystemExit('Run this sampling entry with sudo; raw ARP requires CAP_NET_RAW. No installation needed.')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', args.interface) or not 5 <= args.seconds <= 30:
        raise SystemExit('Invalid interface/window')
    address = command(['ip', '-j', 'addr', 'show', 'dev', args.interface])
    entries = json.loads(address['stdout'] or '[]')
    if not any(a.get('local') == HOST_IP for e in entries for a in e.get('addr_info', [])):
        raise SystemExit(f'{args.interface} does not have {HOST_IP}; no configuration was changed.')
    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0806))
    sock.bind((args.interface, 0))
    mac = sock.getsockname()[4]
    sock.setblocking(False)
    packet = b'\xff' * 6 + mac + b'\x08\x06'
    packet += struct.pack('!HHBBH', 1, 0x0800, 6, 4, 1)
    packet += mac + socket.inet_aton(HOST_IP) + b'\0' * 6 + socket.inet_aton(BOARD_IP)
    packet = packet.ljust(60, b'\0')
    before = snapshot(args.interface)
    # An ephemeral normal UDP send lets the kernel request ARP if necessary.
    # It neither binds the LIVE_FRONT port nor rewrites/deletes neighbors.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as trigger:
        trigger.bind((HOST_IP, 0))
        trigger.sendto(b'E1_ARP_TRIGGER', (BOARD_IP, 50000))
    start = time.monotonic()
    sent = requests = replies = other = 0
    lengths = {}
    examples = []
    while time.monotonic() - start < args.seconds:
        now = time.monotonic() - start
        if sent < int(args.seconds * 2) and now >= sent * 0.5:
            sock.send(packet)
            sent += 1
        readable, _, _ = select.select([sock], [], [], 0.02)
        if not readable:
            continue
        data, info = sock.recvfrom(4096)
        if info[2] == socket.PACKET_OUTGOING:
            continue
        op = parse_board_arp(data)
        if op:
            requests += op == 1
            replies += op == 2
            lengths[str(len(data))] = lengths.get(str(len(data)), 0) + 1
            if len(examples) < 3:
                examples.append(data[:80].hex())
        else:
            other += 1
    sock.close()
    after = snapshot(args.interface)
    hd = delta(before['hardware'], after['hardware'])
    sd = delta(before['sysfs'], after['sysfs'])
    # RK3588's hardware MMC counter is the primary evidence from this site.
    crc_name = 'mmc_rx_crc_error'
    crc = hd.get(crc_name)
    fallback = sd.get('rx_crc_errors')
    neighbor = command(['ip', '-j', 'neigh', 'show', BOARD_IP, 'dev', args.interface])
    n = json.loads(neighbor['stdout'] or '[]')
    learned = any(e.get('lladdr', '').lower() == '02:00:47:53:56:32'
                  and 'PERMANENT' not in e.get('state', []) for e in n)
    enough = requests + replies >= 5
    physical_pass = (enough and crc == 0) if crc is not None else None
    full_pass = physical_pass is True and replies >= 3 and learned
    result = dict(experiment='NET2_OFFICIAL_BASELINE_E1_NOT_FUNCTIONAL_RELEASE',
                  window_seconds=round(time.monotonic()-start, 3), interface=args.interface,
                  expected_board_ip=BOARD_IP, expected_board_mac='02:00:47:53:56:32',
                  host_mac=mac.hex(':'), raw_arp_requests_sent=sent,
                  received_board_arp_requests=requests, received_board_arp_replies=replies,
                  received_arp_lengths_without_fcs=lengths, other_arp=other,
                  hardware_delta=hd, sysfs_delta=sd, hardware_crc_delta=crc,
                  sysfs_crc_fallback_delta=fallback, dynamic_neighbor_matches=learned,
                  neighbor=n, tx_physical_baseline_pass=physical_pass,
                  arp_roundtrip_baseline_pass=full_pass, before=before, after=after,
                  received_examples=examples)
    print('=== E1_SAMPLE_JSON_BEGIN ===')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print('=== E1_SAMPLE_JSON_END ===')
    if full_pass:
        print('PASS: official-structure NET2 ARP roundtrip, valid incoming frames, hardware CRC zero delta.')
    elif physical_pass:
        print('PARTIAL: NET2 TX valid incoming ARP and hardware CRC zero; inspect missing RX/reply/neighbor evidence.')
    elif crc is not None and crc > 0:
        print('FAIL: host hardware CRC errors still increased. Preserve this sample for implementation/port comparison.')
    else:
        print('INCONCLUSIVE: missing frames/counters. Zero CRC without incoming frames is NOT a pass.')
    print('This ARP-only experiment has no LIVE_FRONT heartbeat/video; online=false and no HDMI are expected.')


if __name__ == '__main__':
    main()
