"""Reproduce only the M3-06 PHY, RGMII and role tests on demand."""
from pathlib import Path
import argparse, os, subprocess, sys
R=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--case', choices=['phy','rgmii','roles'],required=True)
a=p.parse_args()
b=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin')
lib=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
src={'phy':['sim/m36_phy2_tb.sv','rtl/network/m36_phy2.v'],
     'rgmii':['sim/m36_rgmii_tb.sv','rtl/network/m36_rgmii_interface.v'],
     'roles':['sim/m36_roles_tb.sv','rtl/network/m3_net_core.v']}[a.case]
top={'phy':'m36_phy2_tb','rgmii':'m36_rgmii_tb','roles':'m36_roles_tb'}[a.case]
out=R/'reports'/('m36_reproduce_'+a.case);out.mkdir(exist_ok=True)
os.environ['PATH']=str(b)+os.pathsep+os.environ['PATH']
subprocess.run([str(b/'iverilog.exe'),'-g2012','-s',top,'-y',str(lib),'-Y','.v',
                '-o',str(out/'run.vvp'),*[str(R/f) for f in src]],check=True,cwd=R)
result=subprocess.run([str(b/'vvp.exe'),str(out/'run.vvp')],cwd=R,capture_output=True,text=True)
(out/'run.log').write_text(result.stdout+result.stderr)
print(result.stdout)
sys.exit(result.returncode)
