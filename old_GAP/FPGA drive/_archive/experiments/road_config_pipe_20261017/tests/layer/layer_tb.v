`timescale 1ns/1ps
module layer_tb;
`include "output/cases.vh"
reg clk=0, rst_n=0;
always #5 clk=~clk;
reg [3:0] cfg_command=0, memory_command=0;
reg [127:0] cfg_payload=0, memory_payload=0;
reg req_ready=0, rsp_error=0;
reg [3:0] select=0;
wire [31:0] observe;
wire [3:0] command=cfg_command | memory_command;
wire [127:0] payload=memory_command!=0 ? memory_payload : cfg_payload;
layer_probe dut(.clk(clk), .rst_n(rst_n), .command(command), .payload(payload),
    .mem_req_ready(req_ready), .mem_rsp_error(rsp_error), .select(select), .observe(observe));

reg [127:0] memory [0:MEMORY_WORDS-1];
reg [127:0] golden [0:MEMORY_WORDS-1];
reg [176:0] transactions [0:TRANSACTIONS-1];
reg [319:0] descriptors [0:CASES-1];
reg [319:0] bad_descriptor;
reg [31:0] random_state=32'h102017ab;
reg [304:0] stalled_payload;
reg stalled=0, pending=0, pending_write=0, pending_error=0, pending_bad_tag=0;
reg [31:0] pending_address;
reg [127:0] pending_data;
reg [15:0] pending_keep;
reg [63:0] pending_tag;
integer response_stage=0, response_delay=0;
integer cycles=0, job_start=0, job=0, index=0, lane=0, file_jobs, file_cycles, file_outputs;
integer scan, expected_start=0, expected_count=0, expected_reads=0, expected_writes=0, expected_tiles=0, expected_padding=0;
integer cursor=0, requests=0, read_count=0, write_count=0, ack_count=0, tiles=0, reuse_count=0, zero_count=0;
integer sequence_number=0, stalls=0, response_waits=0, final_delay_count=0, checks=0, success_jobs=0;
integer inject=0, fault_cases=0, reset_cases=0, timeout_count=0;
reg injected=0, check_trace=0, block_responses=0, active=0;
reg [31:0] expected_job_id=0;
reg [176:0] expected;
wire [304:0] request_payload={dut.mem_req_write,dut.mem_req_addr,dut.mem_req_data,dut.mem_req_strb,dut.mem_req_tag,64'd0};

// Responses are explicitly later than requests; writes commit on acknowledgement.
always @(negedge clk) begin
    if(!rst_n) begin req_ready=0; memory_command=0; memory_payload=0; rsp_error=0; end
    else begin
        select=cycles%10;
        req_ready=(random_state[2:0]!=0 && random_state[5:3]!=0);
        memory_command=0; memory_payload=0; rsp_error=0;
        if(response_stage==2) begin memory_command=4; memory_payload={64'd0,pending_tag}; end
        if(response_stage==3) begin
            memory_command=8; memory_payload=pending_data; rsp_error=pending_error;
        end
    end
end

always @(posedge clk) begin
    cycles=cycles+1;
    if(cycles>15000000) $fatal(1,"Global timeout");
    random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
    if(!rst_n) begin
        pending=0; response_stage=0; stalled=0; sequence_number=0;
    end else begin
        case(select)
        0: if(observe!=={10'd0,dut.fault_code,7'd0,dut.mem_rsp_ready,dut.mem_req_write,dut.mem_req_valid,dut.done,dut.fault,dut.busy,dut.cfg_ready}) $fatal(1,"Probe flags");
        1: if(observe!==dut.mem_req_addr) $fatal(1,"Probe address");
        2: if(observe!==dut.mem_req_tag[31:0]) $fatal(1,"Probe tag low");
        3: if(observe!==dut.mem_req_tag[63:32]) $fatal(1,"Probe tag high");
        4,5,6,7: if(observe!==dut.mem_req_data[(select-4)*32+:32]) $fatal(1,"Probe data");
        8: if(observe!=={16'd0,dut.mem_req_strb}) $fatal(1,"Probe strobes");
        9: if(observe!==dut.result_job_id) $fatal(1,"Probe result");
        endcase
        if(stalled && (!dut.mem_req_valid || request_payload!==stalled_payload)) $fatal(1,"Request changed under backpressure");
        stalled=dut.mem_req_valid && !req_ready;
        stalled_payload=request_payload;
        if(stalled) stalls=stalls+1;
        if(dut.mem_rsp_ready && !command[3]) response_waits=response_waits+1;
        if(response_stage==1 && !block_responses) begin
            if(response_delay==0) response_stage=2;
            else response_delay=response_delay-1;
        end else if(response_stage==2) response_stage=3;
        else if(response_stage==3 && dut.mem_rsp_ready && command[3]) begin
            if(!pending) $fatal(1,"Response without outstanding request");
            if(pending_write && !pending_error && !pending_bad_tag) begin
                for(lane=0;lane<16;lane=lane+1)
                    if(pending_keep[lane]) memory[pending_address][lane*8+:8]=pending_data[lane*8+:8];
                ack_count=ack_count+1;
            end
            pending=0; response_stage=0;
        end
        if(dut.mem_req_valid && req_ready) begin
            if(pending || !active) $fatal(1,"Multiple outstanding requests or inactive job");
            if(dut.mem_req_tag!=={expected_job_id,32'(sequence_number)}) $fatal(1,"Request tag mismatch");
            if(dut.mem_req_addr>=MEMORY_WORDS) $fatal(1,"Request outside memory arena");
            if(check_trace) begin
                if(cursor>=expected_start+expected_count) $fatal(1,"Extra transaction");
                expected=transactions[cursor];
                if(dut.mem_req_write!==expected[176] || dut.mem_req_addr!==expected[175:144] || dut.mem_req_strb!==expected[143:128])
                    $fatal(1,"Transaction mismatch job=%0d cursor=%0d address=%0d expected=%0d",job,cursor,dut.mem_req_addr,expected[175:144]);
                if(dut.mem_req_write) begin
                    for(lane=0;lane<16;lane=lane+1)
                        if(dut.mem_req_strb[lane] && dut.mem_req_data[lane*8+:8]!==expected[lane*8+:8])
                            $fatal(1,"Write value mismatch job=%0d address=%0d lane=%0d",job,dut.mem_req_addr,lane);
                    $fdisplay(file_outputs,"%0d %0d %032h %04h",job,dut.mem_req_addr,dut.mem_req_data,dut.mem_req_strb);
                end else if(memory[dut.mem_req_addr]!==expected[127:0]) $fatal(1,"Read data mismatch (including chained result)");
                cursor=cursor+1;
            end
            pending=1; pending_write=dut.mem_req_write; pending_address=dut.mem_req_addr;
            pending_keep=dut.mem_req_strb; pending_tag=dut.mem_req_tag;
            pending_data=dut.mem_req_write ? dut.mem_req_data : memory[dut.mem_req_addr];
            pending_error=0; pending_bad_tag=0;
            if(!injected && ((inject<=2 && inject>0 && !pending_write) || (inject>=3 && pending_write))) begin
                pending_error=inject==1 || inject==3;
                pending_bad_tag=inject==2 || inject==4;
                if(pending_bad_tag) pending_tag=pending_tag ^ 64'h100000000;
                injected=1;
            end
            requests=requests+1; sequence_number=sequence_number+1;
            if(pending_write) write_count=write_count+1;
            else read_count=read_count+1;
            response_delay=1+random_state[11:8]; response_stage=1;
            if(check_trace && pending_write && write_count==expected_writes) begin
                response_delay=50; final_delay_count=final_delay_count+1;
            end
        end
        if(dut.engine.core_cfg_ready && dut.engine.state==8) begin
            tiles=tiles+1;
            if(dut.engine.reuse_tile) reuse_count=reuse_count+1;
        end
        if(dut.engine.state==15 && dut.engine.core_vec_ready && dut.engine.load_kind==0 && dut.engine.input_outside)
            zero_count=zero_count+1;
        if(dut.done) begin
            if(!active || pending || response_stage!=0 || dut.fault || !check_trace) $fatal(1,"Premature/unexpected completion");
            if(cursor!=expected_start+expected_count || ack_count!=expected_writes || dut.result_job_id!==expected_job_id)
                $fatal(1,"Completion before all acknowledged writes");
        end
        if(dut.fault && (dut.mem_req_valid || dut.mem_rsp_ready || dut.done || dut.cfg_ready)) $fatal(1,"Fault did not halt interface");
    end
end

task reset_dut;
begin
    @(negedge clk); #1; rst_n=0; cfg_command=0; block_responses=0; active=0;
    repeat(4) @(negedge clk);
    #1; rst_n=1;
    @(negedge clk); #1;
    if(!dut.cfg_ready || dut.fault || dut.done || dut.result_job_id!=0) $fatal(1,"Reset state invalid");
end
endtask

task submit;
input [319:0] descriptor;
integer word;
begin
    if(!dut.cfg_ready) $fatal(1,"Submit while not ready");
    for(word=0;word<10;word=word+1) begin
        @(negedge clk); #1; cfg_command=2; cfg_payload=descriptor[word*32+:32];
    end
    @(negedge clk); #1;
    if(dut.descriptor!==descriptor) $fatal(1,"Descriptor probe serial order");
    requests=0; read_count=0; write_count=0; ack_count=0; tiles=0; reuse_count=0; zero_count=0;
    sequence_number=0; stalls=0; response_waits=0; injected=0;
    expected_job_id=descriptor[31:0]; job_start=cycles; active=1; cfg_command=1;
    @(negedge clk); #1; cfg_command=0;
end
endtask

task expect_fault;
input integer code;
input integer no_requests;
integer wait_cycles;
reg [31:0] previous_result;
begin
    previous_result=dut.result_job_id;
    wait_cycles=0;
    while(!dut.fault && wait_cycles<200000) begin @(negedge clk); #2; wait_cycles=wait_cycles+1; end
    if(!dut.fault || dut.fault_code!=code) $fatal(1,"Fault code expected=%0d actual=%0d state=%0d",code,dut.fault_code,dut.engine.state);
    if(no_requests && requests!=0) $fatal(1,"Invalid descriptor issued memory request");
    repeat(12) begin
        @(negedge clk); #2;
        if(!dut.fault || dut.done || dut.result_job_id!=previous_result || dut.mem_req_valid || dut.mem_rsp_ready)
            $fatal(1,"Fault not latched or published result");
    end
    fault_cases=fault_cases+1; active=0;
end
endtask

initial begin
    $readmemh("output/initial.hex",memory);
    $readmemh("output/golden.hex",golden);
    $readmemh("output/transactions.hex",transactions);
    $readmemh("output/descriptors.hex",descriptors);
    file_jobs=$fopen("output/jobs.txt","r");
    file_cycles=$fopen("output/rtl_cycles.txt","w");
    file_outputs=$fopen("output/rtl_outputs.txt","w");
    if(!file_jobs || !file_cycles || !file_outputs) $fatal(1,"Open test files failed");
    reset_dut;
    check_trace=1;
    for(job=0;job<CASES;job=job+1) begin
        scan=$fscanf(file_jobs,"%d %d %d %d %d %d\n",expected_start,expected_count,expected_reads,expected_writes,expected_tiles,expected_padding);
        if(scan!=6) $fatal(1,"Invalid metadata");
        cursor=expected_start;
        submit(descriptors[job]);
        // Descriptor writes/submits while busy must be ignored, including shared payload noise.
        cfg_command=3; cfg_payload=128'hffffffffffffffffffffffffffffffff;
        timeout_count=0;
        while(!dut.done && !dut.fault && timeout_count<4000000) begin
            @(negedge clk); #2; timeout_count=timeout_count+1;
            cfg_command=dut.busy ? (timeout_count[0] ? 4'd3 : 4'd1) : 4'd0;
        end
        cfg_command=0;
        if(dut.fault || !dut.done) $fatal(1,"Layer failed job=%0d code=%0d state=%0d",job,dut.fault_code,dut.engine.state);
        if(dut.descriptor!==descriptors[job]) $fatal(1,"Busy descriptor altered");
        if(pending || ack_count!=expected_writes || dut.result_job_id!=expected_job_id || cursor!=expected_start+expected_count)
            $fatal(1,"Completion contract");
        if(read_count!=expected_reads || write_count!=expected_writes || tiles!=expected_tiles || reuse_count!=tiles-1 || zero_count!=expected_padding)
            $fatal(1,"Counters mismatch job=%0d reads=%0d writes=%0d tiles=%0d padding=%0d",job,read_count,write_count,tiles,zero_count);
        $fdisplay(file_cycles,"%0d %0d %0d %0d %0d %0d %0d %0d %0d",job,cycles-job_start,read_count,write_count,tiles,reuse_count,zero_count,stalls,response_waits);
        $display("LAYER_PASS job=%0d cycles=%0d reads=%0d writes=%0d tiles=%0d",job,cycles-job_start,read_count,write_count,tiles);
        success_jobs=success_jobs+1;
        @(negedge clk); #2; active=0;
        if(dut.done || !dut.cfg_ready) $fatal(1,"Completion not single pulse");
    end
    for(index=0;index<MEMORY_WORDS;index=index+1) begin
        if(memory[index]!==golden[index]) $fatal(1,"Final memory/canary mismatch address=%0d",index);
        checks=checks+1;
    end
    $fclose(file_outputs); $fclose(file_cycles); $fclose(file_jobs);
    check_trace=0;
    // Descriptor validation: no memory request may precede rejection.
    for(index=0;index<11;index=index+1) begin
        // First fault follows a successful job without reset: retain its result ID.
        if(index!=0) reset_dut;
        bad_descriptor=descriptors[0]; bad_descriptor[31:0]=100+index;
        case(index)
        0: bad_descriptor[230:224]=0;
        1: bad_descriptor[280:271]=0;
        2: bad_descriptor[319]=1;
        3: bad_descriptor[95:64]=bad_descriptor[63:32];
        4: bad_descriptor[63:32]=32'hfffffff0;
        5: begin bad_descriptor[95:64]=32'hfffffff8; bad_descriptor[223:192]=32'hffffffff; end
        6: bad_descriptor[95:64]=bad_descriptor[127:96];
        7: bad_descriptor[95:64]=bad_descriptor[159:128];
        8: begin
            bad_descriptor[230:224]=80; bad_descriptor[237:231]=80; bad_descriptor[239:238]=3;
            bad_descriptor[250:246]=1;
            bad_descriptor[95:64]=20000; bad_descriptor[127:96]=30000; bad_descriptor[159:128]=40000;
        end
        9: begin
            bad_descriptor[230:224]=80; bad_descriptor[237:231]=80; bad_descriptor[239:238]=3;
            bad_descriptor[241:240]=2; bad_descriptor[245:242]=8; bad_descriptor[250:246]=8;
            bad_descriptor[260:251]=7; bad_descriptor[270:261]=7;
            bad_descriptor[280:271]=4; bad_descriptor[290:281]=4; bad_descriptor[291]=1;
            bad_descriptor[95:64]=20000; bad_descriptor[127:96]=30000; bad_descriptor[159:128]=40000;
        end
        10: begin
            bad_descriptor[230:224]=2; bad_descriptor[291]=1;
        end
        endcase
        submit(bad_descriptor);
        expect_fault(index<2 || index==10 ? 1 : index==2 ? 8 : index>=8 ? 3 : 2,1);
    end
    // Read and write errors, plus mismatched transaction tags.
    for(index=1;index<=4;index=index+1) begin
        reset_dut; inject=index; bad_descriptor=descriptors[0]; bad_descriptor[31:0]=200+index;
        submit(bad_descriptor);
        expect_fault(index==1 || index==3 ? 5 : 6,0);
        if(!injected) $fatal(1,"Fault injection missed");
    end
    inject=0;
    // Propagate a core fault and reject a corrupted core output index.
    reset_dut; bad_descriptor=descriptors[0]; bad_descriptor[31:0]=300;
    submit(bad_descriptor);
    force dut.engine.core_fault=1'b1;
    expect_fault(4,0);
    release dut.engine.core_fault;
    reset_dut; bad_descriptor[31:0]=301; submit(bad_descriptor);
    wait(dut.engine.core_out_valid && dut.engine.state==18);
    @(negedge clk); #2; force dut.engine.core_index=16'hffff;
    expect_fault(7,0);
    release dut.engine.core_index;
    reset_dut; bad_descriptor[31:0]=302; submit(bad_descriptor);
    force dut.engine.state=5'd30;
    expect_fault(9,0);
    release dut.engine.state;
    // Adapter and engine are reset together with a read/write outstanding.
    for(index=0;index<2;index=index+1) begin
        reset_dut; bad_descriptor=descriptors[0]; bad_descriptor[31:0]=400+index;
        submit(bad_descriptor);
        if(index==0) begin block_responses=1; wait(pending); end
        else begin wait(pending && pending_write); block_responses=1; end
        repeat(8) begin @(negedge clk); #2; if(dut.done) $fatal(1,"Completed without acknowledgement"); end
        reset_dut;
        repeat(8) begin @(negedge clk); #2; if(dut.done || dut.mem_req_valid) $fatal(1,"Reset transaction escaped"); end
        reset_cases=reset_cases+1;
    end
    // Fresh job after faults and reset, still without reloading input memory.
    check_trace=1; job=0; expected_start=0;
    file_jobs=$fopen("output/jobs.txt","r");
    scan=$fscanf(file_jobs,"%d %d %d %d %d %d\n",expected_start,expected_count,expected_reads,expected_writes,expected_tiles,expected_padding);
    $fclose(file_jobs); cursor=expected_start;
    file_outputs=$fopen("output/recovery_outputs.txt","w");
    bad_descriptor=descriptors[0]; bad_descriptor[31:0]=500; submit(bad_descriptor);
    wait(dut.done || dut.fault);
    @(negedge clk); #2;
    if(dut.fault || pending || ack_count!=expected_writes || dut.result_job_id!=500) $fatal(1,"Recovery failed");
    @(negedge clk); #2; active=0;
    $fclose(file_outputs);
    if(final_delay_count!=CASES+1) $fatal(1,"Final write delay not exercised");
    $display("PASS: layer_dma %0d layers %0d memory words %0d fault cases %0d reset cases; recovery passed",success_jobs,checks,fault_cases,reset_cases);
    $finish;
end
endmodule
