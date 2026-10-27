`timescale 1ns/1ps
module layer_tb;
`include "output/cases.vh"
localparam MEM_WORDS=MEMORY_WORDS+MEMORY_WORDS%2;
localparam [31:0] ACC_BASE=32'h00200000, ACC_LIMIT=ACC_BASE+MEM_WORDS;
`include "harness.vh"
reg cfg_valid=0;
reg [319:0] cfg_descriptor=0;
wire cfg_ready, busy, layer_fault, done;
wire [7:0] fault_code;
wire [31:0] result_job_id;
conv_layer_dma engine(
    .clk(clk),.rst_n(rst_n && acc_rst_n),
    .cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_descriptor(cfg_descriptor),
    .busy(busy),.fault(layer_fault),.fault_code(fault_code),.done(done),.result_job_id(result_job_id),
    .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),.mem_req_write(mem_req_write),
    .mem_req_addr(mem_req_addr),.mem_req_data(mem_req_data),.mem_req_strb(mem_req_strb),.mem_req_tag(mem_req_tag),
    .mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),.mem_rsp_data(mem_rsp_data),
    .mem_rsp_tag(mem_rsp_tag),.mem_rsp_error(mem_rsp_error));
reg [127:0] golden [0:MEMORY_WORDS-1];
reg [176:0] transactions [0:TRANSACTIONS-1];
reg [319:0] descriptors [0:CASES-1];
reg [176:0] expected;
reg [319:0] descriptor;
reg [63:0] outstanding_tag;
reg [127:0] read_expected;
reg outstanding=0, outstanding_write=0;
integer job=0, index, lane, word, cursor=0, sequence_number=0;
integer start_index, count, expected_reads, expected_writes, expected_tiles, expected_padding;
integer reads=0, writes=0, acknowledgements=0, output_bytes=0;
integer jobs_file, output_file, cycle_file, count_file, scan, started, waits=0;
integer all_reads=0, all_writes=0;
always @(posedge clk) begin
    if(rst_n && acc_rst_n) begin
        if(fault || layer_fault) $fatal(1,"Integrated layer fault code=%0d",fault_code);
        if(mem_rsp_valid && mem_rsp_ready) begin
            if(!outstanding || mem_rsp_error || mem_rsp_tag!==outstanding_tag)
                $fatal(1,"Integrated memory response mismatch");
            if(!outstanding_write && mem_rsp_data!==read_expected) $fatal(1,"Integrated read value mismatch");
            if(outstanding_write) acknowledgements=acknowledgements+1;
            outstanding=0;
        end
        if(mem_req_valid && mem_req_ready) begin
            if(outstanding || cursor>=start_index+count) $fatal(1,"Extra/multiple request");
            expected=transactions[cursor];
            if(mem_req_write!==expected[176] || mem_req_addr!==expected[175:144]+ACC_BASE ||
                mem_req_strb!==expected[143:128] || mem_req_tag!=={descriptors[job][31:0],32'(sequence_number)})
                $fatal(1,"Integrated request mismatch job=%0d cursor=%0d",job,cursor);
            if(mem_req_write) begin
                for(lane=0;lane<16;lane=lane+1) begin
                    if(mem_req_strb[lane]) begin
                        if(mem_req_data[lane*8+:8]!==expected[lane*8+:8]) $fatal(1,"Integrated output byte mismatch");
                        output_bytes=output_bytes+1;
                    end
                end
                writes=writes+1; all_writes=all_writes+1;
                $fdisplay(output_file,"%0d %0d %032h %04h",job,mem_req_addr-ACC_BASE,mem_req_data,mem_req_strb);
            end else begin reads=reads+1; all_reads=all_reads+1; end
            outstanding=1; outstanding_write=mem_req_write; outstanding_tag=mem_req_tag;
            read_expected=expected[127:0]; sequence_number=sequence_number+1; cursor=cursor+1;
        end
        if(done && (outstanding || acknowledgements!=expected_writes || cursor!=start_index+count))
            $fatal(1,"Layer completed before final verified write");
    end
end
initial begin
    #1;
    $readmemh("output/initial.hex",model.memory,0,MEMORY_WORDS-1);
    $readmemh("output/golden.hex",golden);
    $readmemh("output/transactions.hex",transactions);
    $readmemh("output/descriptors.hex",descriptors);
    jobs_file=$fopen("output/jobs.txt","r");
    output_file=$fopen("output/native_layer_outputs.txt","w");
    cycle_file=$fopen("output/native_layer_cycles.txt","w");
    if(!jobs_file || !output_file || !cycle_file) $fatal(1,"Open integrated vectors failed");
    common_reset;
    for(job=0;job<CASES;job=job+1) begin
        scan=$fscanf(jobs_file,"%d %d %d %d %d %d\n",start_index,count,expected_reads,expected_writes,expected_tiles,expected_padding);
        if(scan!=6 || cursor!=start_index) $fatal(1,"Integrated metadata mismatch");
        descriptor=descriptors[job];
        for(word=1;word<=6;word=word+1)
            descriptor[word*32+:32]=descriptor[word*32+:32]+ACC_BASE;
        reads=0; writes=0; acknowledgements=0; sequence_number=0; started=cycles;
        @(negedge clk); #2;
        if(!cfg_ready || !idle) $fatal(1,"Integrated engine not idle");
        cfg_descriptor=descriptor; cfg_valid=1;
        video_quota=(job+1)*4; video_stress=1;
        @(negedge clk); #2; cfg_valid=0;
        waits=0;
        while(!done && waits<4000000) begin @(negedge clk); #2; waits=waits+1; end
        if(!done || result_job_id!==descriptors[job][31:0] ||
            reads!=expected_reads || writes!=expected_writes) $fatal(1,"Integrated job failed");
        $fdisplay(cycle_file,"%0d %0d %0d %0d",job,cycles-started,reads,writes);
        $display("NATIVE_LAYER_PASS job=%0d cycles=%0d reads=%0d writes=%0d",job,cycles-started,reads,writes);
        @(negedge clk); #2;
    end
    for(index=0;index<MEMORY_WORDS;index=index+1)
        if(model.memory[index]!==golden[index]) $fatal(1,"Integrated final memory/canary mismatch index=%0d",index);
    if(video_reads==0 || video_writes==0 || model.commit_pending) $fatal(1,"No video traffic or uncommitted final write");
    $fclose(jobs_file); $fclose(output_file); $fclose(cycle_file);
    count_file=$fopen("output/layer_counts.txt","w");
    $fdisplay(count_file,"%0d %0d %0d %0d %0d %0d %0d %0d %0d",CASES,output_bytes,all_reads,
        all_writes,MEMORY_WORDS,video_reads,video_writes,native_commands,cycles);
    $fclose(count_file);
    $display("PASS: native layer %0d jobs %0d exact bytes %0d memory words",CASES,output_bytes,MEMORY_WORDS);
    $finish;
end
endmodule
