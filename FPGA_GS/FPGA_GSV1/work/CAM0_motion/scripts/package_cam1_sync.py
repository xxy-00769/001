# -*- coding: utf-8 -*-
"""Package one actual STA-passing 3.5.7 sync candidate; never overwrite releases."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib
import json
import re
import shutil

root = Path(__file__).resolve().parents[1]
project = root.parents[1]
run = sorted((root/'build').glob('CAM1_OV3660_3_5_7_SYNC_CANDIDATE_*'))[-1]
dest = project/'release/FPGA_GSV1_CAM1_OV3660_3_5_7_SYNC_CANDIDATE'
base = project/'release/FPGA_GSV1_CAM1_OV3660_3_5_6_G1_OBSERVATION'
stable = project/'release/FPGA_GSV1_M3_06_3_5_5_TXDET1_CANDIDATE'
assert not dest.exists(), 'Never overwrite any release'
result = json.loads((run/'result.json').read_text(encoding='utf-8-sig'))
assert result['BuildPass'] and result['InputsUnchanged'] and result['ExistingConstraintsMet']
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
changed = []
for item in json.loads((run/'inputs.json').read_text(encoding='utf-8-sig')):
    p = run/item['RelativePath']
    assert sha(p).upper() == item['SnapshotSHA256']
    assert sha(Path(item['Source'])).upper() == item['SHA256']
    old = base/'source'/item['RelativePath']
    if not old.exists() or sha(p) != sha(old):
        changed.append(item['RelativePath'].replace('\\','/'))
assert set(changed) == {'rtl/capture/cam_ov3660_table.v','rtl/capture/cam_ov3660_config.v'}, changed
scope = json.loads((root/'reports/CAM1_357_scope.json').read_text(encoding='utf-8-sig'))
assert scope['PCLK_setting_unchanged'] and scope['geometry_guard_unchanged']
signature = (root/'reports/cam3660_sync_signature_tb.log').read_text()
assert 'PASS sync signature' in signature and 'FATAL' not in signature
assert 'pixels=4344 rows=1 errors=03' in signature
assert 'pixels=921600 rows=720 errors=00 good=2 bad=0' in signature
check = (root/'reports/cam_ov3660_config_357_tb.log').read_text()
assert 'PASS OV3660 production wire sequence' in check and 'FATAL' not in check
assert 'stale 23 refuses ready' in check
timing = (run/'report_timing/fpga_gsv1_top.rtr').read_text(errors='replace')
assert 'Design Summary : All Constraints Met.' in timing
sections = {}
for m in re.finditer(r'(?m)^(Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((Slow|Fast) Corner\):',timing):
    rows=[]
    pending=[]
    for line in timing[m.end():].split('====================================================================================================',1)[0].splitlines():
        r=re.match(r'\s*(.*?)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',line)
        if r:
            rows.append(dict(clocks=(' '.join(pending)+' '+r[1]).strip(),slack_ns=float(r[2]),
                             total_slack_ns=float(r[3]),failing_endpoints=int(r[4]),endpoints=int(r[5])))
            pending=[]
        elif line.strip() and not any(v in line for v in ['****','-----','Endpoints','Clock','TNS','THS','WPWS']):
            pending.append(line.strip())
    assert rows and all(r['slack_ns']>=0 and not r['failing_endpoints'] for r in rows)
    sections[f'{m[1]}_{m[2]}']=rows
assert len(sections)==10
prr=(run/'place_route/fpga_gsv1_top.prr').read_text(errors='replace')
row=next(l for l in prr.splitlines() if re.match(r'\| fpga_gsv1_top\s+\|',l))
cells=[s.strip() for s in row.split('|')][1:]
resources=dict(LUT=int(cells[1]),FF=int(cells[2]),DRM=float(cells[5]),PLL=int(cells[18]))
for name in ['CLMA','CLMS']:
    m=re.search(rf'\| Use of {name}\s+\|\s+(\d+)\s+\|\s+(\d+)',prr)
    assert m
    resources[name]=dict(used=int(m[1]),available=int(m[2]))
old=json.loads((base/'artifact.json').read_text(encoding='utf-8-sig'))
stable_art=json.loads((stable/'artifact.json').read_text(encoding='utf-8-sig'))
delta={k:resources[k]-old['resources'][k] for k in ['LUT','FF','DRM','PLL']}
delta.update({k:resources[k]['used']-old['resources'][k]['used'] for k in ['CLMA','CLMS']})
generated=datetime.fromisoformat(re.sub(r'(\.\d{6})\d+',r'\1',result['GeneratedTime']).replace('Z','+00:00'))
bit=dest/Path(result['Release']).name
summary=dict(version='3.5.7 CAM1 OV3660 sync candidate',classification='integrated_fix_candidate_pending_board',
    bitstream=str(bit),sha256=result['SHA256'].lower(),generated_utc=result['GeneratedTime'],
    generated_Asia_Shanghai=generated.astimezone(timezone(timedelta(hours=8))).isoformat(),
    build_pass=True,declared_constraints_met=True,source_snapshot_verified=True,
    resources=resources,resource_delta_vs_G1=delta,STA_summaries=sections,changed_vs_G1=changed,
    exact_change='final 4740=23->20 and mandatory readback; no PCLK/sampling/guard change',
    sensor_ID='3660',sensor_ID_board_verified=True,board_picture_verified=False,
    module_connector_pinout_confirmed=False,external_sensor_data_skew_measured=False,
    external_PHY_PVT_PCB_signed_off=False,protected_historical_tests_rerun=False,
    G1_actual={'records':9,'tag':'C1G1','configured':True,'pixels':4344,'rows':1,'errors':'03',
               'good_delta':0,'bad_delta':101,'first_bad':246,'last_bad':347,'window_approx_seconds':8},
    raw_capture='reports/OV3660_G1_actual_uart.txt',
    signature_model='four sync combinations; only both inverted reproduce 4344/1/03; normal 921600/720/00',
    physical_raw_sync_waveforms_measured=False,
    nominal_CAM1_frame_rate=36000000/(2172*1322),rollback_G1=old['bitstream'],rollback_G1_sha256=old['sha256'],
    rollback_stable_355=stable_art['bitstream'],rollback_stable_355_sha256=stable_art['sha256'],
    build_directory=str(run),programmed_by_agent=False)
dest.mkdir(parents=True)
for name in ['rtl','vendor','constraints','config']:
    shutil.copytree(run/name,dest/'source'/name)
shutil.copy2(run/'flow.tcl',dest/'source/flow.tcl')
for name in ['scripts','sim']:
    shutil.copytree(root/name,dest/'source'/name)
report_names=['CAM1_357_report.md','CAM1_357_scope.json','CAM1_357_vs_G1.diff',
    'OV3660_G1_actual_uart.txt','OV3660_G1_actual_decoded.json',
    'cam3660_sync_signature_tb.log','cam_ov3660_config_357_tb.log','ov3660_table_manifest.json',
    'ID1_actual_uart.txt','ID1_actual_decoded.json','OV3660_356_actual_uart.txt','OV3660_356_actual_decoded.json',
    'ov3660_dvp_page97.png','interface_audit.md','THIRD_PARTY_NOTICES.md']
(dest/'reports').mkdir()
for name in report_names:
    p=root/'reports'/name
    if not p.exists() and name=='THIRD_PARTY_NOTICES.md':
        p=root/'reports/sources'/name
    assert p.exists(),p
    shutil.copy2(p,dest/'reports'/name)
shutil.copytree(root/'reports/sources',dest/'reports/sources')
for name in ['result.json','inputs.json','pds_console.log']:
    shutil.copy2(run/name,dest/'reports'/name)
for name in ['report_timing/fpga_gsv1_top.rtr','place_route/fpga_gsv1_top.prr']:
    shutil.copy2(run/name,dest/'reports'/Path(name).name)
shutil.copy2(result['Release'],bit)
assert sha(bit)==summary['sha256']
(dest/'artifact.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
readme=(root/'reports/CAM1_357_report.md').read_text(encoding='utf-8')
readme+='\n## 本次实际构建产物\n\n'
readme+=f"唯一候选：{bit}\n\n生成时间（北京时间）：{summary['generated_Asia_Shanghai']}\n\nSHA256：{summary['sha256']}\n\n"
readme+=f"资源：{json.dumps(resources,ensure_ascii=False)}；与G1相比：{json.dumps(delta,ensure_ascii=False)}。\n\n"
for name,rows in sections.items():
    readme+=f"- {name}最小裕量：{min(r['slack_ns'] for r in rows):.3f}ns；失败端点0。\n"
readme+='\n这些是原约束下的最终PNR/STA；没有放宽约束。外部输入偏斜与PHY完整PVT/PCB签核未知项保持如上。构建通过不代表后摄实物画面通过。\n\n'
readme+=f"回退G1：{old['bitstream']}\n\nSHA256：{old['sha256']}\n\n"
readme+=f"已验收的3.5.5 TXDET1：{stable_art['bitstream']}\n\nSHA256：{stable_art['sha256']}\n\n原发布包均保留，3.5.5未适配新OV3660，不作为新后摄已修复版本。\n"
(dest/'README.md').write_text(readme,encoding='utf-8')
lines=[f'{sha(p)}  {p.relative_to(dest).as_posix()}' for p in sorted(dest.rglob('*')) if p.is_file()]
(dest/'SHA256SUMS.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(json.dumps({k:summary[k] for k in ['version','bitstream','sha256','generated_Asia_Shanghai','resources','resource_delta_vs_G1']},ensure_ascii=False,indent=2))
