"""Verify and package the one completed OV3660 integrated candidate."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import difflib
import hashlib
import json
import re
import shutil

root = Path(__file__).resolve().parents[1]
project = root.parents[1]
run = root / 'build/CAM1_OV3660_3_5_6_CANDIDATE_20261023_203143_877'
dest = project / 'release/FPGA_GSV1_CAM1_OV3660_3_5_6_CANDIDATE'
base = project / 'release/FPGA_GSV1_M3_06_3_5_5_TXDET1_CANDIDATE'
result = json.loads((run / 'result.json').read_text(encoding='utf-8-sig'))
assert result['BuildPass'] and result['ExistingConstraintsMet'] and result['InputsUnchanged']
assert not dest.exists(), 'Never overwrite a release'
for item in json.loads((run / 'inputs.json').read_text(encoding='utf-8-sig')):
    assert hashlib.sha256((run / item['RelativePath']).read_bytes()).hexdigest().upper() == item['SnapshotSHA256']
    assert hashlib.sha256(Path(item['Source']).read_bytes()).hexdigest().upper() == item['SHA256']
for name in ['cam_sccb_write_tb', 'cam_ov3660_config_tb', 'cam3660_dvp_tb']:
    log = (root / f'reports/{name}.log').read_text()
    assert 'PASS ' in log and 'FATAL:' not in log, name

timing = (run / 'report_timing/fpga_gsv1_top.rtr').read_text(errors='replace')
assert 'Design Summary : All Constraints Met.' in timing
sections = {}
for match in re.finditer(r'(?m)^(Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((Slow|Fast) Corner\):', timing):
    section = timing[match.end():].split('====================================================================================================', 1)[0]
    rows = []
    pending = []
    for line in section.splitlines():
        row = re.match(r'\s*(.*?)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$', line)
        if row:
            names = (' '.join(pending) + ' ' + row[1]).strip()
            rows.append(dict(clocks=names, slack_ns=float(row[2]), total_slack_ns=float(row[3]),
                             failing_endpoints=int(row[4]), endpoints=int(row[5])))
            pending=[]
        elif line.strip() and not any(x in line for x in ['****','-----','Endpoints','Clock','TNS','THS','WPWS']):
            pending.append(line.strip())
    assert rows, match[0]
    assert all(r['slack_ns'] >= 0 and r['failing_endpoints'] == 0 for r in rows), match[0]
    sections[f'{match[1]}_{match[2]}'] = rows

prr = (run / 'place_route/fpga_gsv1_top.prr').read_text(errors='replace')
top = next(line for line in prr.splitlines() if re.match(r'\| fpga_gsv1_top\s+\|', line))
cells = [s.strip() for s in top.split('|')][1:]
resources = {'LUT': int(cells[1]), 'FF': int(cells[2]), 'DRM': float(cells[5]), 'PLL': int(cells[18])}
for name in ['CLMA', 'CLMS']:
    match = re.search(rf'\| Use of {name}\s+\|\s+(\d+)\s+\|\s+(\d+)', prr)
    assert match
    resources[name] = {'used': int(match[1]), 'available': int(match[2])}
old = json.loads((base / 'artifact.json').read_text(encoding='utf-8-sig'))
deltas = {k: resources[k]-old['resources'][k] for k in ['LUT','FF']}
deltas.update({k:resources[k]-old['resources'][k]['used'] for k in ['DRM','PLL']})
for k in ['CLMA','CLMS']:
    deltas[k] = resources[k]['used']-old['resources'][k]['used']
generated = datetime.fromisoformat(re.sub(r'(\.\d{6})\d+',r'\1',result['GeneratedTime']).replace('Z', '+00:00'))
bit = dest / Path(result['Release']).name
summary = dict(version='3.5.6 CAM1 OV3660', classification='integrated_candidate_pending_board',
               build_pass=True, source_snapshot_verified=True, declared_STA_pass=True,
               resources=resources, resource_delta_vs_355=deltas, STA_summaries=sections,
               nominal_PHY_model_only=True, external_PHY_PVT_PCB_signed_off=False,
               sensor_ID_board_verified=True, sensor_ID='3660',
               actual_ID_capture='reports/ID1_actual_uart.txt', board_picture_verified=False,
               module_connector_pinout_confirmed=False,
               camera_external_data_skew_measured=False,
               calculated_CAM1_byte_PCLK_Hz=72000000, calculated_CAM1_pixel_clk_Hz=36000000,
               sensor_expected_frame_rate_theoretical=36000000/(2172*1322),
               sensor_actual_frame_rate=None,
               baseline_355_sha256=old['sha256'],
               rollback=str(Path(old['bitstream'])),
               bitstream=str(bit), sha256=result['SHA256'].lower(),
               generated_utc=result['GeneratedTime'],
               generated_Asia_Shanghai=generated.astimezone(timezone(timedelta(hours=8))).isoformat(),
               build_directory=str(run), programmed_by_agent=False,
               untouched_historical_tests_rerun=False)
(root / 'reports/ov3660_build_summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
scope = []
diff = []
for directory in ['rtl','vendor','constraints','config']:
    for path in sorted((run / directory).rglob('*')):
        if not path.is_file():
            continue
        relative = path.relative_to(run)
        previous = base / 'source' / relative
        if not previous.exists() or previous.read_bytes() != path.read_bytes():
            scope.append(str(relative))
            if path.suffix in ['.v','.vh','.fdc','.json']:
                before = previous.read_text(errors='replace').splitlines(True) if previous.exists() else []
                diff += list(difflib.unified_diff(before,path.read_text(errors='replace').splitlines(True),
                                                fromfile='3.5.5/'+relative.as_posix(),tofile='3.5.6/'+relative.as_posix()))
(root / 'reports/ov3660_source_scope.json').write_text(json.dumps(scope, indent=2), encoding='utf-8')
(root / 'reports/ov3660_source_changes.diff').write_text(''.join(diff), encoding='utf-8')

dest.mkdir(parents=True)
for name in ['rtl','vendor','constraints','config']:
    shutil.copytree(run / name, dest / 'source' / name)
shutil.copy2(run / 'flow.tcl', dest / 'source/flow.tcl')
for name in ['scripts','sim']:
    shutil.copytree(root / name, dest / 'source' / name)
shutil.copytree(root / 'reports',dest / 'reports',ignore=shutil.ignore_patterns('*.vvp'))
for name in ['result.json','inputs.json','pds_console.log']:
    shutil.copy2(run / name,dest / 'reports' / name)
for name in ['report_timing/fpga_gsv1_top.rtr','place_route/fpga_gsv1_top.prr']:
    shutil.copy2(run / name,dest / 'reports' / Path(name).name)
shutil.copy2(result['Release'],bit)
assert hashlib.sha256(bit.read_bytes()).hexdigest() == summary['sha256']
(dest / 'artifact.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
readme = (root / 'reports/OV3660_CAM1_fix_report.md').read_text(encoding='utf-8')
readme += '\n## 本次实际构建产物\n\n'
readme += f"生成：{summary['generated_Asia_Shanghai']}；唯一位流：{bit}\n\nSHA256：{summary['sha256']}\n\n"
readme += f"资源：{json.dumps(resources, ensure_ascii=False)}；相对3.5.5变化：{json.dumps(deltas, ensure_ascii=False)}。\n\n"
for name, rows in sections.items():
    readme += f"- {name}最小裕量：{min(r['slack_ns'] for r in rows):.3f}ns，失败端点0。\n"
readme += '\n上述setup/hold最小值可能包含名义PHY外部模型；完整各域数值见artifact及原始rtr。没有放宽约束。\n'
(dest / 'README.md').write_text(readme,encoding='utf-8')
lines=[]
for path in sorted(dest.rglob('*')):
    if path.is_file():
        lines.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(dest).as_posix()}')
(dest / 'SHA256SUMS.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(json.dumps(dict(release=str(bit),sha256=summary['sha256'],generated=summary['generated_Asia_Shanghai'],
                      resources=resources,delta=deltas,files=len(lines)),indent=2))
