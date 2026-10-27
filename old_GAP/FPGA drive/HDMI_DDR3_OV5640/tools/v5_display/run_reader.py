from pathlib import Path
import subprocess,datetime,json,hashlib,os,re
D=Path(__file__).resolve().parents[2]
R=Path('E:/zhoumian/FPGA/JF/checks')/('v5_1_display_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S')); R.mkdir(parents=True)
BIN=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin'); os.environ['PATH']=str(BIN)+os.pathsep+os.environ['PATH']
LIB=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
src=[D/'source/rtl'/x for x in ['mpi7001_timing.v','rd_buf.v','rd_fram_buf/rd_fram_buf.v','rd_fram_buf/rtl/ipml_sdpram_v1_6_rd_fram_buf.v']]
pll_sources=[D/'source/rtl/pll_mpi7001.v',D/'tools/v5_display/pll_tb.sv']
inputs=src+[D/'tools/v5_display/reader_tb.sv',D/'tools/v5_display/timing_tb.sv',Path(__file__),LIB/'GTP_GRS.v',LIB/'GTP_DRM18K.v',LIB/'GTP_PLL_E3.v']+pll_sources
manifest={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
text=src[-1].read_text(encoding='utf-8'); text,n=re.subn(r'(integer\s+gen_cs[ab];\s*)always@\(\*\)',r'\1always_comb',text); assert n==2
compat=R/src[-1].name; compat.write_text(text,encoding='utf-8')
def run(args,log):
 with (R/log).open('wb') as f: code=subprocess.run([str(x) for x in args],cwd=R,stdout=f,stderr=subprocess.STDOUT).returncode
 if code: raise RuntimeError(log+': '+(R/log).read_text(errors='replace')[-2500:])
print(R,flush=True)
result={'Verdict':'ERROR','BoardTest':False,'PhysicalDDRPHY':False,'Directory':str(R),
 'Boundary':'Display timing and production rd_buf with native read-data BFM, original generated read RAM with constant-CS simulation compatibility, original DRM primitive',
 'Excluded':'Writer, ownership, image algorithms, physical DDR/HDMI/monitor',
 'Compatibility':'simulation copy only: CSA and CSB always @(*) -> always_comb; original production IP unchanged'}
try:
 for name,sources,marker in [('timing',[src[0],D/'tools/v5_display/timing_tb.sv'],'TIMING_PASS'),('pll',pll_sources,'PLL_PASS'),('reader',src[:-1]+[compat,D/'tools/v5_display/reader_tb.sv'],'READER_PASS')]:
  run([BIN/'iverilog.exe','-g2012','-s',name+'_tb','-y',LIB,'-Y','.v','-o',name+'.vvp',*sources],name+'_compile.log')
  run([BIN/'vvp.exe',name+'.vvp'],name+'.log')
  assert marker in (R/(name+'.log')).read_text()
 result['Verdict']='PASS'
except Exception as e: result['Error']=str(e)
result['InputsUnchanged']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in manifest.items())
(R/'inputs.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(R/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
if result['Verdict']!='PASS': raise SystemExit(1)
