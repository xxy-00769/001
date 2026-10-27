`timescale 1ns/1ps
module bridge_tb;
localparam [31:0] ACC_BASE=32'h00200000, ACC_LIMIT=ACC_BASE+1024;
localparam MEM_WORDS=1024;
`include "harness.vh"
reg req_valid=0, req_write=0, rsp_ready=0;
reg [31:0] req_addr=0;
reg [127:0] req_data=0;
reg [15:0] req_keep=0;
reg [63:0] req_tag=0;
assign mem_req_valid=req_valid;
assign mem_req_write=req_write;
assign mem_req_addr=req_addr;
assign mem_req_data=req_data;
assign mem_req_strb=req_keep;
assign mem_req_tag=req_tag;
assign mem_rsp_ready=rsp_ready;
reg [127:0] expected [0:MEM_WORDS-1];
reg [127:0] value;
reg [31:0] rng=32'h1033aaff;
integer checks=0, mask_writes=0, invalid_cases=0, cancelled_cases=0, fault_cases=0;
integer i,j,idx,n,prior_commands,wait_count,report_file,prior_reads;
reg [15:0] keep;
task request;
input wr;
input [31:0] address;
input [127:0] data;
input [15:0] mask;
begin
    @(negedge clk); #1;
    req_valid=1; req_write=wr; req_addr=address; req_data=data; req_keep=mask;
    req_tag=req_tag+64'h100000001;
    wait_count=0;
    @(posedge clk);
    while(!mem_req_ready && wait_count<100000) begin @(posedge clk); wait_count=wait_count+1; end
    if(!mem_req_ready) $fatal(1,"Request acceptance timeout");
    @(negedge clk); #1; req_valid=0;
end
endtask
task response;
input err;
input [127:0] data;
input integer hold_cycles;
begin
    wait_count=0;
    while(!mem_rsp_valid && wait_count<100000) begin @(negedge clk); #2; wait_count=wait_count+1; end
    if(!mem_rsp_valid || mem_rsp_error!==err || mem_rsp_tag!==req_tag ||
        mem_rsp_data!==data) $fatal(1,"Response mismatch err=%b expected=%b data=%h expected=%h",mem_rsp_error,err,mem_rsp_data,data);
    repeat(hold_cycles) begin
        @(negedge clk); #2;
        if(mem_req_ready || !mem_rsp_valid) $fatal(1,"Single outstanding/backpressure violation");
    end
    rsp_ready=1;
    @(negedge clk); #2; rsp_ready=0;
    checks=checks+1;
end
endtask
task cancel_at;
input integer target;
input wr;
begin
    block_commands=target==1 || target==3;
    block_data=target==2 || target==4;
    request(wr,ACC_BASE+7,128'h1817161514131211100f0e0d0c0b0a09,16'hffff);
    wait_count=0;
    while(dut.state!=target && wait_count<1000) begin @(negedge clk); #2; wait_count=wait_count+1; end
    if(dut.state!=target) $fatal(1,"Cancel state not reached");
    acc_rst_n=0;
    repeat(3) @(negedge clk);
    #2; acc_rst_n=1; block_commands=0; block_data=0;
    wait_count=0;
    while(!idle && wait_count<1000) begin
        @(negedge clk); #2; wait_count=wait_count+1;
        if(mem_rsp_valid) $fatal(1,"Cancelled response leaked to new job");
    end
    if(!idle || fault) $fatal(1,"Cancelled transaction did not drain");
    repeat(40) @(negedge clk);
    cancelled_cases=cancelled_cases+1;
end
endtask
initial begin
    common_reset;
    for(i=0;i<MEM_WORDS;i=i+1) expected[i]=model.memory[i];
    for(i=0;i<256;i=i+1) begin
        rng=rng*1664525+1013904223;
        idx=i<32 ? i : rng%MEM_WORDS;
        value={rng,~rng,rng^32'ha55ac33c,rng+32'h12345678};
        keep=i<16 ? 16'(1<<i) : i<32 ? 16'hffff : rng[15:0];
        request(1,ACC_BASE+idx,value,keep);
        response(0,0,i%5);
        for(j=0;j<16;j=j+1)
            if(keep[j]) expected[idx][j*8+:8]=value[j*8+:8];
        for(j=0;j<MEM_WORDS;j=j+1)
            if(model.memory[j]!==expected[j]) $fatal(1,"Masked write/neighbor corruption index=%0d",j);
        request(0,ACC_BASE+idx,0,0);
        response(0,expected[idx],i%7);
        mask_writes=mask_writes+1;
    end
    request(1,ACC_LIMIT-1,128'hffffffffffffffffffffffffffffffff,16'hf00f);
    response(0,0,4);
    prior_commands=native_commands;
    request(1,ACC_BASE,0,0); response(0,0,4);
    if(native_commands!=prior_commands) $fatal(1,"Zero-mask write issued native traffic");
    for(i=0;i<5;i=i+1) begin
        case(i)
        0: value=ACC_BASE-1;
        1: value=ACC_LIMIT;
        2: value=32'hffffffff;
        3: value=32'h04000000;
        4: value=0;
        endcase
        request(i[0],value[31:0],0,16'hffff); response(1,0,3);
        if(native_commands!=prior_commands) $fatal(1,"Rejected request issued native traffic");
        invalid_cases=invalid_cases+1;
    end
    // Deliberately delay visibility: readback retries must precede write success.
    commit_delay=180; prior_reads=model.reads;
    request(1,ACC_BASE+500,128'hc0ffee0123456789abcdef0001020304,16'hffff);
    response(0,0,8);
    if(model.reads-prior_reads<2 || model.commit_pending) $fatal(1,"Write acknowledged before readback/commit");
    commit_delay=19;
    drop_write=1;
    request(1,ACC_BASE+501,128'hc0ffee0123456789abcdef0001020304,16'hffff);
    response(1,0,3);
    drop_write=0; fault_cases=fault_cases+1;
    // Both video channels request bursts while the accelerator is pending.
    video_quota=32; video_stress=1;
    request(0,ACC_BASE+400,0,0); response(0,model.memory[400],8);
    wait_count=0;
    while((video_read_jobs<video_quota || video_write_jobs<video_quota ||
        video_rd_pending || video_wr_pending) && wait_count<100000) begin
        @(negedge clk); #2; wait_count=wait_count+1;
    end
    if(video_read_jobs!=32 || video_write_jobs!=32) $fatal(1,"Video contention did not complete");
    video_stress=0;
    // A held accelerator response must not block fresh video bursts.
    request(0,ACC_BASE+401,0,0);
    wait(mem_rsp_valid);
    @(negedge clk); #2; video_quota=48; video_stress=1;
    wait_count=0;
    while((video_read_jobs<48 || video_write_jobs<48 || video_rd_pending || video_wr_pending) && wait_count<100000) begin
        @(negedge clk); #2; wait_count=wait_count+1;
    end
    if(video_read_jobs!=48 || video_write_jobs!=48) $fatal(1,"Held response blocked video");
    video_stress=0;
    response(0,model.memory[401],4);
    fast_data=1;
    for(i=0;i<16;i=i+1) begin
        request(1,ACC_BASE+600+i,{4{32'h90120000+i}},16'hffff); response(0,0,3);
        request(0,ACC_BASE+600+i,0,0); response(0,{4{32'h90120000+i}},3);
    end
    fast_data=0;
    cancel_at(1,1); cancel_at(2,1); cancel_at(3,0); cancel_at(4,0);
    request(0,ACC_BASE+7,0,0); response(0,model.memory[7],10);
    // Cancellation also clears a buffered response that has not been consumed.
    request(0,ACC_BASE+9,0,0);
    wait(mem_rsp_valid);
    @(negedge clk); #2; acc_rst_n=0;
    repeat(4) @(negedge clk);
    #2; acc_rst_n=1;
    repeat(4) @(negedge clk);
    if(mem_rsp_valid || !mem_req_ready) $fatal(1,"Buffered response survived cancel");
    cancelled_cases=cancelled_cases+1;
    for(i=0;i<5;i=i+1) begin
        common_reset;
        block_data=1;
        request(i[0],ACC_BASE+20,128'hdeadbeef,16'hffff);
        wait(dut.state==2 || dut.state==4);
        @(negedge clk); #2;
        if(i<2) corrupt_id=1;
        else if(i<4) corrupt_last=1;
        else ddr_init_done=0;
        block_data=0;
        wait_count=0;
        while(!fault && wait_count<1000) begin @(negedge clk); #2; wait_count=wait_count+1; end
        if(!fault) $fatal(1,"Native corruption/init loss not latched");
        response(1,0,3);
        if(mem_req_ready || axi_awvalid || axi_arvalid) $fatal(1,"Fatal adapter issued traffic");
        fault_cases=fault_cases+1;
    end
    for(i=0;i<4;i=i+1) begin
        common_reset;
        prior_commands=native_commands;
        video_quota=2;
        video_read_jobs=i[0] ? 2 : 1;
        video_write_jobs=i[0] ? 1 : 2;
        if(i[0]) begin
            v_awaddr=i<2 ? 28'd513 : 28'h07ffff8;
        end else begin
            v_araddr=i<2 ? 28'd1 : 28'h07ffff8;
        end
        video_stress=1;
        wait(fault);
        @(negedge clk); #2;
        if(axi_awvalid || axi_arvalid || native_commands!=prior_commands) $fatal(1,"Video range rejection leaked command");
        video_stress=0; fault_cases=fault_cases+1;
        v_awaddr=512; v_araddr=0;
    end
    // A video fault and accelerator acceptance can occur on the same edge.
    common_reset;
    prior_commands=native_commands;
    @(posedge clk); #1;
    video_quota=2; video_read_jobs=1; video_write_jobs=2;
    v_araddr=1; video_stress=1;
    req_valid=1; req_write=0; req_addr=ACC_BASE; req_data=0; req_keep=0;
    req_tag=req_tag+64'h100000001;
    @(posedge clk);
    if(!mem_req_ready || !v_arready) $fatal(1,"Simultaneous acceptance not exercised");
    @(negedge clk); #2; req_valid=0; video_stress=0;
    response(1,0,3);
    if(!fault || native_commands!=prior_commands) $fatal(1,"Simultaneous fault leaked command");
    fault_cases=fault_cases+1; v_araddr=0;
    common_reset;
    request(0,ACC_BASE,0,0); response(0,model.memory[0],2);
    report_file=$fopen("output/bridge_counts.txt","w");
    $fdisplay(report_file,"%0d %0d %0d %0d %0d %0d %0d %0d %0d",checks,mask_writes,
        invalid_cases,cancelled_cases,fault_cases,video_reads,video_writes,native_commands,cycles);
    $fclose(report_file);
    $display("PASS: native bridge masks=%0d invalid=%0d cancels=%0d faults=%0d video_read_beats=%0d video_write_beats=%0d",
        mask_writes,invalid_cases,cancelled_cases,fault_cases,video_reads,video_writes);
    $finish;
end
endmodule
