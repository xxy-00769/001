# -*- coding: utf-8 -*-
from pathlib import Path
import os,sys,subprocess,datetime,hashlib,json,argparse
p=argparse.ArgumentParser();p.add_argument('--case',choices=['full','backlog','rate','owner','epoch'],required=True);p.add_argument('--fps',type=int,default=30);p.add_argument('--frames',type=int,default=3);a=p.parse_args()
R=Path(__file__).resolve().parents[1];O=R/'reports'/('sim_m36_'+a.case+'_'+str(a.fps)+'_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));O.mkdir()
b=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin');lib=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation');os.environ['PATH']=str(b)+os.pathsep+os.environ['PATH']
if a.case=='epoch':
 src=['sim/m36_epoch_tb.sv','rtl/network/m3_network.v','rtl/network/m3_mac.v','rtl/network/m3_byte_ram.v','rtl/network/m3_net_core.v'];top='m36_epoch_tb';opts=[]
elif a.case=='owner':
 src=['sim/m36_owner_tb.sv','rtl/network/m3_right_store.v','rtl/display/m31_rd_buf.v','sim/m36_line_ram_model.sv']+['rtl/reuse/'+n+'.v' for n in ['wr_rd_ctrl_top','wr_cmd_trans','wr_ctrl','rd_ctrl']];top='m36_owner_tb';opts=[]
elif a.case in ('backlog','rate'):
 src=['sim/m36_backlog_tb.sv','rtl/network/m3_mac.v','rtl/network/m3_byte_ram.v','rtl/network/m3_net_core.v'];top='m36_'+a.case+'_tb';src[0]='sim/'+top+'.sv';opts=[] if a.case=='backlog' else ['-P'+top+'.FPS='+str(a.fps),'-P'+top+'.NET_FRAMES='+str(a.frames)]
else:
 src=['sim/m36_full_tb.sv','sim/m33_packet_model.sv','rtl/network/m3_mac.v','rtl/network/m3_net_core.v','rtl/network/m3_right_store.v','rtl/network/m3_upload.v','sim/m3_source.sv','sim/m36_line_ram_model.sv','sim/m32_text_model.sv','rtl/frame/m3_front_owner.v','rtl/frame/dual_ddr_arbiter.v','rtl/capture/capture_pipe.v']
 src+=['rtl/reuse/'+x+'.v' for x in ['video_capture_status','frame_buffer_owner','fram_buf','wr_buf','rd_buf','wr_rd_ctrl_top','wr_cmd_trans','wr_ctrl','rd_ctrl']]
 src+=['rtl/display/'+x+'.v' for x in ['m31_timing','m31_video_output','m31_rd_buf','m1_display_gain','m31_osd']]
 top='m36_full_tb';opts=['-P'+top+'.FPS='+str(a.fps),'-P'+top+'.NET_FRAMES='+str(a.frames)]
inputs={str(R/x):hashlib.sha256((R/x).read_bytes()).hexdigest() for x in src}
if a.case in ('full','rate'):
 original=(R/'rtl/network/m3_net_core.v').read_text();core,cache=original.split('module m33_packet_ram(',1)
 assert original.count('module m33_packet_ram(')==1
 # Exact production core, only DRM primitive wrapper substituted by the
 # synchronous contract separately tested in backlog with actual primitives.
 adapted=O/'core_with_packet_model.v'
 adapted.write_text(core+"""module m33_packet_ram(input clk,we,input [5:0] wa,ra,input [255:0] wd,output reg [255:0] rd);
 reg [255:0] mem[0:63];always @(posedge clk) begin if(we) mem[wa]<=wd;rd<=mem[ra];end
endmodule
""")
 src[src.index('rtl/network/m3_net_core.v')]=str(adapted)
 if a.case=='rate':src[src.index('rtl/network/m3_byte_ram.v')]='sim/m33_packet_model.sv';inputs[str(R/'sim/m33_packet_model.sv')]=hashlib.sha256((R/'sim/m33_packet_model.sv').read_bytes()).hexdigest()
result=dict(Verdict='ERROR',BoardMeasured=False,PhysicalDDRPHY=False,Case=a.case,OfferedFPS=a.fps,Frames=a.frames,ProcessingInPerfSimulation=False,ProductionBuildProcessing=True)
print(O,flush=True)
try:
 for phase,cmd in [('compile',[b/'iverilog.exe','-g2012','-s',top,*opts,'-y',lib,'-Y','.v','-o','run.vvp',*[R/x for x in src]]),('run',[b/'vvp.exe','-i','run.vvp'])]:
  with (O/(phase+'.log')).open('wb') as f: code=subprocess.run([str(x) for x in cmd],cwd=O,stdout=f,stderr=subprocess.STDOUT,timeout=7200).returncode
  if code:raise RuntimeError((O/(phase+'.log')).read_text(errors='replace')[-2500:])
 assert 'M36_'+a.case.upper()+'_PASS' in (O/'run.log').read_text()
 result['Verdict']='PASS'
except Exception as e:result['Error']=str(e)
result['InputsUnchanged']=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in inputs.items())
(O/'inputs.json').write_text(json.dumps(inputs,indent=2));(O/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2),flush=True)
sys.exit(0 if result['Verdict']=='PASS' and result['InputsUnchanged'] else 1)
