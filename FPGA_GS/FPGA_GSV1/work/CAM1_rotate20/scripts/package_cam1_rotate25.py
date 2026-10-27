# -*- coding: utf-8 -*-
"""Package a real STA-passing complete candidate; never overwrite releases."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib
import json
import re
import shutil

root = Path(__file__).resolve().parents[1]
project = root.parents[1]
run = sorted((root/'build').glob('CAM1_OV3660_3_5_8_ROTATE25_CANDIDATE_*'))[-1]
dest = project/'release/FPGA_GSV1_CAM1_OV3660_3_5_8_ROTATE25_CANDIDATE'
base = project/'release/FPGA_GSV1_CAM1_OV3660_3_5_7_SYNC_CANDIDATE'
assert not dest.exists(), 'Never overwrite release packages'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
result = json.loads((run/'result.json').read_text(encoding='utf-8-sig'))
assert result['BuildPass'] and result['ExistingConstraintsMet'] and result['InputsUnchanged']
for item in json.loads((run/'inputs.json').read_text(encoding='utf-8-sig')):
    assert sha(run/item['RelativePath']).upper() == item['SnapshotSHA256']
    assert sha(Path(item['Source'])).upper() == item['SHA256']
scope = json.loads((root/'reports/CAM1_358_scope.json').read_text())
assert scope['protected_constraints_and_PHY_PLL_identical'] and not scope['overlap']
assert sha(root/'constraints/mes50hp.fdc') == sha(base/'source/constraints/mes50hp.fdc')
for name in ['config_rotate1.log','config_rotate0.log','cam1_rotate25.log','cam1_rate_status.log','cam1_byte_verdict.log']:
    log = (root/'reports'/name).read_text()
    assert 'PASS' in log and 'FATAL' not in log, name
timing = (run/'report_timing/fpga_gsv1_top.rtr').read_text(errors='replace')
assert 'Design Summary : All Constraints Met.' in timing
sections = {}
for m in re.finditer(r'(?m)^(Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((Slow|Fast) Corner\):', timing):
    rows, pending = [], []
    for line in timing[m.end():].split('====================================================================================================',1)[0].splitlines():
        r = re.match(r'\s*(.*?)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',line)
        if r:
            rows.append(dict(clocks=(' '.join(pending)+' '+r[1]).strip(),slack_ns=float(r[2]),
                total_slack_ns=float(r[3]),failing_endpoints=int(r[4]),endpoints=int(r[5])))
            pending = []
        elif line.strip() and not any(v in line for v in ['****','-----','Endpoints','Clock','TNS','THS','WPWS']):
            pending.append(line.strip())
    assert rows and all(r['slack_ns']>=0 and not r['failing_endpoints'] for r in rows)
    sections[f'{m[1]}_{m[2]}'] = rows
assert len(sections)==10
prr = (run/'place_route/fpga_gsv1_top.prr').read_text(errors='replace')
row = next(l for l in prr.splitlines() if re.match(r'\| fpga_gsv1_top\s+\|',l))
cells = [s.strip() for s in row.split('|')][1:]
resources = dict(LUT=int(cells[1]), FF=int(cells[2]), DRM=float(cells[5]), PLL=int(cells[18]))
for name in ['CLMA','CLMS']:
    m = re.search(rf'\| Use of {name}\s+\|\s+(\d+)\s+\|\s+(\d+)',prr)
    assert m
    resources[name] = dict(used=int(m[1]),available=int(m[2]))
old = json.loads((base/'artifact.json').read_text(encoding='utf-8-sig'))
assert sha(Path(old['bitstream'])) == old['sha256']
delta = {k:resources[k]-old['resources'][k] for k in ['LUT','FF','DRM','PLL']}
delta.update({k:resources[k]['used']-old['resources'][k]['used'] for k in ['CLMA','CLMS']})
generated = datetime.fromisoformat(re.sub(r'(\.\d{6})\d+',r'\1',result['GeneratedTime']).replace('Z','+00:00'))
bit = dest/Path(result['Release']).name
summary = dict(version='3.5.8 CAM1 rotate180 native720 nominal25fps candidate',
    classification='complete_function_candidate_pending_board_rates',bitstream=str(bit),
    sha256=result['SHA256'].lower(),generated_utc=result['GeneratedTime'],
    generated_Asia_Shanghai=generated.astimezone(timezone(timedelta(hours=8))).isoformat(),
    build_pass=True,declared_constraints_met=True,source_snapshot_verified=True,
    resources=resources,resource_delta_vs_357=delta,STA_summaries=sections,
    baseline_357_user_accepted=True,rollback=old['bitstream'],rollback_sha256=old['sha256'],
    changed=scope['changed_production_files'],CAM1_rotate_180=True,
    HTS=1800,VTS=800,nominal_SYSCLK_Hz=36000000,nominal_byte_PCLK_Hz=72000000,
    nominal_fps=25,actual_capture_fps=None,actual_DDR_publish_fps=None,actual_visible_fps=None,
    exposure_ceiling_ms=39.8,night_frame_extension=False,narrower_FOV=True,
    native_output=[1280,720],raw_DDR_format='RGB565',
    XCLK_directly_measured=False,XCLK_inference_pending_candidate_board=True,
    CAM1_external_pad_skew_measured=False,PHY_external_PVT_PCB_signed_off=False,
    network_PLL_PHY_RGMII_source_identical=True,constraints_identical_to_357=True,
    four_sources_20fps_completed=False,programmed_by_agent=False,
    unrelated_historical_tests_rerun=False,build_directory=str(run))
dest.mkdir(parents=True)
for name in ['rtl','vendor','constraints','config']:
    shutil.copytree(run/name,dest/'source'/name)
shutil.copy2(run/'flow.tcl',dest/'source/flow.tcl')
for name in ['sim','scripts','tools']:
    shutil.copytree(root/name,dest/('source' if name!='tools' else '')/name,
                    ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
(dest/'reports').mkdir()
for name in ['CAM1_358_design_review.md','CAM1_358_user_report.md','baseline_acceptance.md',
             'CAM1_358_scope.json','CAM1_358_vs_357.diff','ov3660_table_manifest.json',
             'config_rotate1.log','config_rotate0.log','cam1_rotate25.log','cam1_rate_status.log','cam1_byte_verdict.log','cam1_decoder.log']:
    shutil.copy2(root/'reports'/name,dest/'reports'/name)
shutil.copytree(root/'reports/sources',dest/'reports/sources')
for name in ['result.json','inputs.json','pds_console.log']:
    shutil.copy2(run/name,dest/'reports'/name)
for name in ['report_timing/fpga_gsv1_top.rtr','place_route/fpga_gsv1_top.prr']:
    shutil.copy2(run/name,dest/'reports'/Path(name).name)
shutil.copy2(result['Release'],bit)
assert sha(bit) == summary['sha256']
(dest/'artifact.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
readme = (root/'reports/CAM1_358_user_report.md').read_text(encoding='utf-8')
readme += f"\n## 本包实际产物\n\n唯一候选：{bit}\n\n生成时间（北京时间）：{summary['generated_Asia_Shanghai']}\n\nSHA256：{summary['sha256']}\n\n"
readme += f"资源：{json.dumps(resources,ensure_ascii=False)}；相对3.5.7变化：{json.dumps(delta,ensure_ascii=False)}。\n\n"
for name,rows in sections.items():
    readme += f"- {name}最小裕量：{min(r['slack_ns'] for r in rows):.3f}ns；失败端点0。\n"
readme += f"\n3.5.7可用回退位流：{old['bitstream']}\n\nSHA256：{old['sha256']}\n"
(dest/'README.md').write_text(readme,encoding='utf-8')
(dest/'SHA256SUMS.txt').write_text('\n'.join(f'{sha(p)}  {p.relative_to(dest).as_posix()}'
    for p in sorted(dest.rglob('*')) if p.is_file())+'\n',encoding='utf-8')
print(json.dumps({k:summary[k] for k in ['version','bitstream','sha256','generated_Asia_Shanghai','resources','resource_delta_vs_357']},ensure_ascii=False,indent=2))
