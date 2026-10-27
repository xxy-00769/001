from pathlib import Path
import argparse, hashlib, json, shutil, datetime, re
P=argparse.ArgumentParser()
for k in ['build','full','regression','address']: P.add_argument('--'+k,required=True)
a=P.parse_args(); root=Path(__file__).resolve().parents[1]
def digest(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
build=Path(a.build); full=Path(a.full); regression=Path(a.regression)
b=read(build/'result.json'); f=read(full/'result.json'); g=read(regression/'result.json'); address=read(a.address)
assert b['BuildPass'] and b['ExistingConstraintsMet'] and b['InputsUnchanged']
assert b['Version'] in ['M2-02 2.1','M2-02 2.1B']
assert f['Case']=='m2_full' and f['Verdict']=='PASS' and f['InputsUnchanged']
assert g['Case']=='m2_regression' and g['Verdict']=='PASS' and g['InputsUnchanged']
assert address['Verdict']=='PASS'
assert 'FULL_RESULT_PENDING' not in (root/'reports/M2_02_delivery.md').read_text(encoding='utf-8')
# Both formal simulations and every build/source input must remain exact.
ignored=[]
for directory in [full,regression]:
 for name,h in read(directory/'inputs.json').items(): assert digest(name)==h.upper(),name
for item in read(build/'inputs.json'):
 assert digest(item['Source'])==item['SHA256'].upper(),item['Source']
 snapshot=build/item['RelativePath']
 if 'SnapshotSHA256' in item: assert digest(snapshot)==item['SnapshotSHA256'].upper()
 elif Path(item['RelativePath']).name=='fpga_gsv1_top.v': assert digest(snapshot)==item['SHA256'].upper()
for name,h in address['Inputs'].items(): assert digest(root/name)==h.upper()
assert digest(b['Release'])==b['SHA256'].upper()
suffix='M2_02_2_1B' if b['Version'].endswith('B') else 'M2_02_2_1'
dest=root/'release'/('FPGA_GSV1_'+suffix)
assert not dest.exists(),'Never overwrite a release'
dest.mkdir(); bit=dest/('FPGA_GSV1_'+suffix+'_RESTORE_VIDEO.sbit');shutil.copy2(b['Release'],bit)
for folder in ['report_timing','device_map','place_route']:
 ext={'report_timing':'.rtr','device_map':'.dmr','place_route':'.prr'}[folder]
 shutil.copy2(build/folder/('fpga_gsv1_top'+ext),dest/(folder+ext))
shutil.copy2(build/'inputs.json',dest/'build_inputs.json')
for label,directory in [('full',full),('regression',regression)]:
 evidence=dest/'verification'/label;evidence.mkdir(parents=True)
 for p in directory.iterdir():
  if p.suffix in ['.log','.json','.py']: shutil.copy2(p,evidence/p.name)
shutil.copy2(a.address,dest/'address_check.json')
variant=read(root/'reports/M2_02_variant_diff.json');assert variant['Verdict']=='PASS'
shutil.copy2(root/'reports/M2_02_variant_diff.json',dest/'variant_diff.json')
epoch=dest/'verification/epoch_before';epoch.mkdir()
for name in ['run.log','m2_rd_buf_before.v']:shutil.copy2(root/'reports/M2_02_epoch_before'/name,epoch/name)
cdc=dest/'verification/credit_cdc_before';cdc.mkdir()
for name in ['run.log','frame_run.log','m2_rd_buf_before.v']:shutil.copy2(root/'reports/M2_02_credit_cdc_before'/name,cdc/name)
before=sorted((root/'reports').glob('M2_02_full_before_cdc_*'))[-1]
assert read(before/'result.json')['ExpectedFailure'] and read(before/'result.json')['InputsUnchanged']
shutil.copytree(before,dest/'verification/full_before_cdc',ignore=shutil.ignore_patterns('*.vvp'))


for src,name in [('docs/M2_02_board_test.md','USER_TEST.md'),('docs/M2_02_changes.md','CHANGES.md'),('reports/M2_02_delivery.md','DELIVERY.md')]: shutil.copy2(root/src,dest/name)
src=dest/'source';src.mkdir()
for folder in ['rtl','vendor','constraints']: shutil.copytree(build/folder,src/folder)
project='FPGA_GSV1_M2_02_BYPASS.pds' if suffix.endswith('B') else 'FPGA_GSV1_M2_02.pds'
shutil.copy2(build/'build.pds',src/project)
# The working tree keeps PROCESSING_ENABLE=1. A root-level bypass PDS
# would accidentally elaborate that default; rebuild B from its own snapshot.
if not suffix.endswith('B'): shutil.copy2(build/'build.pds',root/project)
shutil.copy2(build/'flow.tcl',src/'flow.tcl')
for folder in ['scripts','sim']: shutil.copytree(root/folder,src/folder)
(src/'reports').mkdir();(src/'docs').mkdir()
shutil.copy2(root/'reports/M2_01_edid.bin',src/'reports/M2_01_edid.bin')
for name in ['M2_02_board_test.md','M2_02_changes.md']:shutil.copy2(root/'docs'/name,src/'docs'/name)
time_text=re.sub(r'(\.\d{6})\d+(?=Z|[+-])',r'\1',b['GeneratedTime'])
instant=datetime.datetime.fromisoformat(time_text.replace('Z','+00:00'))
r={'Version':b['Version'],'Bitstream':str(bit.resolve()),'SHA256':b['SHA256'],
 'GeneratedUtc':instant.isoformat(),'GeneratedShanghai':instant.astimezone(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
 'Build':str(build.resolve()),'FullSimulation':str(full.resolve()),'Regression':str(regression.resolve()),
 'BuildPass':True,'SimulationPass':True,'ConsumedInputsUnchanged':True,'UnusedManifestDifferences':ignored,
 'ProcessingEnable':not suffix.endswith('B'),'Programmed':False,'BoardVerified':False,'ExternalIoTimingSignoff':False}
(dest/'release.json').write_text(json.dumps(r,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(r,indent=2,ensure_ascii=False))
