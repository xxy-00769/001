from pathlib import Path
import os, sys, subprocess, datetime, hashlib, json, argparse, importlib.util
P=argparse.ArgumentParser();P.add_argument('--case',choices=['unit','full','m2'],default='unit');a=P.parse_args()
R=Path(__file__).resolve().parents[1];O=R/'reports'/('sim_m3_'+a.case+'_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));O.mkdir()
BIN=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin');LIB=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
os.environ['PATH']=str(BIN)+os.pathsep+os.environ['PATH']
inputs=list((R/'rtl').rglob('*.v'))+list((R/'sim').glob('m3*'))+list((R/'tools/m3').glob('*.py'))+list((R/'constraints').glob('*'))+[R/'flow.tcl',Path(__file__)]
manifest={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
def run(n,top,sources,marker,opts=[]):
 for phase,cmd in [('compile',[BIN/'iverilog.exe','-g2012','-s',top,*opts,'-y',LIB,'-Y','.v','-o',n+'.vvp',*[str(R/x) for x in sources]]),('run',[BIN/'vvp.exe','-i',n+'.vvp'])]:
  with (O/(n+'_'+phase+'.log')).open('wb') as f:c=subprocess.run([str(x) for x in cmd],cwd=O,stdout=f,stderr=subprocess.STDOUT,timeout=3600).returncode
  if c:raise RuntimeError((O/(n+'_'+phase+'.log')).read_text(errors='replace')[-3000:])
 log=(O/(n+'_run.log')).read_text();assert marker in log,log[-2000:];print(n+': '+log.strip().splitlines()[-2],flush=True)
print(O,flush=True);result={'Case':'m3_'+a.case,'Verdict':'ERROR','BoardVerified':False,'PhysicalDDRPHY':False}
try:
 if a.case=='unit':
  run('ram_mac','m3_mac_tb',['rtl/network/m3_byte_ram.v','rtl/network/m3_mac.v','sim/m3_mac_tb.sv'],'M3_MAC_PASS')
  run('owner','m3_owner_tb',['rtl/frame/m3_front_owner.v','sim/m3_owner_tb.sv'],'M3_OWNER_PASS')
  run('core','m3_core_tb',['rtl/network/m3_net_core.v','sim/m3_core_tb.sv'],'M3_CORE_PASS')
  run('upload','m3_upload_tb',['rtl/network/m3_upload.v','sim/line_ram_model.sv','sim/m3_upload_tb.sv'],'M3_UPLOAD_PASS')
  run('control','m3_control_tb',['rtl/board/m3_keys.v','rtl/display/m3_view_select.v','rtl/display/m1_hint_cdc.v','rtl/display/m3_osd.v','rtl/display/m3_text.v','sim/m3_control_tb.sv'],'M3_CONTROL_PASS')
  run('right_owner','m3_right_owner_tb',['rtl/network/m3_right_store.v','rtl/display/m2_rd_buf.v','rtl/reuse/wr_rd_ctrl_top.v','rtl/reuse/wr_cmd_trans.v','rtl/reuse/wr_ctrl.v','rtl/reuse/rd_ctrl.v','sim/line_ram_model.sv','sim/m3_right_owner_tb.sv'],'M3_RIGHT_OWNER_PASS')
  c=subprocess.run([sys.executable,'-X','utf8',str(R/'tools/m3/test_protocol.py')],capture_output=True,text=True)
  (O/'host.log').write_text(c.stdout+c.stderr,encoding='utf-8');assert c.returncode==0,c.stdout+c.stderr
 elif a.case=='full':
  common=['rtl/reuse/'+x+'.v' for x in ['video_capture_status','frame_buffer_owner','fram_buf','wr_buf','rd_buf','wr_rd_ctrl_top','wr_cmd_trans','wr_ctrl','rd_ctrl','mpi7001_timing']]
  display=['rtl/display/'+x+'.v' for x in ['m2_rd_buf','m3_video_output','m1_display_gain','m2_processing','m3_osd']]+['sim/m3_text_model.sv']
  run('full','m3_full_tb',common+display+['rtl/frame/m3_front_owner.v','rtl/frame/dual_ddr_arbiter.v','rtl/capture/capture_pipe.v','rtl/network/m3_net_core.v','rtl/network/m3_right_store.v','rtl/network/m3_upload.v','sim/line_ram_model.sv','sim/m2_filter_row_model.sv','sim/m3_source.sv','sim/m3_full_tb.sv'],'M3_FULL_PASS')
 elif a.case=='m2':
  run('cdc','m2_credit_cdc_tb',['rtl/display/m2_rd_buf.v','sim/line_ram_model.sv','sim/m2_credit_cdc_tb.sv'],'M2_CREDIT_CDC_PASS')
  run('epoch','m2_epoch_tb',['rtl/display/m2_rd_buf.v','sim/line_ram_model.sv','sim/m2_epoch_tb.sv'],'M2_EPOCH_PASS')
 result['Verdict']='PASS'
except Exception as e:result['Error']=str(e)
result['InputsUnchanged']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in manifest.items())
(O/'inputs.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');(O/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2));sys.exit(0 if result['Verdict']=='PASS' and result['InputsUnchanged'] else 1)
