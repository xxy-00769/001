from pathlib import Path
import subprocess,os,hashlib,json
r=Path(__file__).resolve().parents[1]
t=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin')
lib=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
os.environ['PATH']=str(t)+os.pathsep+os.environ['PATH']
src=list((r/'rtl').glob('*.v'))+[r/'sim/baseline_tb.sv']
cmd=[str(t/'iverilog.exe'),'-g2012','-s','baseline_tb','-y',str(lib),'-Y','.v','-o',str(r/'reports/baseline.vvp'),*[str(p) for p in src]]
c=subprocess.run(cmd,cwd=r,capture_output=True,text=True)
(r/'reports/sim_compile.log').write_text(c.stdout+c.stderr)
if c.returncode:raise RuntimeError(c.stderr)
v=subprocess.run([str(t/'vvp.exe'),str(r/'reports/baseline.vvp')],cwd=r,capture_output=True,text=True,timeout=30)
(r/'reports/sim.log').write_text(v.stdout+v.stderr)
print(v.stdout+v.stderr)
if v.returncode or 'E1_PIN_PASS' not in v.stdout:raise RuntimeError('pin path verification failed')
(r/'reports/sim_inputs.json').write_text(json.dumps({str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in src},indent=2))
