`timescale 1ns/1ps
module layer0_tb;
parameter CASES = 575;
reg clk=0;
always #5 clk=~clk;
reg rst_n=0;
reg load_valid=0, start_valid=0, out_ready=0;
reg [9:0] load_addr=0;
reg [7:0] load_data=0;
wire load_ready, start_ready, busy, fault, done, out_valid;
wire [9:0] out_index;
wire [7:0] out_data;
wire signed [31:0] out_acc;
reg [7:0] tiles [0:CASES*867-1];
reg [39:0] expected [0:CASES*1024-1];
integer output_file, stats_file, c, k, total=0, jobs=0;
reg [49:0] saved;
layer0_tile dut(.*);

task reset_dut;
begin
    @(negedge clk);
    rst_n=0; load_valid=0; start_valid=0; out_ready=0;
    repeat(3) @(negedge clk);
    rst_n=1;
    @(negedge clk);
    if(busy || out_valid || start_ready || fault || !load_ready) $fatal(1,"Reset state invalid");
end
endtask

task load_tile(input integer number);
integer a;
begin
    for(a=0;a<867;a=a+1) begin
        @(negedge clk);
        if(!load_ready) $fatal(1,"Input not ready case=%0d addr=%0d",number,a);
        load_valid=1; load_addr=a; load_data=tiles[number*867+a];
        if(a%11==5) begin
            @(negedge clk);
            load_valid=0;
        end
    end
    @(negedge clk);
    load_valid=0;
    if(!start_ready || load_ready || fault) $fatal(1,"Incomplete or faulted loaded tile");
    // A write while not ready must not corrupt the complete snapshot.
    load_valid=1; load_addr=867; load_data=8'hff;
    repeat(3) @(negedge clk);
    load_valid=0;
    if(!start_ready || fault) $fatal(1,"Blocked extra input changed state");
end
endtask

task launch;
begin
    @(negedge clk);
    if(!start_ready) $fatal(1,"Launch not ready");
    start_valid=1;
    @(negedge clk);
    start_valid=0;
    if(!busy || start_ready || load_ready) $fatal(1,"Launch did not protect tile");
end
endtask

task run_job(input integer number);
integer n,cycles,stalls;
reg held;
reg [49:0] held_value;
begin
    launch();
    n=0; cycles=0; stalls=0; held=0;
    load_valid=1; load_addr=0; load_data=8'hff;
    start_valid=1;
    out_ready=1;
    while(n<1024) begin
        @(posedge clk);
        if(fault || load_ready || start_ready) $fatal(1,"Busy state allowed overwrite/restart");
        if(held && (!out_valid || {out_index,out_acc,out_data} !== held_value))
            $fatal(1,"Output changed under backpressure");
        if(out_valid && out_ready) begin
            if(out_index !== n[9:0] || {out_acc,out_data} !== expected[number*1024+n])
                $fatal(1,"Mismatch case=%0d n=%0d idx=%0d got=%08x%02x expected=%010x",number,n,out_index,out_acc,out_data,expected[number*1024+n]);
            $fdisplay(output_file,"%0d %0d %08x %02x",number,n,out_acc,out_data);
            n=n+1; total=total+1;
        end
        held=out_valid && !out_ready;
        held_value={out_index,out_acc,out_data};
        if(held) stalls=stalls+1;
        @(negedge clk);
        cycles=cycles+1;
        out_ready=(cycles%17>2 && cycles%53>4);
        if(cycles>80000) $fatal(1,"Job timeout");
    end
    out_ready=0; load_valid=0; start_valid=0;
    if(!done || busy || out_valid || start_ready || !load_ready) $fatal(1,"Completion handshake invalid");
    jobs=jobs+1;
    $fdisplay(stats_file,"%0d %0d %0d %0d",number,cycles,n,stalls);
end
endtask

initial begin
    $readmemh("output/tiles.hex",tiles);
    $readmemh("output/expected.hex",expected);
    output_file=$fopen("output/rtl_outputs.txt","w");
    stats_file=$fopen("output/rtl_cycles.txt","w");
    if(!output_file || !stats_file) $fatal(1,"Cannot open output files");
    reset_dut();
    // A skipped address faults, blocks start, and cannot expose stale RAM.
    @(negedge clk); load_valid=1; load_addr=1; load_data=4;
    @(negedge clk); load_valid=0;
    if(!fault || start_ready || load_ready) $fatal(1,"Out-of-order load not rejected");
    repeat(5) @(negedge clk);
    reset_dut();
    // A partial tile is never a valid job.
    for(k=0;k<13;k=k+1) begin
        @(negedge clk); load_valid=1; load_addr=k; load_data=tiles[k];
    end
    @(negedge clk); load_valid=0; start_valid=1;
    repeat(10) @(negedge clk);
    if(start_ready || busy || out_valid || fault) $fatal(1,"Partial tile started");
    reset_dut();
    load_tile(0); launch();
    repeat(23) @(negedge clk);
    reset_dut();
    load_tile(0); run_job(0);
    // Abort while a produced output is stalled, then recapture the next tile.
    load_tile(0); launch();
    while(!out_valid) @(negedge clk);
    saved={out_index,out_acc,out_data};
    repeat(13) begin
        @(negedge clk);
        if(!out_valid || {out_index,out_acc,out_data} !== saved) $fatal(1,"Long hold unstable");
    end
    reset_dut();
    for(c=0;c<CASES;c=c+1) begin
        load_tile(c); run_job(c);
        if(c%50==0) $display("Progress %0d/%0d tiles",c,CASES);
    end
    if(total != (CASES+1)*1024 || jobs != CASES+1) $fatal(1,"Wrong total");
    $fclose(output_file); $fclose(stats_file);
    $display("PASS: %0d jobs, %0d bit-exact outputs; stalls, reset, incomplete and out-of-order input",jobs,total);
    $finish;
end
initial begin
    #1000000000;
    $fatal(1,"Global watchdog");
end
endmodule
