`ifdef VENDOR_DDR
wire clk, ddr_init_done;
reg rst_n=0, acc_rst_n=0;
`else
reg clk=0, rst_n=0, ddr_init_done=0, acc_rst_n=0;
always #5 clk=~clk;
`endif
wire mem_req_valid, mem_req_ready, mem_req_write, mem_rsp_valid, mem_rsp_ready, mem_rsp_error;
wire [31:0] mem_req_addr;
wire [127:0] mem_req_data, mem_rsp_data;
wire [15:0] mem_req_strb;
wire [63:0] mem_req_tag, mem_rsp_tag;
wire fault, idle;
reg v_awvalid=0, v_arvalid=0;
wire v_awready, v_arready, v_wready, v_wlast, v_rvalid, v_rlast;
reg [27:0] v_awaddr=512, v_araddr=0;
reg [3:0] v_awid=15, v_arid=15, v_awlen=0, v_arlen=0;
reg v_awap=0, v_arap=0;
reg [255:0] v_wdata={8{32'hfabe002a}};
reg [31:0] v_wstrb=32'hffffffff;
wire [3:0] v_wid, v_rid;
wire [255:0] v_rdata;
wire axi_awvalid, axi_awready, axi_arvalid, axi_arready, axi_awuser_ap, axi_aruser_ap;
wire axi_wready, axi_wusero_last, axi_rvalid, axi_rlast;
wire [27:0] axi_awaddr, axi_araddr;
wire [3:0] axi_awuser_id, axi_awlen, axi_aruser_id, axi_arlen, axi_wusero_id, axi_rid;
wire [255:0] axi_wdata, axi_rdata;
wire [31:0] axi_wstrb;
reg block_commands=0, block_data=0, drop_write=0, corrupt_id=0, corrupt_last=0, fast_data=0;
reg [7:0] commit_delay=19;
road_ddr_bridge #(.ACC_BASE_WORD(ACC_BASE),.ACC_LIMIT_WORD(ACC_LIMIT),.VIDEO_LIMIT(29'h00800000),
    .VERIFY_RETRIES(8'd15)) dut(.*);
`ifndef VENDOR_DDR
native_bfm #(.WORDS(MEM_WORDS),.BASE({ACC_BASE[25:1],3'b000})) model(
    .clk(clk),.rst_n(rst_n),.awvalid(axi_awvalid),.awready(axi_awready),
    .awaddr(axi_awaddr),.awid(axi_awuser_id),.awlen(axi_awlen),
    .wdata(axi_wdata),.wstrb(axi_wstrb),.wready(axi_wready),.wlast(axi_wusero_last),.wid(axi_wusero_id),
    .arvalid(axi_arvalid),.arready(axi_arready),.araddr(axi_araddr),.arid(axi_aruser_id),.arlen(axi_arlen),
    .rdata(axi_rdata),.rid(axi_rid),.rvalid(axi_rvalid),.rlast(axi_rlast),
    .block_commands(block_commands),.block_data(block_data),.drop_write(drop_write),.fast_data(fast_data),
    .corrupt_id(corrupt_id),.corrupt_last(corrupt_last),.commit_delay(commit_delay));
`endif

integer cycles=0, native_commands=0, video_reads=0, video_writes=0;
integer read_beats=0, write_beats=0, video_read_jobs=0, video_write_jobs=0;
integer video_quota=0;
reg video_stress=0, video_rd_pending=0, video_wr_pending=0;
reg [3:0] video_rd_length=0, video_wr_length=0;
reg aw_stalled=0, ar_stalled=0, rsp_stalled=0;
reg [36:0] aw_hold, ar_hold;
reg [192:0] rsp_hold;
function [255:0] expected_video;
input integer beat;
reg [31:0] lo,hi;
begin
    lo=32'h12340000+beat*2; hi=lo+1;
`ifdef VENDOR_DDR
    expected_video={8{32'hfabe002a}};
`else
    expected_video={{4{hi}},{4{lo}}};
`endif
end
endfunction
always @(negedge clk) begin
    v_arvalid=rst_n && video_stress && !video_rd_pending && video_read_jobs<video_quota;
    v_awvalid=rst_n && video_stress && !video_wr_pending && video_write_jobs<video_quota;
    if(!video_rd_pending) begin v_arlen=video_read_jobs%16; v_arid=video_read_jobs%16; end
    if(!video_wr_pending) begin v_awlen=video_write_jobs%16; v_awid=video_write_jobs%16; end
`ifdef VENDOR_DDR
    if(!video_wr_pending) v_awlen=15;
`endif
end
always @(posedge clk) begin
    cycles=cycles+1;
    if(cycles>25000000) $fatal(1,"Harness global timeout");
    if(!rst_n) begin
        aw_stalled=0; ar_stalled=0; rsp_stalled=0;
        video_rd_pending=0; video_wr_pending=0; read_beats=0; write_beats=0;
    end else begin
        if(aw_stalled && (!axi_awvalid || {axi_awaddr,axi_awuser_id,axi_awlen,axi_awuser_ap}!==aw_hold))
            $fatal(1,"Native AW changed under stall");
        if(ar_stalled && (!axi_arvalid || {axi_araddr,axi_aruser_id,axi_arlen,axi_aruser_ap}!==ar_hold))
            $fatal(1,"Native AR changed under stall");
        if(rsp_stalled && acc_rst_n && (!mem_rsp_valid || {mem_rsp_data,mem_rsp_tag,mem_rsp_error}!==rsp_hold))
            $fatal(1,"Accelerator response changed under stall");
        aw_stalled=axi_awvalid && !axi_awready;
        ar_stalled=axi_arvalid && !axi_arready;
        rsp_stalled=mem_rsp_valid && !mem_rsp_ready && acc_rst_n;
        aw_hold={axi_awaddr,axi_awuser_id,axi_awlen,axi_awuser_ap};
        ar_hold={axi_araddr,axi_aruser_id,axi_arlen,axi_aruser_ap};
        rsp_hold={mem_rsp_data,mem_rsp_tag,mem_rsp_error};
        if(axi_awvalid && axi_awready) native_commands=native_commands+1;
        if(axi_arvalid && axi_arready) native_commands=native_commands+1;
        if((v_arvalid || v_awvalid) && dut.state==0 && dut.pending && !dut.response_valid &&
            !dut.cancelled && acc_rst_n && !fault && ddr_init_done && !(v_arready || v_awready))
            $fatal(1,"Video not prioritized");
        if(v_arvalid && v_arready) begin
            video_rd_pending=1; video_rd_length=v_arlen; read_beats=0;
            video_read_jobs=video_read_jobs+1;
        end
        if(v_awvalid && v_awready) begin
            video_wr_pending=1; video_wr_length=v_awlen; write_beats=0;
            video_write_jobs=video_write_jobs+1;
        end
        if(v_rvalid) begin
            if(!video_rd_pending || v_rdata!==expected_video(read_beats) ||
                v_rlast!==(read_beats==video_rd_length) || v_rid!==(video_read_jobs-1)%16)
                $fatal(1,"Video read routing/data/last mismatch");
            read_beats=read_beats+1; video_reads=video_reads+1;
            if(v_rlast) video_rd_pending=0;
        end
        if(v_wready) begin
            if(!video_wr_pending || v_wlast!==(write_beats==video_wr_length) ||
                v_wid!==(video_write_jobs-1)%16) $fatal(1,"Video write routing/last mismatch");
            write_beats=write_beats+1; video_writes=video_writes+1;
            if(v_wlast) video_wr_pending=0;
        end
    end
end
`ifndef VENDOR_DDR
task common_reset;
begin
    @(negedge clk); #1; rst_n=0; acc_rst_n=0; ddr_init_done=0;
    block_commands=0; block_data=0; drop_write=0; corrupt_id=0; corrupt_last=0; fast_data=0;
    video_stress=0;
    repeat(4) @(negedge clk);
    #1; rst_n=1;
    repeat(4) @(negedge clk);
    #1;
    if(mem_req_ready || axi_awvalid || axi_arvalid) $fatal(1,"Traffic before DDR initialization");
    ddr_init_done=1; acc_rst_n=1;
    @(negedge clk); #1;
    if(!mem_req_ready || fault) $fatal(1,"Reset did not recover");
end
endtask
`endif
