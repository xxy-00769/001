"""Package the single routed E1 integration candidate; never overwrite releases."""
from pathlib import Path
import datetime, hashlib, json, shutil, zipfile

R = Path(__file__).resolve().parents[1]
P = R.parents[1]
B = R / 'build/M3_06_3_5_4_20261022_185404_116'
D = P / 'release/FPGA_GSV1_M3_06_3_5_4'
assert not D.exists(), 'Preserve existing release; packaging is one-shot'
result = json.loads((B / 'result.json').read_text(encoding='utf-8-sig'))
assert result['BuildPass'] and result['InputsUnchanged']
checks = json.loads((R / 'reports/m364_checks/result.json').read_text())
assert all(checks['checks'].values()) and checks['InputsUnchanged']
assert 'M364_REF_PASS' in (R / 'reports/m364_checks/ref.log').read_text()
hashfile = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
bit = B / 'generate_bitstream/fpga_gsv1_top.sbit'
assert hashfile(bit) == result['SHA256'].lower()
D.mkdir()

def copy(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

# Only source snapshots actually used by the bitstream build.
for folder in ['rtl', 'vendor', 'constraints', 'config']:
    shutil.copytree(B / folder, D / 'source' / folder)
copy(B / 'flow.tcl', D / 'source/flow.tcl')
for name in ['build_m364.ps1', 'configure_m36_endpoints.py', 'check_m364.py', 'package_m364.py']:
    copy(R / 'scripts' / name, D / 'source/scripts' / name)
for name in ['m364_tx_tb.sv', 'm364_burst_tb.sv', 'm364_clock_model.sv', 'm364_ref_tb.sv', 'm361_phy_model.vh', 'm36_line_ram_model.sv']:
    copy(R / 'sim' / name, D / 'source/sim' / name)
(D / 'source/reports').mkdir()
(D / 'source/reports/README.txt').write_text('Build/test outputs are isolated here. See ../../evidence for delivered results.\n')
copy(bit, D / 'FPGA_GSV1_M3_06_3_5_4_HDMI_1080P60.sbit')
for p in (R / 'tools').iterdir():
    if p.is_file():
        copy(p, D / 'tools' / p.name)
for name in ['pds_console.log', 'inputs.json', 'result.json']:
    copy(B / name, D / 'evidence/build' / name)
for name in ['fpga_gsv1_top.prr', 'clock_utilization.txt', 'fpga_gsv1_top_timing_summary_after_hold_fix.txt', 'fpga_gsv1_top_prr.prt']:
    copy(B / 'place_route' / name, D / 'evidence/build/place_route' / name)
# Keep the original build STA, before a documented supplemental-query attempt.
S = R / 'reports/supplemental_camera_sta'
copy(S / 'before_fpga_gsv1_top.rtr', D / 'evidence/build/report_timing/fpga_gsv1_top.rtr')
copy(S / 'before_run.log', D / 'evidence/build/report_timing/run.log')
for p in S.iterdir():
    if p.is_file(): copy(p, D / 'evidence/supplemental_camera_sta' / p.name)
for p in (R / 'reports/m364_checks').iterdir():
    if p.is_file() and p.suffix not in ['.vvp']:
        copy(p, D / 'evidence/checks' / p.name)
for name in ['e1_integration_analysis.md', 'E1_FROZEN_BASELINE.json']:
    copy(R / 'reports' / name, D / 'evidence' / name)
Q = R / 'reports/clock_route_probe'
for name in ['probe.v', 'probe.fdc', 'probe.tcl', 'probe_console.log', 'report_timing/clock_route_probe.rtr', 'place_route/clock_utilization.txt']:
    copy(Q / name, D / 'evidence/clock_route_probe' / name)
copy(R / 'reports/M3_06_3_5_4_delivery.md', D / 'README.md')
manifest = json.loads((B / 'inputs.json').read_text(encoding='utf-8-sig'))
for item in manifest:
    assert hashfile(D / 'source' / item['RelativePath']) == item['SnapshotSHA256'].lower()
artifact = dict(version=result['Version'], status='controlled_integration_candidate_pending_board',
    bitstream=str(D / 'FPGA_GSV1_M3_06_3_5_4_HDMI_1080P60.sbit'),
    sha256=hashfile(bit), generated_utc=result['GeneratedTime'], generated_local='2026-10-22T19:01:45+08:00',
    build_pass=True, declared_constraints_met=True, external_net2_io_signed_off=False,
    inherited_camera_i2c_unclocked_pins=38, programmed=False, board_verified=False,
    source_snapshot_verified=True, build_directory=str(B),
    tools_remote_scp_and_python_help_pass=True, integrated_sudo_sample_completed=False,
    E1_baseline_accepted=True, front_request_fps=5, front_actual_fps=None, right_actual_fps=None)
(D / 'artifact.json').write_text(json.dumps(artifact, indent=2))
sums = [hashfile(p) + '  ' + p.relative_to(D).as_posix() for p in sorted(D.rglob('*')) if p.is_file()]
(D / 'SHA256SUMS.txt').write_text('\n'.join(sums) + '\n')
archive = D.with_suffix('.zip')
assert not archive.exists()
with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as z:
    for p in sorted(D.rglob('*')):
        if p.is_file(): z.write(p, p.relative_to(D.parent))
archive.with_suffix('.zip.sha256').write_text(hashfile(archive) + '  ' + archive.name + '\n')
print(json.dumps(artifact, indent=2))
print('PACKAGE=' + str(archive))
