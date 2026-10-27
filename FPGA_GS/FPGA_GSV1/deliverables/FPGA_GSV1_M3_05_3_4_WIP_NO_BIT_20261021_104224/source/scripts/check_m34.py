from pathlib import Path
import argparse,datetime,subprocess,os,json,hashlib,sys
p=argparse.ArgumentParser();p.add_argument('--case',choices=['camera','hdmi','status'],required=True);a=p.parse_args()
R=Path(__file__).resolve().parents[1];O=R/'reports'/('sim_m34_'+a.case+'_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));O.mkdir()
b=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin');lib=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
os.environ['PATH']=str(b)+os.pathsep+os.environ['PATH']
src={'camera':['sim/m34_camera_tb.sv','rtl/reuse/cmos_8_16bit.v','rtl/capture/hdmi_input.v'],
     'hdmi':['sim/m34_hdmi_tb.sv','rtl/capture/hdmi_input.v','rtl/reuse/video_capture_status.v','rtl/capture/capture_pipe.v'],
     'status':['sim/m34_status_tb.sv','rtl/capture/hdmi_input.v','rtl/display/m31_osd.v','sim/m32_text_model.sv']}[a.case]
inputs={str(R/f):hashlib.sha256((R/f).read_bytes()).hexdigest() for f in src}
q=dict(Verdict='ERROR',Case=a.case,BoardMeasured=False);print(O,flush=True)
try:
 for phase,cmd in [('compile',[b/'iverilog.exe','-g2012','-s','m34_'+a.case+'_tb','-y',lib,'-Y','.v','-o','run.vvp',*[R/f for f in src]]),('run',[b/'vvp.exe','-i','run.vvp'])]:
  with (O/(phase+'.log')).open('wb') as f:c=subprocess.run([str(x) for x in cmd],cwd=O,stdout=f,stderr=subprocess.STDOUT,timeout=900).returncode
  assert c==0,(O/(phase+'.log')).read_text(errors='replace')[-1500:]
 assert 'M34_'+a.case.upper()+'_PASS' in (O/'run.log').read_text()
 q['Verdict']='PASS'
except Exception as e:q['Error']=str(e)
q['InputsUnchanged']=all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in inputs.items())
(O/'inputs.json').write_text(json.dumps(inputs,indent=2));(O/'result.json').write_text(json.dumps(q,indent=2));print(json.dumps(q,indent=2),flush=True)
sys.exit(0 if q['Verdict']=='PASS' and q['InputsUnchanged'] else 1)
