"""Exercise the actual native read controller, without a camera/writer/owner model."""
from pathlib import Path
import subprocess, datetime, json, hashlib, os, re

D = Path(__file__).resolve().parents[2]
R = Path('E:/zhoumian/FPGA/JF/checks') / ('v5_1_native_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
R.mkdir(parents=True)
BIN = Path('E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin')
os.environ['PATH'] = str(BIN) + os.pathsep + os.environ['PATH']
LIB = Path('E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation')
rtl = ['mpi7001_timing.v', 'rd_buf.v', 'wr_rd_ctrl_top.v', 'wr_cmd_trans.v',
       'rd_ctrl.v', 'wr_ctrl.v', 'rd_fram_buf/rd_fram_buf.v',
       'rd_fram_buf/rtl/ipml_sdpram_v1_6_rd_fram_buf.v']
sources = [D / 'source/rtl' / p for p in rtl]
fixture = D / 'tools/v5_display/reader_tb.sv'
manifest = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sources + [fixture, Path(__file__), LIB/'GTP_GRS.v', LIB/'GTP_DRM18K.v']}
tb = fixture.read_text(encoding='utf-8')
tb = tb.replace('reg done=0,ren=0;', 'wire done,ren,ready;')
tb = tb.replace('reg [255:0] data=0;', 'wire [255:0] data;')
tb = tb.replace('.ddr_rrdy(1\'b1)', '.ddr_rrdy(ready)')
a = tb.index('    integer beat,lane,row,col,transactions=0;')
b = tb.index('    integer x=0,y=0,pixels=0,frames=0;', a)
tb = tb[:a] + r'''
    wire [27:0] native_addr;
    wire [3:0] native_len;
    wire native_valid;
    reg native_ready=0, native_rvalid=0, native_rlast=0;
    reg [255:0] native_data=0;
    wr_rd_ctrl_top #(.MEM_DQ_WIDTH(32)) controller (
        .clk(dc),.rstn(rst),
        .wr_cmd_en(1'b0),.wr_cmd_addr(28'd0),.wr_cmd_len(32'd80),
        .wr_ctrl_data(256'd0),.axi_awready(1'b0),.axi_wready(1'b0),
        .axi_wlast(1'b0),.axi_bid(4'd0),.axi_bresp(2'd0),.axi_bvalid(1'b0),
        .rd_cmd_en(command),.rd_cmd_addr(addr),.rd_cmd_len(len),
        .rd_cmd_ready(ready),.rd_cmd_done(done),
        .read_ready(1'b1),.read_rdata(data),.read_en(ren),
        .axi_araddr(native_addr),.axi_arlen(native_len),
        .axi_arvalid(native_valid),.axi_arready(native_ready),
        .axi_rdata(native_data),.axi_rvalid(native_rvalid),
        .axi_rlast(native_rlast),.axi_rid(4'd0),.axi_rresp(2'd0));
    integer beat,lane,row,col,transactions=0,base,burst_len,expected_base=0;
    always @(posedge dc) if(command) begin
        if(addr[21:0] !== expected_base || len !== 80 || !ready)
            $fatal(1,"Line command mismatch addr=%h expected=%h",addr,expected_base);
        expected_base=(expected_base==718*640) ? 0 : expected_base+1280;
    end
    initial begin
        wait(rst);
        forever begin
            @(negedge dc); native_ready=1;
            do @(posedge dc); while(!native_valid);
            base=native_addr[21:0]/8; burst_len=native_len+1;
            if(native_addr[2:0]!=0 || burst_len!=16)
                $fatal(1,"Native address/burst length");
            @(negedge dc); native_ready=0;
            repeat(2+transactions%7) @(negedge dc);
            for(beat=0;beat<burst_len;beat=beat+1) begin
                if(beat%5==3) repeat(3) @(negedge dc);
                row=(base+beat)/80; col=((base+beat)%80)*16;
                for(lane=0;lane<16;lane=lane+1)
                    native_data[lane*16+:16]=pattern(row,col+lane);
                native_rvalid=1; native_rlast=beat==burst_len-1;
                @(negedge dc); native_rvalid=0; native_rlast=0;
            end
            transactions=transactions+1;
        end
    end
''' + tb[b:]
(R/'reader_tb.sv').write_text(tb, encoding='utf-8')
compat = sources[-1].read_text(encoding='utf-8')
compat, n = re.subn(r'(integer\s+gen_cs[ab];\s*)always@\(\*\)', r'\1always_comb', compat)
assert n == 2
(R/sources[-1].name).write_text(compat, encoding='utf-8')
sources[-1] = R/sources[-1].name
result = {'Verdict':'ERROR', 'Directory':str(R), 'BoardVerified':False,
          'Boundary':'Timing -> production rd_buf -> production native controllers -> address-based return BFM; original DRM primitive',
          'Excluded':'Camera, writer, ownership, physical DDR and HDMI',
          'RAMCompatibility':'Simulation copy only: constant CSA/CSB blocks use always_comb'}
print(R, flush=True)
try:
    for name,args in [('compile',[BIN/'iverilog.exe','-g2012','-s','reader_tb','-y',LIB,'-Y','.v','-o','reader.vvp',*sources,R/'reader_tb.sv']),
                      ('simulate',[BIN/'vvp.exe','reader.vvp'])]:
        with (R/(name+'.log')).open('wb') as log:
            code=subprocess.run([str(x) for x in args], cwd=R, stdout=log, stderr=subprocess.STDOUT, timeout=180).returncode
        if code: raise RuntimeError((R/(name+'.log')).read_text(errors='replace')[-2000:])
    log=(R/'simulate.log').read_text()
    assert 'READER_PASS' in log
    result.update(Verdict='PASS', Summary=log)
except Exception as e:
    result['Error']=str(e)
result['InputsUnchanged']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in manifest.items())
(R/'inputs.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(R/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
if result['Verdict']!='PASS': raise SystemExit(1)
