from pathlib import Path
import subprocess,datetime,json,hashlib,os,re
D=Path(__file__).resolve().parents[2]
R=D.parent/'tmp'/'v5_display_sim'/datetime.datetime.now().strftime('%Y%m%d_%H%M%S'); R.mkdir(parents=True)
BIN=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin')
os.environ['PATH']=str(BIN)+os.pathsep+os.environ['PATH']
LIB=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
def run(args,log):
 with (R/log).open('wb') as f:
  p=subprocess.run([str(x) for x in args],cwd=R,stdout=f,stderr=subprocess.STDOUT)
 out=(R/log).read_bytes()
 if p.returncode: raise RuntimeError(f'{log}: {out[-2000:]!r}')
 return out.decode(errors='replace')
tb=(D/'tools/frame_ownership/full_frame_tb.sv').read_text(encoding='utf-8')
tb=tb.replace('fram_buf dut (','fram_buf #(.DISPLAY_HALF(1)) dut (')
start=tb.index('    img_proc #(')
end=tb.index('    reg out_vs=',start)
tb=tb[:start]+'''    // Test boundary: known source pixels into the production frame buffer.
    // Unchanged image algorithms are not part of this display-only regression.
    reg [1:0] vs_pipe=0, de_pipe=0;
    reg [15:0] rgb_pipe0=0, rgb_pipe1=0;
    reg source_vs_d=0;
    reg [31:0] tagged_id=0, tagged_time=0;
    always @(posedge video_clk) begin
        if (!pipeline_running) begin
            vs_pipe<=0; de_pipe<=0; rgb_pipe0<=0; rgb_pipe1<=0;
            source_vs_d<=0; tagged_id<=0; tagged_time<=0;
        end else begin
            vs_pipe<={vs_pipe[0],vs}; de_pipe<={de_pipe[0],de};
            source_vs_d<=vs;
            if (vs && !source_vs_d) begin tagged_id<=open_id; tagged_time<=open_time; end
            rgb_pipe0<=rgb; rgb_pipe1<=rgb_pipe0;
        end
    end
    assign raw_clean_vs=vs_pipe[1], display_vs=vs_pipe[1];
    assign raw_clean_de=de_pipe[1], display_de=de_pipe[1];
    assign raw_clean_rgb=rgb_pipe1, display_rgb=rgb_pipe1;
    assign raw_clean_id=tagged_id, display_id=tagged_id;
    assign raw_clean_time=tagged_time, display_time=tagged_time;
''' +tb[end:]
tb=tb.replace('always #13.1 out_clk','always #16.9230769 out_clk')
tb=tb.replace('pattern(output_tag,rows,columns)','pattern(output_tag,rows*2,columns*2)')
tb=tb.replace('if(columns!=W)','if(columns!=W/2)')
tb=tb.replace('columns=0; rows=rows+1;', '$fflush(row_file); columns=0; rows=rows+1;')
tb=tb.replace('repeat(200) @(negedge video_clk);\n        end\n    endtask', 'repeat(200) @(negedge video_clk);\n            $display("SOURCE_CAPTURE tag=%0d published=%0d",tag,dut.published_count); $fflush();\n        end\n    endtask')
a=tb.index('    task display_frame('); b=tb.index('    initial begin\n        row_file=',a)
part=tb[a:b].replace('y<H;','y<H/2;').replace('x<W;','x<W/2;').replace('pixels!=W*H || rows!=H','pixels!=W*H/4 || rows!=H/2').replace('reads-old_reads!=57600','reads-old_reads!=28800').replace('last_row_pixels=1280','last_row_pixels=640')
tb=tb[:a]+part+tb[b:]
tb=tb.replace('repeat(W) begin','repeat(W/2) begin').replace('black_pixels!=2560','black_pixels!=1280').replace('frames*W*H,','frames*W*H/4,')
start=tb.index('        // No output boundary:')
end=tb.index('        // A read extends',start)
tb=tb[:start]+'        display_frame(0);\n        display_frame(0);\n'+tb[end:]
tb=tb.replace('dut.display_id!=4','dut.display_id!=0').replace('display_frame(4);','display_frame(0);')
(R/'half_frame_tb.sv').write_text(tb,encoding='utf-8')
rtl=['video_capture_status.v','frame_buffer_owner.v','fram_buf.v','wr_buf.v','rd_buf.v','wr_rd_ctrl_top.v','wr_cmd_trans.v','wr_ctrl.v','rd_ctrl.v','wr_fram_buf/wr_fram_buf.v','wr_fram_buf/rtl/ipml_sdpram_v1_6_wr_fram_buf.v','rd_fram_buf/rd_fram_buf.v','rd_fram_buf/rtl/ipml_sdpram_v1_6_rd_fram_buf.v']
sources=[D/'source/rtl'/x for x in rtl]
manifest={str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in sources}
simulation_sources=[]
for path in sources:
 if path.name.startswith('ipml_sdpram_'):
  text=path.read_text(encoding='utf-8')
  compatible,n=re.subn(r'(integer\s+gen_cs[ab];\s*)always@\(\*\)',r'\1always_comb',text)
  assert n==2
  copy=R/path.name; copy.write_text(compatible,encoding='utf-8')
  simulation_sources.append(copy)
 else: simulation_sources.append(path)
(R/'inputs.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
result={'Verdict':'ERROR','BoardTest':False,'PhysicalDDRPHY':False,'Directory':str(R),
 'Boundary':'720p known source -> production frame buffer -> half-size display reader',
 'RAMCompatibility':'simulation copies only: two constant chip-select always blocks per wrapper use always_comb; original GTP_DRM18K unchanged',
 'Scenarios':'one 720p capture, three full half-size displays, repeat, read fault blacking and recovery; no image algorithm regression'}
print(R,flush=True)
try:
 run([BIN/'iverilog.exe','-g2012','-s','timing_tb','-o','timing.vvp',D/'source/rtl/mpi7001_timing.v',D/'tools/v5_display/timing_tb.sv'],'timing_compile.log')
 text=run([BIN/'vvp.exe','timing.vvp'],'timing.log'); assert 'TIMING_PASS' in text
 run([BIN/'iverilog.exe','-g2012','-s','ownership_full_frame_tb','-Pownership_full_frame_tb.DISPLAY_PATH=1','-y',LIB,'-Y','.v','-o','frame.vvp',*simulation_sources,R/'half_frame_tb.sv'],'frame_compile.log')
 text=run([BIN/'vvp.exe','frame.vvp'],'frame.log'); assert 'OWNERSHIP_FULL_RESULT' in text
 result['Verdict']='PASS'; result['Summary']=text[-1600:]
except Exception as e: result['Error']=str(e)
result['InputsUnchanged']=all(hashlib.sha256(Path(x).read_bytes()).hexdigest()==h for x,h in manifest.items())
(R/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
if result['Verdict']!='PASS': raise SystemExit(1)
