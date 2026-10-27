"""Check the measured-signature candidate has only the intended CAM1 change."""
from pathlib import Path
import difflib
import hashlib
import json
import re

root = Path(__file__).resolve().parents[1]
base = root.parents[1] / 'release/FPGA_GSV1_CAM1_OV3660_3_5_6_G1_OBSERVATION/source'
allowed = {'rtl/capture/cam_ov3660_table.v', 'rtl/capture/cam_ov3660_config.v'}
changed = []
diff = []
for directory in ['rtl', 'vendor', 'constraints', 'config']:
    for old in (base / directory).rglob('*'):
        if not old.is_file():
            continue
        rel = old.relative_to(base)
        new = root / rel
        assert new.is_file(), rel
        if old.read_bytes() != new.read_bytes():
            name = rel.as_posix()
            assert name in allowed, f'Unexpected change: {name}'
            changed.append(name)
            diff += difflib.unified_diff(old.read_text().splitlines(True), new.read_text().splitlines(True),
                                         fromfile='G1/'+name, tofile='3.5.7/'+name)
assert set(changed) == allowed, changed
assert (root/'flow.tcl').read_bytes() == (base/'flow.tcl').read_bytes()
old = (base/'rtl/capture/cam_ov3660_table.v').read_text()
new = (root/'rtl/capture/cam_ov3660_table.v').read_text()
before = re.findall(r"9'd(\d+):entry=24'h([0-9a-f]+)", old)
after = re.findall(r"9'd(\d+):entry=24'h([0-9a-f]+)", new)
assert len(before) == len(after) == 235
changes = [(a,b) for a,b in zip(before,after) if a != b]
assert len(changes) == 1 and changes[0][0][1] == '474023' and changes[0][1][1] == '474020'
old = (base/'rtl/capture/cam_ov3660_config.v').read_text()
new = (root/'rtl/capture/cam_ov3660_config.v').read_text()
assert new == old.replace("6:expected=24'h474023", "6:expected=24'h474020")
evidence = json.loads((root/'reports/OV3660_G1_actual_decoded.json').read_text())
assert evidence['records'] == 9 and evidence['geometry_bad_delta_mod65536'] == 101
for r in evidence['snapshots']:
    assert r['layout'] == 'C1G1' and r['configured'] and not r['failed'] and r['error_code'] == 0
    assert r['geometry'] == dict(pixels=4344, rows=1, error_bits='03',
                                errors=['wrong line length', 'wrong row count'])
out = dict(changed_vs_G1=changed, table_entry_change=changes,
           only_register_data_changed='4740:23->20', mandatory_readback='4740=20',
           PCLK_setting_unchanged=True, input_sampling_and_gearbox_unchanged=True,
           geometry_guard_unchanged=True, camera0_network_DDR_HDMI_filter_unchanged=True,
           constraints_and_flow_equal=True,
           raw_evidence_sha256=hashlib.sha256((root/'reports/OV3660_G1_actual_uart.txt').read_bytes()).hexdigest())
(root/'reports/CAM1_357_scope.json').write_text(json.dumps(out, indent=2), encoding='utf-8')
(root/'reports/CAM1_357_vs_G1.diff').write_text(''.join(diff), encoding='utf-8')
print('PASS scope: only final CAM1 4740 byte 23->20 and mandatory readback; all capture, protected functions, flow and constraints byte-identical to G1')
