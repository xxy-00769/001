"""Only changed port2 bring-up and passive serial checks; no video regression."""
from pathlib import Path
import os,subprocess,json,hashlib,sys
R=Path(__file__).resolve().parents[1]
B=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin');L=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
os.environ['PATH']=str(B)+os.pathsep+os.environ['PATH']
common=['rtl/network/'+n+'.v' for n in ['m3_network','m36_phy2','m36_rgmii_interface','m361_diag','m3_mac','m3_byte_ram','m3_net_core','m3_upload']]
common+=['vendor/rd_fram_buf/rd_fram_buf.v','vendor/rd_fram_buf/rtl/ipml_sdpram_v1_6_rd_fram_buf.v']
O=R/'reports/m361_checks';O.mkdir(exist_ok=True)
inputs=set(common+['sim/m361_link_tb.sv','sim/m361_phy_model.vh','sim/m361_diag_tb.sv'])
hashes={p:hashlib.sha256((R/p).read_bytes()).hexdigest() for p in inputs}
results={}
for name,src in [('link',['sim/m361_link_tb.sv']+common),('diag',['sim/m361_diag_tb.sv','rtl/network/m361_diag.v'])]:
    top='m361_'+name+'_tb';out=O/(name+'.vvp')
    c=subprocess.run([str(B/'iverilog.exe'),'-g2012','-s',top,'-y',str(L),'-Y','.v','-I','vendor/rd_fram_buf/rtl','-o',str(out),*src],cwd=R,capture_output=True,text=True)
    (O/(name+'_compile.log')).write_text(c.stdout+c.stderr)
    if c.returncode:raise RuntimeError(c.stderr)
    run=subprocess.run([str(B/'vvp.exe'),str(out)],cwd=R,capture_output=True,text=True,timeout=60)
    (O/(name+'.log')).write_text(run.stdout+run.stderr)
    results[name]=run.returncode==0 and 'M361_'+name.upper()+'_PASS' in run.stdout
    print(run.stdout,end='')
results['InputsUnchanged']=all(hashlib.sha256((R/p).read_bytes()).hexdigest()==h for p,h in hashes.items())
(O/'inputs.json').write_text(json.dumps(hashes,indent=2))
(O/'result.json').write_text(json.dumps(dict(checks=results,BoardVerified=False,PhysicalPHY=False,PadDelayModeled=False),indent=2))
sys.exit(0 if all(results.values()) else 1)
