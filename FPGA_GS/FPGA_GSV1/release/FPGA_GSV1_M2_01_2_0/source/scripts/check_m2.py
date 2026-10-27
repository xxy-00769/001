from pathlib import Path
import os, sys, subprocess, datetime, hashlib, json, argparse, re

parser=argparse.ArgumentParser()
parser.add_argument('--case',choices=['joint','reader','processing','control','hdmi','vendor','all'],default='all')
args=parser.parse_args()
R=Path(__file__).resolve().parents[1]
OUT=R/'reports'/('sim_m2_'+args.case+'_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
OUT.mkdir()
BIN=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin')
LIB=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
os.environ['PATH']=str(BIN)+os.pathsep+os.environ['PATH']
rtl=list((R/'rtl').rglob('*.v'))
inputs=list((R/'vendor').rglob('*.v'))+[R/'reports/M2_01_edid.bin']+rtl+list((R/'constraints').glob('*'))+[R/'flow.tcl',Path(__file__)]+list((R/'sim').glob('m2*'))
manifest={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
common=[R/'rtl/reuse'/f'{n}.v' for n in ['video_capture_status','frame_buffer_owner','fram_buf','wr_buf','rd_buf','wr_rd_ctrl_top','wr_cmd_trans','wr_ctrl','rd_ctrl']]
common += [R/'rtl/display/m2_rd_buf.v',R/'rtl/capture/capture_pipe.v',R/'rtl/frame/dual_ddr_arbiter.v']

def run(name,top,sources,marker,options=[]):
    for phase,command in [('compile',[BIN/'iverilog.exe','-g2012','-s',top,*options,'-y',LIB,'-Y','.v','-o',name+'.vvp',*sources]),('run',[BIN/'vvp.exe','-i',name+'.vvp'])]:
        with (OUT/(name+'_'+phase+'.log')).open('wb') as f:
            code=subprocess.run([str(x) for x in command],cwd=OUT,stdout=f,stderr=subprocess.STDOUT,timeout=1200).returncode
        if code: raise RuntimeError((OUT/(name+'_'+phase+'.log')).read_text(errors='replace')[-3000:])
    t=(OUT/(name+'_run.log')).read_text()
    assert marker in t,t[-2000:]
    print(name+': '+t.strip().splitlines()[-1],flush=True)

def vectors():
    # Python fixed-point oracle. Inputs include sharp independent window colors,
    # impulses and all 640 columns across both horizontal and vertical seams.
    count=0
    def pixel(x,y,q):
        source=(int(x>=320)+2*int(y>=180)) if q else 0
        return ((x*37+y*19+source*71)&255,(x*13+y*43+source*83)&255,(x*59+y*7+source*29)&255)
    with (OUT/'processing_vectors.txt').open('w') as f:
        for q in [0,1]:
            for mode in range(5):
                for y in range(186 if q else 6):
                    for x in range(640):
                        rgb=pixel(x,y,q);r,g,b=rgb
                        lum=(77*r+150*g+29*b+128)>>8
                        lx=x%320 if q else x;ly=y%180 if q else y
                        out=rgb
                        if mode==1:out=(lum,)*3
                        if mode==2 and lx>=2 and ly>=2:
                            out=tuple(sum(pixel(x-i,y-j,q)[c] for j in range(3) for i in range(3))//9 for c in range(3))
                        if mode==3:out=((255 if lum>=128 else 0),)*3
                        if mode==4:
                            cb=max(0,min(255,(32896-43*r-85*g+128*b)>>8))
                            cr=max(0,min(255,(32896+128*r-107*g-21*b)>>8))
                            w=320 if q else 640
                            out=((lum if lx<w//3 else cb if lx<(w*2)//3 else cr),)*3
                        color=(r<<16)|(g<<8)|b;expected=(out[0]<<16)|(out[1]<<8)|out[2]
                        f.write(f'{q} {mode} {x+80} {y+60} {color:06x} {expected:06x}\n');count+=1
                    f.write('0 0 0 0 000000 000000\n') # blank line clock
                    count+=1
    return count

print(OUT,flush=True)
result={'Case':'m2_'+args.case,'Verdict':'ERROR','Directory':str(OUT),'BoardVerified':False,'PhysicalDDRPHY':False}
try:
    if args.case in ['joint','all']:
        run('joint','m2_joint_tb',common+[R/'sim/line_ram_model.sv',R/'sim/m2_source.sv',R/'sim/m2_joint_tb.sv'],'M2_JOINT_PASS')
    if args.case in ['reader','all']:
        reader=[R/'rtl/reuse/mpi7001_timing.v',R/'rtl/reuse/rd_buf.v',R/'rtl/display/m2_rd_buf.v',R/'sim/line_ram_model.sv',R/'sim/m2_reader_tb.sv']
        run('reader_half_delayed','m2_reader_tb',reader,'M2_READER_PASS',['-Pm2_reader_tb.DELAY_NS=45000'])
        run('reader_quarter','m2_reader_tb',reader,'M2_READER_PASS',['-Pm2_reader_tb.QUARTER=1'])
        run('reader_legacy_delayed','m2_reader_tb',reader,'M2_READER_PASS',['-Pm2_reader_tb.LEGACY=1','-Pm2_reader_tb.DELAY_NS=45000'])
    if args.case in ['vendor','all']:
        vendor=[]
        for p in [R/'vendor/rd_fram_buf/rd_fram_buf.v',R/'vendor/rd_fram_buf/rtl/ipml_sdpram_v1_6_rd_fram_buf.v']:
            if p.name.startswith('ipml_'):
                copy=OUT/p.name
                copy.write_text(re.sub(r'always\s*@\s*\(\s*\*\s*\)', 'always_comb',p.read_text(encoding='utf-8')),encoding='utf-8')
                vendor.append(copy)
            else:vendor.append(p)
        run('vendor_quarter','m2_reader_tb',[R/'rtl/reuse/mpi7001_timing.v',R/'rtl/reuse/rd_buf.v',R/'rtl/display/m2_rd_buf.v',*vendor,R/'sim/m2_reader_tb.sv'],'M2_READER_PASS',['-Pm2_reader_tb.QUARTER=1'])
    if args.case in ['processing','all']:
        result['ReferenceSamples']=vectors()
        run('processing','m2_processing_tb',[R/'rtl/display/m2_processing.v',R/'sim/m2_processing_tb.sv'],'M2_PROCESSING_PASS')
    if args.case in ['control','all']:
        run('control','m2_control_tb',[R/'rtl/board/m2_keys.v',R/'rtl/display/m2_view_select.v',R/'rtl/display/m1_hint_cdc.v',R/'rtl/display/m2_osd.v',R/'rtl/display/m2_text.v',R/'sim/m2_control_tb.sv'],'M2_CONTROL_PASS')
        run('arbiter_edge','arbiter_edge_tb',[R/'rtl/frame/dual_ddr_arbiter.v',R/'sim/arbiter_edge_tb.sv'],'ARBITER_EDGE_PASS')
        run('owner','ownership_owner_tb',[R/'rtl/reuse/frame_buffer_owner.v',R/'sim/owner_tb.sv'],'OWNERSHIP_UNIT_RESULT')
    if args.case in ['hdmi','all']:
        edid=(R/'reports/M2_01_edid.bin').read_bytes()
        assert len(edid)==256 and sum(edid[:128])%256==0 and edid[126]==0
        assert edid[54:56]==bytes([1,29]) and edid[56]==0 and edid[58]>>4==5
        (OUT/'edid_expected.hex').write_text('\n'.join(f'{b:02x}' for b in edid)+'\n')
        run('rx_config','m2_rx_config_tb',[R/'rtl/reuse/ms7200_ctl.v',R/'sim/m2_rx_config_tb.sv'],'M2_RX_CONFIG_PASS')
        run('hdmi','m2_hdmi_tb',[R/'rtl/capture/hdmi_input.v',R/'sim/m2_hdmi_tb.sv'],'M2_HDMI_PASS')
    result['Verdict']='PASS'
except Exception as e:result['Error']=str(e)
result['InputsUnchanged']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in manifest.items())
(OUT/'inputs.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(OUT/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
sys.exit(0 if result['Verdict']=='PASS' and result['InputsUnchanged'] else 1)
