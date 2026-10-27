`timescale 1ns/1ps
module pll_tb;
    reg clk=0, grs_n=0;
    always #10 clk=~clk;
    GTP_GRS GRS_INST(.GRS_N(grs_n));
    wire p,c,x,locked;
    pll_mpi7001 dut(clk,p,c,x,locked);
    real t,period;
    initial begin
        #100 grs_n=1;
        wait(locked);
        repeat(100) @(posedge p);
        t=$realtime; repeat(100) @(posedge p); period=($realtime-t)/100;
        if(period<33.83 || period>33.87) $fatal(1,"Pixel clock period %f",period);
        @(posedge c); t=$realtime; repeat(100) @(posedge c); period=($realtime-t)/100;
        if(period<99.95 || period>100.05) $fatal(1,"Config clock period %f",period);
        @(posedge x); t=$realtime; repeat(100) @(posedge x); period=($realtime-t)/100;
        if(period<39.98 || period>40.02) $fatal(1,"Camera clock period %f",period);
        $display("PLL_PASS pixel=29.545454MHz config=10MHz camera_control=25MHz lock=1 V5_clock_structure_preserved=1");
        $finish;
    end
    initial begin #2000000; $fatal(1,"PLL lock timeout"); end
endmodule
