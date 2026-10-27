"""Package the completed ID-only build without rebuilding or programming."""
from pathlib import Path
import hashlib
import json
import shutil

root = Path(__file__).resolve().parents[1]
run = root / 'build/CAM1_ID1_TXDET1_20261023_195422_472'
dest = root.parents[1] / 'release/FPGA_GSV1_CAM1_ID1_TXDET1'
result = json.loads((run / 'result.json').read_text(encoding='utf-8-sig'))
assert result['BuildPass'] and result['InputsUnchanged']
assert not dest.exists(), 'Never overwrite a release'
for item in json.loads((run / 'inputs.json').read_text(encoding='utf-8-sig')):
    snapshot = run / item['RelativePath']
    assert hashlib.sha256(snapshot.read_bytes()).hexdigest().upper() == item['SnapshotSHA256']

summary = {
    **result,
    'CheckpointOnly': True,
    'SensorPhysicallyIdentified': False,
    'CAM1FramePublication': False,
    'Resource': {'FF': 19430, 'LUT': 18981, 'CLMA': 3754, 'CLMS': 2400,
                 'DRM': 93, 'PLL': 5},
    'STA_ns': {'slow_internal_setup_min': 0.365, 'slow_internal_hold_min': 0.157,
               'fast_internal_setup_min': 1.834, 'fast_internal_hold_min': 0.088,
               'slow_nominal_eth2_external_setup': 0.070,
               'slow_nominal_eth2_external_hold': 0.096,
               'id_sys_clk_setup': 12.065, 'id_sys_clk_hold': 0.239},
    'Limitations': ['CAM1 deliberately not configured or published in ID checkpoint',
                    'TY module connector pinout remains unconfirmed',
                    'Existing nominal PHY/PCB external timing assumptions retained',
                    'No board test; future CAM1 capture path is not validated by this build'],
}
(root / 'reports/build_summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
dest.mkdir(parents=True)
for name in ['rtl', 'vendor', 'constraints', 'config']:
    shutil.copytree(run / name, dest / 'source' / name)
shutil.copy2(run / 'flow.tcl', dest / 'source/flow.tcl')
for name in ['scripts', 'sim']:
    shutil.copytree(root / name, dest / 'source' / name)
shutil.copytree(root / 'reports', dest / 'reports', ignore=shutil.ignore_patterns('*.vvp'))
for name in ['result.json', 'inputs.json', 'pds_console.log']:
    shutil.copy2(run / name, dest / 'reports' / name)
for name in ['report_timing/fpga_gsv1_top.rtr', 'place_route/fpga_gsv1_top.prr']:
    shutil.copy2(run / name, dest / 'reports' / Path(name).name)
bit = dest / Path(result['Release']).name
shutil.copy2(result['Release'], bit)
assert hashlib.sha256(bit.read_bytes()).hexdigest().upper() == result['SHA256']
summary['Release'] = str(bit.resolve())
(dest / 'artifact.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
shutil.copy2(root / 'reports/ID1_README.md', dest / 'README.md')
lines = []
for path in sorted(dest.rglob('*')):
    if path.is_file():
        lines.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(dest).as_posix()}')
(dest / 'SHA256SUMS.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
print(json.dumps({'release': str(bit), 'sha256': result['SHA256'],
                  'generated_utc': result['GeneratedTime'], 'files': len(lines)}, indent=2))
