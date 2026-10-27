"""Decode OV36 configuration or C1G1 geometry in the same N2 35O envelope."""
from pathlib import Path
import argparse
import json

p = argparse.ArgumentParser()
p.add_argument('capture', type=Path)
p.add_argument('--output', type=Path)
args = p.parse_args()
records = []
for line in args.capture.read_text(encoding='utf-8-sig').splitlines():
    if not line.startswith('N2 35O '):
        continue
    try:
        w = [int(v, 16) for v in line.split()[2:]]
    except ValueError:
        continue
    if len(w) != 40 or w[12] not in (0x4f563336, 0x43314731):
        continue
    if w[12] == 0x43314731:
        flags = (w[14] >> 24) & 15
        error = w[14] >> 28
        bits = (w[14] >> 16) & 255
        records.append(dict(layout='C1G1', identified=bool(flags & 1),
            id_finished=bool(flags & 2), configured=bool(flags & 4), failed=bool(flags & 8),
            error_code=error, geometry_snapshot_available=True,
            geometry_good_low16=w[15] & 65535, geometry_bad_low16=w[15] >> 16,
            geometry=dict(pixels=w[13], rows=w[14] & 65535, error_bits=f'{bits:02X}',
                errors=[name for bit,name in enumerate(['wrong line length','wrong row count',
                    'DE during VS','counter saturation','timeout']) if bits & (1 << bit)])))
    else:
        status = w[14] & 255
        error = (w[14] >> 8) & 255
        records.append(dict(layout='OV36', first_id=f'{w[13] >> 16:04X}',
            confirmation_id=f'{w[13] & 65535:04X}', identified=bool(status & 1),
            id_finished=bool(status & 2), configured=bool(status & 4), failed=bool(status & 8),
            last_register=f'{w[14] >> 16:04X}', error_code=error,
            error={0:'none',1:'ID refused',2:'write NACK',3:'SCCB timeout',
                4:'readback NACK',5:'register readback mismatch'}.get(error,'unknown'),
            geometry_snapshot_available=False,
            geometry_good_low16=w[15] & 65535, geometry_bad_low16=w[15] >> 16))

report = dict(records=len(records), first=records[0] if records else None,
              last=records[-1] if records else None,
              snapshots=records,
              note='Geometry counts are source reports, not DDR publication/board picture verification.')
if len(records) >= 2:
    report['geometry_good_delta_mod65536'] = (records[-1]['geometry_good_low16']-records[0]['geometry_good_low16']) & 65535
    report['geometry_bad_delta_mod65536'] = (records[-1]['geometry_bad_low16']-records[0]['geometry_bad_low16']) & 65535
text = json.dumps(report, ensure_ascii=False, indent=2)
if args.output:
    args.output.write_text(text+'\n', encoding='utf-8')
print(text)
raise SystemExit(0 if records else 2)
