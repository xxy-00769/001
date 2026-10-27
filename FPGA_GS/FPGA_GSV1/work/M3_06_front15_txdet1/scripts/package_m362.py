"""Package the sole ARP-capture diagnostic; preserve actual STA failures."""
from pathlib import Path
import datetime,hashlib,json,re,shutil,sys,zipfile
R=Path(__file__).resolve().parents[1];ROOT=R.parents[1];B=Path(sys.argv[1]).resolve()
result=json.loads((B/'result.json').read_text(encoding='utf-8-sig'))
assert result['ExitCode']==0 and result['InputsUnchanged'],result
log=(B/'pds_console.log').read_text(errors='replace')
assert not re.search(r'^\s*E:|Program Error',log,re.M)
for x in json.loads((B/'inputs.json').read_text(encoding='utf-8-sig')):
 assert hashlib.sha256((R/x['RelativePath']).read_bytes()).hexdigest()==x['SnapshotSHA256'].lower(),x
checks=json.loads((R/'reports/m362_checks/result.json').read_text());assert all(checks['checks'].values())
for n,h in json.loads((R/'reports/m362_checks/inputs.json').read_text()).items():
 assert hashlib.sha256((R/n).read_bytes()).hexdigest()==h,n
audit=json.loads((R/'reports/baseline_scope.json').read_text());assert not audit['baseline_mismatches']
base=ROOT/'release/FPGA_GSV1_M3_06_3_5_1/source'
for n in ['m36_phy2.v','m36_rgmii_interface.v','m3_mac.v','m3_net_core.v','m3_upload.v']:
 assert (R/'rtl/network'/n).read_bytes()==(base/'rtl/network'/n).read_bytes(),n
for folder in ['rtl/board','rtl/capture','rtl/display','rtl/frame','rtl/reuse','vendor']:
 for p in (base/folder).rglob('*'):
  if p.is_file():assert p.read_bytes()==(R/p.relative_to(base)).read_bytes(),p
release=ROOT/'release/FPGA_GSV1_M3_06_3_5_2';assert not release.exists(),release
source=release/'source';evidence=release/'evidence';evidence.mkdir(parents=True)
for n in ['rtl','vendor','constraints','config','tools','docs','scripts','sim']:
 shutil.copytree(R/n,source/n,ignore=shutil.ignore_patterns('__pycache__','*.pyc','*.vvp'))
shutil.copy2(R/'flow.tcl',source/'flow.tcl');shutil.copy2(B/'build.pds',source/'FPGA_GSV1_M3_06_3_5_2.pds')
bit=release/'FPGA_GSV1_M3_06_3_5_2_NET2_ARP_CAPTURE_DIAG_HDMI_1080P60.sbit'
shutil.copy2(B/'generate_bitstream/fpga_gsv1_top.sbit',bit)
for n in ['baseline_scope.json','baseline_bit.json','port_comparison.json','orangepi_stats_delta.json','hardware351_decoded.json','baseline_tx_io_datasheet.log','tx_path_audit.json','expected_host_arp.json']:
 shutil.copy2(R/'reports'/n,evidence/n)
shutil.copy2(R/'net2_diag.txt',evidence/'net2_diag_351_original.txt')
shutil.copytree(R/'reports/m362_checks',evidence/'checks',ignore=shutil.ignore_patterns('*.vvp'))
for n in ['pds_console.log','result.json','inputs.json','report_timing/fpga_gsv1_top.rtr','device_map/fpga_gsv1_top_dmr.prt','device_map/fpga_gsv1_top.pcf','place_route/fpga_gsv1_top_prr.prt','place_route/clock_utilization.txt']:
 d=evidence/'build'/n;d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(B/n,d)
probe=R/'build/M3_06_3_5_2_20261022_145051_825'
for n in ['result.json','report_timing/fpga_gsv1_top.rtr']:
 d=evidence/'withdrawn_12mA_probe'/n;d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(probe/n,d)
def resource(label,first=False):
 v=re.findall(r'\|\s*'+re.escape(label)+r'\s*\|\s*([\d.]+)',log);assert v,label
 return float(v[0] if first else v[-1])
res={n:resource(l) for n,l in {'DRM':'Use of DRM','PLL':'Use of PLL','APM':'Use of APM','CLMA':'Use of CLMA','CLMS':'Use of CLMS'}.items()}
res.update(FF=resource('FF',True),MappedLUT=resource('LUT',True));res['CLBPercent']=100*(res['CLMA']+res['CLMS'])/10700
timing=(B/'report_timing/fpga_gsv1_top.rtr').read_text(errors='replace');slacks={}
for m in re.finditer(r'((?:Setup|Hold|Recovery|Removal) Summary\((?:Slow|Fast) Corner\):)(.*?)(?:={10,})',timing,re.S):
 v=re.findall(r'\s(-?\d+\.\d+)\s+-?\d+\.\d+\s+\d+\s+\d+\s*$',m[2],re.M)
 if v:slacks[m[1]]=min(map(float,v))
assert len(slacks)==8,slacks
rows=[l.strip() for l in timing.splitlines() if re.search(r'^\s*eth2_rxc\s+eth2_phy_tx_capture\s+',l)];assert len(rows)==4
stamp=datetime.datetime.fromtimestamp(bit.stat().st_mtime,datetime.timezone.utc)
record=dict(Version='M3-06 3.5.2 ARP capture DIAGNOSTIC ONLY',Bitstream=str(bit),SHA256=hashlib.sha256(bit.read_bytes()).hexdigest().upper(),GeneratedUTC=stamp.isoformat(),GeneratedShanghai=stamp.astimezone(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),Build=str(B),Resources=res,MinSlackNs=slacks,Port2CaptureRows=rows,SynthesisRouteBitstreamComplete=True,BuildPass=result['BuildPass'],STAAllConstraintsMet=result['ExistingConstraintsMet'],RecommendedFunctionalRelease=False,BoardVerified=False,PhysicalRootCauseConfirmed=False,NetworkClosedLoopRestored=False,TXPadDriveMilliamp=4,PHYRegistersOrPLLChanged=False,ProtocolOrEndpointsChanged=False)
(release/'release.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
report=(R/'docs/M3_06_3_5_2_status.md').read_text(encoding='utf-8')
report+='\n\n## 实际构建、资源、唯一诊断位流\n\n'
report+='综合/布局布线/位流生成已完成。输入冻结哈希一致。**是否全约束STA通过：'+str(record['STAAllConstraintsMet'])+'；BuildPass='+str(record['BuildPass'])+'。负裕量按失败保留，不能作为已签核修复版。**\n\n'
report+='资源相对3.5.1：FF '+str(res['FF'])+'（原20889）、映射LUT '+str(res['MappedLUT'])+'（原20027）、DRM '+str(res['DRM'])+'/134（原94）、CLB '+format(res['CLBPercent'],'.2f')+'%（原60.38%）、PLL '+str(res['PLL'])+'/5、APM '+str(res['APM'])+'。\n\n'
report+='最终STA最小裕量ns：\n```json\n'+json.dumps(slacks,indent=2)+'\n```\n\n'
report+='网口2TX窗口slow setup/hold、fast setup/hold原始行：\n```\n'+'\n'.join(rows)+'\n```\n\n'
report+='完整原报告：evidence/build/report_timing/fpga_gsv1_top.rtr。名义PHY模型不等于实际波形测量。旧发布包保持不变，未自动烧录。\n\n'
report+='唯一诊断候选、真实时间和SHA256：\n```json\n'+json.dumps(record,indent=2)+'\n```\n'
(release/'M3_06_3_5_2_delivery.md').write_text(report,encoding='utf-8');(ROOT/'reports/M3_06_3_5_2_delivery.md').write_text(report,encoding='utf-8')
readme='M3-06 3.5.2 ARP capture DIAGNOSTIC ONLY. Not a qualified functional repair. Read delivery report and release.json.\n'
(release/'README.md').write_text(readme);(source/'README.md').write_text(readme)
(release/'source_sha256.json').write_text(json.dumps({str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source.rglob('*')) if p.is_file()},indent=2))
archive=ROOT/'deliverables'/('FPGA_GSV1_M3_06_3_5_2_ARP_CAPTURE_DIAG_'+stamp.strftime('%Y%m%d_%H%M%S_UTC')+'.zip')
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in release.rglob('*'):
  if p.is_file():z.write(p,Path(release.name)/p.relative_to(release))
print(json.dumps(dict(**record,Archive=str(archive)),indent=2))
