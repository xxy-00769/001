`timescale 1ns/1ps
module buttons_tb;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg [3:0] key_n=0;
    wire [3:0] pressed, fast_pressed;
    lane_button_events #(.STABLE_CYCLES(4)) dut(.*);
    lane_button_events #(.STABLE_CYCLES(1)) fast(.clk(clk),.rst_n(rst_n),.key_n(key_n),.pressed(fast_pressed));
    integer counts[0:3], fast_counts[0:3], i;
    always @(posedge clk) begin
        #1;
        for(i=0;i<4;i=i+1) begin
            if(pressed[i]) counts[i]=counts[i]+1;
            if(fast_pressed[i]) fast_counts[i]=fast_counts[i]+1;
        end
    end
    task hold(input [3:0] value, input integer cycles);
        begin @(negedge clk); key_n=value; repeat(cycles) @(negedge clk); end
    endtask
    initial begin
        for(i=0;i<4;i=i+1) begin counts[i]=0; fast_counts[i]=0; end
        repeat(3) @(negedge clk); rst_n=1;
        hold(0,20);
        for(i=0;i<4;i=i+1)
            if(counts[i]!=0 || fast_counts[i]!=0) $fatal(1,"held at reset triggered");
        hold(15,12);
        hold(14,1); hold(15,1); hold(14,1); hold(15,8);
        if(counts[0]!=0) $fatal(1,"bounce triggered");
        hold(14,30);
        if(counts[0]!=1) $fatal(1,"press/hold repeat");
        hold(15,10); hold(14,10);
        if(counts[0]!=2) $fatal(1,"rearm");
        hold(8,12);
        if(counts[1]!=1 || counts[2]!=1 || counts[3]!=0) $fatal(1,"independent keys");
        hold(15,12); hold(0,12);
        if(counts[0]!=3 || counts[1]!=2 || counts[2]!=2 || counts[3]!=1)
            $fatal(1,"simultaneous keys");
        rst_n=0; repeat(3) @(negedge clk); rst_n=1; hold(0,12);
        if(counts[0]!=3 || fast_counts[3]!=1) $fatal(1,"reset hold");
        $display("PASS buttons: bounce, hold, release-to-arm, independent/simultaneous, reset, STABLE=1");
        $finish;
    end
    initial begin #100000; $fatal(1,"buttons timeout"); end
endmodule
