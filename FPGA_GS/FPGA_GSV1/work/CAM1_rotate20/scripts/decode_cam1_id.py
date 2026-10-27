"""Decode camera words from the existing 40-word N2 UART capture."""
import argparse
import json
from pathlib import Path


def decode(words):
    if len(words) != 40 or words[12] != 0x43414D31:
        return None
    first, confirmation = words[13] >> 16, words[13] & 0xFFFF
    nacks = words[14] >> 16
    finished = bool(words[14] & 2)
    timeout = bool(words[14] & 8)
    valid = finished and not timeout and nacks == 0 and first == confirmation
    phases = ['write_address_0x78', 'register_high', 'register_low', 'read_address_0x79']
    reads = []
    aborted = False
    for read_number in range(4):
        mask = (nacks >> (read_number * 4)) & 15
        states = []
        for phase in range(4):
            if aborted or not finished:
                states.append('not_completed_or_not_attempted')
            elif mask & (1 << phase):
                states.append('NACK_or_timed_out_before_ACK' if timeout else 'NACK')
                aborted = True
            else:
                states.append('ACK')
        reads.append(dict(register='0x300A' if read_number % 2 == 0 else '0x300B',
                          phases=dict(zip(phases, states))))
    return dict(first_id=f'{first:04X}', confirmation_id=f'{confirmation:04X}',
                finished=finished, timeout=timeout,
                compiled_expected_id_matches=bool(words[14] & 4),
                id_read_confirmed=valid,
                model=({0x3660: 'OV3660', 0x5640: 'OV5640'}.get(first, 'other_sensor')
                       if valid else 'unconfirmed'),
                nack_masks=f'{nacks:04X}', reads=reads,
                reset_pin_high=bool(words[15] & 8),
                initial_wait_complete=bool(words[15] & 4),
                raw_href_level=bool(words[15] & 2), raw_vsync_level=bool(words[15] & 1),
                camera_configured=False, camera_frame_publication_enabled=False,
                note='ID-only checkpoint; raw pin levels do not measure activity or timing.')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('capture', type=Path)
    ap.add_argument('--output', type=Path)
    args = ap.parse_args()
    records = []
    for line in args.capture.read_text(encoding='utf-8-sig').splitlines():
        if not line.startswith('N2 35O '):
            continue
        try:
            value = decode([int(v, 16) for v in line.split()[2:]])
        except ValueError:
            continue
        if value is not None:
            records.append(value)
    report = dict(records=len(records), last=records[-1] if records else None,
                  actual_capture=str(args.capture),
                  complete_result=bool(records and records[-1]['finished']))
    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(text + '\n', encoding='utf-8')
    print(text)
    return 0 if report['complete_result'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
