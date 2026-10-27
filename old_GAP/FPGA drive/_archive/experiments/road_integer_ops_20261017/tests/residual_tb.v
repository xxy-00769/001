`timescale 1ns/1ps
module residual_tb;
`include "output/residual_params.vh"
reg clk=0;
always #5 clk=~clk;
reg rst_n=0, cfg_valid=0, in_valid=0, out_ready=0;
reg [16:0] cfg_count=0;
reg signed [47:0] cfg_gain_a=0, cfg_gain_b=0;
reg signed [63:0] cfg_offset=0;
reg [7:0] in_a=0, in_b=0;
wire cfg_ready, in_ready, out_valid, out_last, busy, done, fault;
wire [7:0] out_data;
reg [7:0] expected[0:65535];
integer sent, received, cycles, k, stalls=0;
reg held, accepted;
reg [8:0] held_value;
residual_requant dut(.*);
task reset_dut;
begin
    @(negedge clk); rst_n=0; cfg_valid=0; in_valid=0; out_ready=0;
    repeat(3) @(negedge clk);
    rst_n=1;
    @(negedge clk);
    if(!cfg_ready || in_ready || out_valid || busy || fault || done) $fatal(1,"Bad residual reset");
end
endtask
task configure(input integer count);
begin
    @(negedge clk); cfg_count=count; cfg_gain_a=GA; cfg_gain_b=GB; cfg_offset=OFFSET; cfg_valid=1;
    @(negedge clk); cfg_valid=0;
end
endtask
initial begin
    $readmemh("output/residual_expected.hex",expected);
    reset_dut(); configure(0);
    if(!fault || cfg_ready || in_ready) $fatal(1,"Zero residual length accepted");
    reset_dut(); configure(65537);
    if(!fault || cfg_ready || in_ready) $fatal(1,"Oversize residual accepted");
    reset_dut(); configure(1);
    in_valid=1; in_a=255; in_b=255;
    @(negedge clk); in_valid=0;
    while(!out_valid) @(negedge clk);
    repeat(20) begin
        @(negedge clk);
        if(!out_valid || !out_last || done || !busy || in_ready || cfg_ready) $fatal(1,"Final result not held");
    end
    reset_dut(); configure(65536);
    sent=0; received=0; cycles=0; held=0; accepted=0;
    // Changed coefficients while busy must be ignored, including the last output.
    cfg_valid=1; cfg_count=1; cfg_gain_a=-GA; cfg_gain_b=-GB; cfg_offset=0;
    while(received<65536) begin
        @(negedge clk);
        if(!in_valid || accepted) begin
            in_valid=sent<65536 && cycles%13!=3;
            in_a=(sent>>8)&255; in_b=sent&255;
        end
        out_ready=cycles%19>3;
        @(posedge clk);
        if(fault || cfg_ready) $fatal(1,"Residual accepted new configuration");
        if(held && (!out_valid || {out_last,out_data} !== held_value)) $fatal(1,"Residual changed under backpressure");
        accepted=in_valid && in_ready;
        if(accepted) sent=sent+1;
        if(out_valid && out_ready) begin
            if(out_data !== expected[received] || out_last !== (received==65535))
                $fatal(1,"Residual mismatch n=%0d got=%0d expected=%0d",received,out_data,expected[received]);
            received=received+1;
        end
        held=out_valid && !out_ready; held_value={out_last,out_data};
        if(held) stalls=stalls+1;
        cycles=cycles+1;
        if(cycles>200000) $fatal(1,"Residual timeout");
    end
    @(negedge clk); in_valid=0; cfg_valid=0; out_ready=0;
    if(!done || busy || out_valid || sent!=65536 || stalls==0) $fatal(1,"Bad residual completion");
    for(k=0;k<2;k=k+1) begin
        @(negedge clk);
        if(!cfg_ready) $fatal(1,"Cannot reconfigure residual");
        cfg_valid=1; cfg_count=1;
        cfg_gain_a=k==0 ? (48'sd1 <<< 36) : 0;
        cfg_gain_b=k==0 ? 0 : -(48'sd1 <<< 36);
        cfg_offset=k==0 ? 0 : (64'sd255 <<< 36);
        @(negedge clk); cfg_valid=0; in_valid=1; in_a=37; in_b=73;
        @(negedge clk); in_valid=0;
        while(!out_valid) @(negedge clk);
        if(out_data !== (k==0 ? 8'd37 : 8'd182) || !out_last) $fatal(1,"Old residual coefficients reused");
        out_ready=1;
        @(negedge clk); out_ready=0;
        if(!done || busy) $fatal(1,"Residual reconfiguration did not finish");
    end
    $display("PASS: residual 65536 exhaustive pairs, 2 reconfiguration outputs, %0d held cycles",stalls);
    $finish;
end
initial begin #3000000; $fatal(1,"Global residual watchdog"); end
endmodule
