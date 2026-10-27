# -*- coding: utf-8 -*-
"""C1R8 UART rate decoder. Counts new source frames, never HDMI refreshes."""
import argparse
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('capture', type=Path)
p.add_argument('--output', type=Path)
p.add_argument('--minimum-window', type=float, default=0)
a = p.parse_args()
records = []
for line in a.capture.read_text(encoding='utf-8-sig').splitlines():
    if not line.startswith('N2 35O '):
        continue
    try:
        w = [int(v, 16) for v in line.split()[2:]]
    except ValueError:
        continue
    if len(w) != 40 or w[12] != 0x43315238:
        continue
    records.append(dict(tag='C1R8', configured=bool(w[14] & 0x04000000),
        config_failed=bool(w[14] & 0x08000000), config_error=w[14] >> 28,
        pixels=w[13], rows=w[14] & 65535, geometry_errors=(w[14] >> 16) & 255,
        geometry_error_meanings=[name for i, name in enumerate([
            'line length', 'row count', 'DE during VS', 'counter saturation', 'timeout',
            'RGB565 odd byte or tuple overflow'])
            if w[14] & (1 << (16+i))],
        capture_good=w[15] & 65535, capture_bad=w[15] >> 16,
        capture_start_ms=w[16], ddr_published=w[17] >> 16,
        displayed_new=w[17] & 65535, reference_ms=w[18],
        actual_byte_pclk_hz=w[19], inferred_xclk_hz=w[19]/3 if w[19] else None,
        pll_falls=w[9], phy_ready_falls=w[10]))

result = dict(tag='C1R8', records=len(records), completed=False, snapshots=records,
    notes=['XCLK is inferred from measured PCLK and mandatory PLL readback; not probed directly.',
           'Capture verdict closes at next VS; its own frame-start timestamps bound capture fps.',
           'DDR/display counts use the same first/last atomic UART records and reference_ms window.',
           'Display counts require CAM1 selected, all requested rows complete, no underflow, distinct frame ID.',
           '16bit counters wrap modulo65536; short/60s windows cannot wrap more than once at25fps.'])
if len(records) >= 2:
    f, z = records[0], records[-1]
    delta = lambda key: (z[key]-f[key]) & 65535
    dt = ((z['reference_ms']-f['reference_ms']) & 0xffffffff)/1000
    capture_dt = ((z['capture_start_ms']-f['capture_start_ms']) & 0xffffffff)/1000
    result.update(reference_window_seconds=dt, capture_window_seconds=capture_dt,
        capture_good_delta=delta('capture_good'), capture_bad_delta=delta('capture_bad'),
        ddr_publish_delta=delta('ddr_published'), display_new_delta=delta('displayed_new'),
        capture_fps=delta('capture_good')/capture_dt if capture_dt else None,
        ddr_publish_fps=delta('ddr_published')/dt if dt else None,
        display_new_fps=delta('displayed_new')/dt if dt else None)
    result['geometry_ok'] = all(r['configured'] and not r['config_failed'] and not r['config_error']
        and r['pixels']==921600 and r['rows']==720 and not r['geometry_errors'] for r in records)
    epoch_ok = all(0 < ((v['reference_ms']-u['reference_ms']) & 0xffffffff) <= 5000
                   for u,v in zip(records,records[1:]))
    result['reference_epoch_consistent'] = epoch_ok
    result['completed'] = epoch_ok and dt >= a.minimum_window and capture_dt > 0
    result['rate_quality_pass'] = (result['completed'] and result['geometry_ok']
        and result['capture_bad_delta']==0 and all(result[k] is not None and result[k]>=20
        for k in ('capture_fps', 'ddr_publish_fps', 'display_new_fps')))
else:
    result['error'] = '采样未完成：没有至少两条完整C1R8记录；不要把旧版本标识当成本版数据。'
out = json.dumps(result, ensure_ascii=False, indent=2)
if a.output:
    a.output.write_text(out+'\n', encoding='utf-8')
print(out)
raise SystemExit(0 if result['completed'] else 2)
