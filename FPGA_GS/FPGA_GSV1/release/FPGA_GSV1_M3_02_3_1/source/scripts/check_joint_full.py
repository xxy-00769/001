from pathlib import Path
import os,sys,subprocess,datetime,hashlib,json,re
case='joint_full'
R=Path(__file__).resolve().parents[1]
OUT=R/'reports'/('sim_full_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
OUT.mkdir()
BIN=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin')
LIB=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
os.environ['PATH']=str(BIN)+os.pathsep+os.environ['PATH']
rtl=[R/'rtl/reuse'/f'{n}.v' for n in ['video_capture_status','frame_buffer_owner','fram_buf','wr_buf','rd_buf','wr_rd_ctrl_top','wr_cmd_trans','wr_ctrl','rd_ctrl']]
rtl+=[R/'rtl/capture/capture_pipe.v',R/'rtl/frame/dual_ddr_arbiter.v']
rtl += [R/'sim/line_ram_model.sv']
display_rtl=[R/'rtl/display/m1_view_select.v']
inputs=[R/'rtl/board/fpga_gsv1_top.v',R/'constraints/mes50hp.fdc',R/'flow.tcl']+display_rtl+rtl+list((R/'sim').glob('*sv'))+[R/'rtl/board/m1_keys.v',R/'rtl/reuse/mpi7001_timing.v',R/'rtl/display/m1_osd.v',R/'rtl/display/m1_view_select.v',Path(__file__),LIB/'GTP_GRS.v',LIB/'GTP_DRM18K.v']
manifest={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
# Icarus does not trigger vendor constant-CS always@* blocks at t=0.
# This mechanical compatibility change affects simulation copies only.
for k,p in enumerate(rtl):
    if p.name.startswith('ipml_'):
        t,n=re.subn(r'(integer\s+gen_cs[ab];\s*)always@\(\*\)',r'\1always_comb',p.read_text(encoding='utf-8'))
        assert n==2
        # Also evaluate the generated constant byte-enable/address muxes at
        # time zero. Otherwise Icarus leaves the very first 256-bit word X
        # until an address transition; later words are already correct.
        t=re.sub(r'always\s*@\s*\(\s*\*\s*\)', 'always_comb', t)
        copy=OUT/p.name; copy.write_text(t,encoding='utf-8'); rtl[k]=copy
def run(name,top,sources,marker,options=[]):
    for phase,args in [('compile',[BIN/'iverilog.exe','-g2012','-s',top,*options,'-y',LIB,'-Y','.v','-o',name+'.vvp',*sources]),('run',[BIN/'vvp.exe','-i',name+'.vvp'])]:
        log=OUT/(name+'_'+phase+'.log')
        with log.open('wb') as f:
            code=subprocess.run([str(a) for a in args],cwd=OUT,stdout=f,stderr=subprocess.STDOUT,timeout=1800).returncode
        if code: raise RuntimeError(str(log)+'\n'+log.read_text(errors='replace')[-2500:])
    t=(OUT/(name+'_run.log')).read_text()
    assert marker in t,t[-2000:]
    print(name+': '+t.strip().splitlines()[-2],flush=True)
result={'Verdict':'ERROR','Directory':str(OUT),'LineRAMModel':'4096x32 synchronous behavioral; vendor primitives covered separately','PhysicalDDRPHY':False,'BoardVerified':False,
        'RAMCompatibility':'behavioral synchronous 4096x32; actual generated RAM runs are separate'}
print(OUT,flush=True)
try:
    run('display_joint_720','display_joint_tb',rtl+display_rtl+[R/'sim/display_source.sv',R/'sim/display_joint_tb.sv'],'DISPLAY_JOINT_PASS',['-Pdisplay_joint_tb.HEIGHT=720','-Pdisplay_joint_tb.FRAMES=14','-Pdisplay_joint_tb.FIXED_FRONT=6','-Pdisplay_joint_tb.FIXED_REAR=4'])
    result['Verdict']='PASS'
except Exception as e: result['Error']=str(e)
result['InputsUnchanged']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in manifest.items())
result['Case']=case
(OUT/'inputs.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(OUT/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
sys.exit(0 if result['Verdict']=='PASS' and result['InputsUnchanged'] else 1)
