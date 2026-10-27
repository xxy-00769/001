from pathlib import Path
import hashlib,json,os,subprocess,datetime,re
repo=Path.cwd(); out=Path('E:/zhoumian/FPGA/JF/checks')/('v5_2_output_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));out.mkdir()
bin=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin');os.environ['PATH']=str(bin)+os.pathsep+os.environ['PATH']
paths=[repo/'source/rtl/hdmi_ddr_ov5640_top.v',repo/'source/rtl/mpi7001_timing.v',repo/'tools/v5_display/timing_tb.sv',Path(__file__).resolve()]
manifest={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
s=paths[0].read_text(encoding='utf-8');a=s.index('     function [7:0] display_brighten;');b=s.index('////////////////////////////////////////////////////////////////////////////////////////////',a)
block=s[a:b]
fixture='''`timescale 1ns/1ps
module output_tb;
reg pix_clk=0; always #5 pix_clk=~pix_clk;
reg panel_image=0,show_capture_video=0,de_o=0;
reg panel_hs=0,panel_vs=0,panel_de=0;
reg [15:0] o_rgb565=0;
reg [7:0] r_out,g_out,b_out;
reg vs_out,hs_out,de_out;
'''+block+'''
integer i,k,r,g,b; integer er,eg,eb;
initial begin
for(k=0;k<8;k=k+1) begin
 for(i=0;i<65536;i=i+1) begin
  @(negedge pix_clk);
  {panel_image,show_capture_video,de_o}=k;
  o_rgb565=i; {panel_hs,panel_vs,panel_de}=i%8;
  r=((i>>11)&31)*255/31;
  g=((i>>5)&63)*255/63;
  b=(i&31)*255/31;
  // Bit replication reference, then uniform 9/8 saturation.
  r=(((i>>11)&31)<<3)|((i>>13)&7);
  g=(((i>>5)&63)<<2)|((i>>9)&3);
  b=((i&31)<<3)|((i>>2)&7);
  er=r+r/8; if(er>255) er=255;
  eg=g+g/8; if(eg>255) eg=255;
  eb=b+b/8; if(eb>255) eb=255;
  if(k!=7) begin er=0;eg=0;eb=0;end
  @(posedge pix_clk); #1;
  if(r_out!==er || g_out!==eg || b_out!==eb) $fatal(1,"RGB mismatch k=%0d rgb565=%h",k,o_rgb565);
  if({hs_out,vs_out,de_out}!=={panel_hs,panel_vs,panel_de}) $fatal(1,"Sync alignment changed");
 end
end
$display("OUTPUT_PASS rgb565_values=65536 gating_combinations=8 black_margins=1 gain=9/8 saturation=1 sync_latency_preserved=1");
$finish;
end
endmodule
'''
(out/'output_tb.sv').write_text(fixture,encoding='utf-8')
def run(args,log):
 with (out/log).open('wb') as f: subprocess.run([str(x) for x in args],cwd=out,stdout=f,stderr=subprocess.STDOUT,check=True)
for name,sources in [('output',[out/'output_tb.sv']),('timing',paths[1:3])]:
 run([bin/'iverilog.exe','-g2012','-s',name+'_tb','-o',name+'.vvp',*sources],name+'_compile.log')
 run([bin/'vvp.exe',name+'.vvp'],name+'.log')
 assert name.upper()+'_PASS' in (out/(name+'.log')).read_text()
unchanged=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in manifest.items())
result={'Verdict':'PASS','InputsUnchanged':unchanged,'Directory':str(out),'Scope':'Output RGB/gating/sync exhaustive RGB565; 3-frame panel timing and black margins','BoardVerified':False}
(out/'inputs.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');(out/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2))
assert unchanged
