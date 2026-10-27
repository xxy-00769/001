"""Reproduce the two original design behaviours from frozen 3.2 sources."""
from pathlib import Path
import datetime, os, subprocess
R=Path(__file__).resolve().parent;S=R/'source'
O=R/('rerun_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));O.mkdir()
B=Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin')
LIB=Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
os.environ['PATH']=str(B)+os.pathsep+os.environ['PATH']
cases={'backlog':['sim/m33_backlog_tb.sv','rtl/network/m3_mac.v','rtl/network/m3_byte_ram.v','rtl/network/m3_net_core.v'],
       'wait':['sim/m33_wait_tb.sv','rtl/network/m3_right_store.v','rtl/display/m2_rd_buf.v','sim/line_ram_model.sv']+
       ['rtl/reuse/'+n+'.v' for n in ['wr_rd_ctrl_top','wr_cmd_trans','wr_ctrl','rd_ctrl']]}
for name,files in cases.items():
    commands=[[B/'iverilog.exe','-g2012','-s','m33_'+name+'_tb','-y',LIB,'-Y','.v','-o',name+'.vvp',*[S/f for f in files]],
              [B/'vvp.exe',name+'.vvp']]
    for phase,cmd in zip(['compile','run'],commands):
        q=subprocess.run([str(x) for x in cmd],cwd=O,capture_output=True,timeout=60)
        (O/(name+'_'+phase+'.log')).write_bytes(q.stdout+q.stderr)
        assert q.returncode==0,(name,phase,q.stdout,q.stderr)
    print(name,(O/(name+'_run.log')).read_text())
print(O)
