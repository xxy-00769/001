`timescale 1ns/1ps
module cdc_tb;
    reg reset_n=0, src_clk=0, dst_clk=0, run_src=1, run_dst=1, src_valid=0;
    always #7 if(run_src) src_clk=~src_clk;
    always #5 if(run_dst) dst_clk=~dst_clk;
    reg [255:0] src_snapshot=0;
    wire src_busy, dst_valid;
    wire [15:0] dropped;
    wire [255:0] dst_snapshot;
    lane_snapshot_cdc dut(.*);
    reg [255:0] expected[0:31];
    integer sent=0, received=0, i;
    always @(posedge dst_clk) begin
        #1;
        if(reset_n && dst_valid) begin
            if(received>=sent || dst_snapshot!==expected[received])
                $fatal(1,"CDC payload/duplicate at %d",received);
            received=received+1;
        end
    end
    task offer(input [255:0] value);
        begin @(negedge src_clk); src_snapshot=value; src_valid=1;
            if(!src_busy) begin expected[sent]=value; sent=sent+1; end
            @(negedge src_clk); src_valid=0; src_snapshot=~value;
        end
    endtask
    task idle;
        begin wait(!src_busy); repeat(2) @(negedge src_clk); end
    endtask
    initial begin
        repeat(3) @(negedge dst_clk); reset_n=1; idle;
        for(i=0;i<16;i=i+1) begin
            offer({8{32'h12345678+i}}); idle;
        end
        if(received!=16) $fatal(1,"CDC missing samples");
        @(negedge dst_clk); run_dst=0;
        offer(256'habc);
        repeat(3) offer(256'hbad);
        if(dropped!=3) $fatal(1,"busy drop count");
        run_dst=1; idle;
        offer(256'h123); @(negedge src_clk); run_src=0;
        repeat(12) @(negedge dst_clk);
        if(received!=sent) $fatal(1,"held payload source stopped");
        run_src=1; idle;
        // Abort an in-flight request while the destination clock is stopped.
        @(negedge dst_clk); run_dst=0; offer(256'hdead);
        reset_n=0; sent=0; received=0;
        repeat(4) @(negedge src_clk);
        reset_n=1; run_dst=1; idle;
        if(received!=0 || dropped!=0) $fatal(1,"reset leaked request");
        offer(256'hbeef); idle;
        if(received!=1) $fatal(1,"reset recovery");
        $display("PASS cdc: asynchronous clocks, 16 payloads, busy drops, stopped clocks, common reset/recovery");
        $finish;
    end
    initial begin #100000; $fatal(1,"CDC timeout"); end
endmodule
