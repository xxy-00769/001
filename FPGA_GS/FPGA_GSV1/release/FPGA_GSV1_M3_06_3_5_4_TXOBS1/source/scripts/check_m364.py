"""Changed production network path only; no unchanged video/algorithm tests."""
from pathlib import Path
import hashlib,json,os,subprocess,sys
R=Path(__file__).resolve().parents[1]
V=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin')
L=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
os.environ['PATH']=str(V)+os.pathsep+os.environ['PATH']
src=['sim/m364_tx_tb.sv','sim/m364_burst_tb.sv','sim/m364_clock_model.sv']+['rtl/network/'+n+'.v' for n in ['m3_network','m36_phy2','m364_e1_rgmii','m3_mac','m3_byte_ram','m3_net_core','m3_upload']]
src+=['sim/m36_line_ram_model.sv','rtl/network/m361_diag.v','rtl/network/m365_tx_observer.v']
O=R/'reports/m364_checks';O.mkdir(exist_ok=True)
hashes={p:hashlib.sha256((R/p).read_bytes()).hexdigest() for p in src+['sim/m361_phy_model.vh']}
checks={}
for name in ['tx','burst']:
    top='m364_'+name+'_tb'
    c=subprocess.run([str(V/'iverilog.exe'),'-g2012','-s',top,'-y',str(L),'-Y','.v','-I','vendor/rd_fram_buf/rtl','-o',str(O/(name+'.vvp')),*src],cwd=R,capture_output=True,text=True)
    (O/(name+'_compile.log')).write_text(c.stdout+c.stderr)
    if c.returncode:raise RuntimeError(c.stderr)
    t=subprocess.run([str(V/'vvp.exe'),str(O/(name+'.vvp'))],cwd=R,capture_output=True,text=True,timeout=90)
    (O/(name+'.log')).write_text(t.stdout+t.stderr);print(t.stdout+t.stderr)
    checks[name]=t.returncode==0 and ('M364_TX_PASS' if name=='tx' else 'M364_BURST_PASS') in t.stdout
unchanged=all(hashlib.sha256((R/p).read_bytes()).hexdigest()==h for p,h in hashes.items())
(O/'inputs.json').write_text(json.dumps(hashes,indent=2))
(O/'result.json').write_text(json.dumps(dict(checks=checks,InputsUnchanged=unchanged,BoardVerified=False,ElectricalTimingBySimulation=False),indent=2))
sys.exit(0 if all(checks.values()) and unchanged else 1)
