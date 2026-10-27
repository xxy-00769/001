from pathlib import Path
import re,os,sys,subprocess,datetime,hashlib,json,argparse
p=argparse.ArgumentParser();p.add_argument('--case',choices=['hint','format','display','processing','reader','osd','cdc','epoch','core'],required=True);a=p.parse_args()
R=Path(__file__).resolve().parents[1];O=R/'reports'/('sim_m32_'+a.case+'_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));O.mkdir()
BIN=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin');LIB=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
os.environ['PATH']=str(BIN)+os.pathsep+os.environ['PATH']
def run(top,src,marker):
    for phase,cmd in [('compile',[BIN/'iverilog.exe','-g2012','-s',top,'-y',LIB,'-Y','.v','-o','run.vvp',*[R/x for x in src]]),('run',[BIN/'vvp.exe','-i','run.vvp'])]:
        with (O/(phase+'.log')).open('wb') as f:c=subprocess.run([str(x) for x in cmd],cwd=O,stdout=f,stderr=subprocess.STDOUT,timeout=3600).returncode
        if c:raise RuntimeError((O/(phase+'.log')).read_text(errors='replace')[-2500:])
    assert marker in (O/'run.log').read_text()
sources=[];print(O,flush=True)
if a.case=='hint':
    sources=['sim/m32_hint_tb.sv','rtl/display/m1_hint_cdc.v']
elif a.case=='format':
    sources=['sim/m32_format_tb.sv','rtl/display/m31_pixel_pll.v','rtl/display/m31_timing.v',
      'rtl/display/m31_video_output.v','rtl/display/m31_processing.v','rtl/display/m31_filter_row.v',
      'rtl/display/m31_osd.v','sim/m32_text_model.sv','rtl/display/m1_display_gain.v',str(LIB/'GTP_PLL_E3.v')]
elif a.case=='display':
    # Long-run RAM model; physical 256->32 and 2048x24 DRM contracts are
    # separately validated with actual generated RAM/vendor primitives.
    sources=['sim/m32_display_tb.sv','rtl/display/m31_timing.v','rtl/display/m31_video_output.v','rtl/display/m31_rd_buf.v',
      'rtl/display/m31_processing.v','rtl/display/m31_osd.v','sim/m32_text_model.sv','rtl/display/m1_display_gain.v',
      'sim/line_ram_model.sv','sim/m32_filter_row_model.sv','rtl/frame/dual_ddr_arbiter.v']
    sources += ['rtl/reuse/'+x+'.v' for x in ['wr_rd_ctrl_top','wr_ctrl','rd_ctrl','wr_cmd_trans']]
elif a.case=='processing':
    sources=['sim/m32_processing_tb.sv','rtl/display/m31_processing.v','rtl/display/m31_filter_row.v']
    def pixel(x,y,q):
        source=(x//960+2*(y//540)) if q else 0
        return ((x*37+y*19+source*71)&255,(x*13+y*43+source*83)&255,(x*59+y*7+source*29)&255)
    with (O/'processing_vectors.txt').open('w') as f:
        for q in [0,1]:
            for mode in range(5):
                for y in (list(range(6))+list(range(540,546)) if q else list(range(180,186))):
                    for x in range(0 if q else 320,1920 if q else 1600):
                        rgb=pixel(x,y,q);r,g,b=rgb;lum=(77*r+150*g+29*b+128)>>8
                        lx=x%960 if q else x-320;ly=y%540 if q else y-180;out=rgb
                        if mode==1:out=(lum,)*3
                        if mode==2 and lx>=2 and ly>=2:
                            sums=[sum(pixel(x-dx,y-dy,q)[c] for dy in range(3) for dx in range(3)) for c in range(3)]
                            out=tuple((v*7282)>>16 for v in sums)
                        if mode==3:out=((255 if lum>=128 else 0),)*3
                        if mode==4:
                            cb=max(0,min(255,(32896-43*r-85*g+128*b)>>8));cr=max(0,min(255,(32896+128*r-107*g-21*b)>>8))
                            width=960 if q else 1280;v=lum if lx<width//3 else cb if lx<(width*2)//3 else cr;out=(v,)*3
                        value=lambda v:(v[0]<<16)|(v[1]<<8)|v[2]
                        f.write(f'{q} {mode} {x} {y} {value(rgb):06x} {value(out):06x}\n')
                    f.write(f'{q} {mode} -1 {y} 000000 000000\n')
elif a.case=='reader':
    sources=['sim/m32_reader_tb.sv','rtl/display/m31_rd_buf.v','vendor/rd_fram_buf/rd_fram_buf.v','vendor/rd_fram_buf/rtl/ipml_sdpram_v1_6_rd_fram_buf.v']
elif a.case=='core':
    sources=['sim/m32_core_tb.sv','rtl/network/m3_net_core.v']
elif a.case=='osd':
    sources=['sim/m32_osd_tb.sv','rtl/display/m31_osd.v','rtl/display/m31_text.v','rtl/display/m3_text.v','rtl/reuse/ms7210_ctl.v']
else:
    sources=['sim/m32_'+a.case+'_tb.sv','rtl/display/m31_rd_buf.v','sim/line_ram_model.sv']
inputs={str(R/x):hashlib.sha256((R/x).read_bytes()).hexdigest() for x in sources}
if a.case=='format':
    # Icarus interprets an IEEE floating cancellation of -8.88e-16ns in
    # the vendor model's phase subtraction as an enormous unsigned delay.
    # Clamp only this physically zero negative residual in a simulation copy;
    # all ratios, oscillator generation, lock and divider behavior stay vendor.
    original=LIB/'GTP_PLL_E3.v';adapted=O/original.name
    model=original.read_text()
    expression='clkout0_time - (((divider0 - phase0) * clkout0_time) / divider0)'
    assert expression in model
    model=model.replace(expression, f'(({expression}) < 0.0 && ({expression}) > -1e-9 ? 0.0 : ({expression}))')
    adapted.write_text(model);sources[-1]=str(adapted)
if a.case=='reader':
    original=R/sources[-1]; adapted=O/original.name
    adapted.write_text(re.sub(r'always\s*@\s*\(\s*\*\s*\)', 'always_comb',original.read_text(encoding='utf-8')),encoding='utf-8')
    sources[-1]=str(adapted)
result={'Case':a.case,'Verdict':'ERROR','BoardVerified':False}
try:
    run('m32_'+a.case+'_tb',sources,'M32_'+a.case.upper()+'_PASS');result['Verdict']='PASS'
except Exception as exc:result['Error']=str(exc)
result['InputsUnchanged']=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in inputs.items())
(O/'inputs.json').write_text(json.dumps(inputs,indent=2));(O/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
sys.exit(0 if result['Verdict']=='PASS' and result['InputsUnchanged'] else 1)
