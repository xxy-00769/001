"""Only port2 production TX regression; unchanged video/algorithms are not run."""
from pathlib import Path
import hashlib,json,os,subprocess,sys
R=Path(__file__).resolve().parents[1]
V=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin')
L=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
os.environ['PATH']=str(V)+os.pathsep+os.environ['PATH']
src=['sim/m363_tx_tb.sv','sim/m363_burst_tb.sv']+['rtl/network/'+n+'.v' for n in ['m3_network','m36_phy2','m36_rgmii_interface','m361_diag','m3_mac','m3_byte_ram','m3_net_core','m3_upload']]
# Existing one-clock 256/32 staging model; MAC TX RAM and serializer remain production.
src+=['sim/m36_line_ram_model.sv']
O=R/'reports/m363_checks';O.mkdir(exist_ok=True)
hashes={p:hashlib.sha256((R/p).read_bytes()).hexdigest() for p in src+['sim/m361_phy_model.vh']}
c=subprocess.run([str(V/'iverilog.exe'),'-g2012','-s','m363_tx_tb','-y',str(L),'-Y','.v','-I','vendor/rd_fram_buf/rtl','-o',str(O/'tx.vvp'),*src],cwd=R,capture_output=True,text=True)
(O/'compile.log').write_text(c.stdout+c.stderr)
if c.returncode:raise RuntimeError(c.stderr)
t=subprocess.run([str(V/'vvp.exe'),str(O/'tx.vvp')],cwd=R,capture_output=True,text=True,timeout=90)
(O/'tx.log').write_text(t.stdout+t.stderr);print(t.stdout+t.stderr)
ok=t.returncode==0 and 'M363_LOAD_PASS' in t.stdout and 'M363_TX_PASS' in t.stdout
bc=subprocess.run([str(V/'iverilog.exe'),'-g2012','-s','m363_burst_tb','-y',str(L),'-Y','.v','-I','vendor/rd_fram_buf/rtl','-o',str(O/'burst.vvp'),*src],cwd=R,capture_output=True,text=True)
(O/'burst_compile.log').write_text(bc.stdout+bc.stderr)
if bc.returncode:raise RuntimeError(bc.stderr)
bt=subprocess.run([str(V/'vvp.exe'),str(O/'burst.vvp')],cwd=R,capture_output=True,text=True,timeout=90)
(O/'burst.log').write_text(bt.stdout+bt.stderr);print(bt.stdout+bt.stderr)
ok=ok and bt.returncode==0 and 'M363_BURST_PASS' in bt.stdout
unchanged=all(hashlib.sha256((R/p).read_bytes()).hexdigest()==h for p,h in hashes.items())
(O/'inputs.json').write_text(json.dumps(hashes,indent=2))
(O/'result.json').write_text(json.dumps(dict(ProductionTX=ok,InputsUnchanged=unchanged,BoardVerified=False,ElectricalTimingBySimulation=False),indent=2))
sys.exit(0 if ok and unchanged else 1)
