`timescale 1ns/1ps
module rule_source_tb;
    reg clk=0, rst_n=0, frame_start=0;
    always #5 clk=~clk;
    wire valid;
    wire [255:0] snapshot;
    lane_rule_test_source #(.FRAMES_PER_SCENE(2)) dut(.*);
    integer i, scene;
    reg [3:0] types;
    initial begin
        repeat(2) @(negedge clk); rst_n=1;
        for(i=0;i<12;i=i+1) begin
            @(negedge clk); frame_start=1; @(posedge clk); #1;
            scene=(i/2)%4;
            case(scene) 0:types=10; 1:types=9; 2:types=6; 3:types=0; endcase
            if(!valid || snapshot[31:16]!==i || snapshot[11:8]!==types ||
                snapshot[7:0] !== (scene==3?8'h40:8'h47))
                $fatal(1,"rule phase/frame %0d",i);
            @(negedge clk); frame_start=0; @(posedge clk); #1;
            if(valid) $fatal(1,"valid not pulsed");
        end
        @(negedge clk); rst_n=0; @(posedge clk); #1;
        if(valid || snapshot!==0) $fatal(1,"rule reset");
        $display("PASS rule_source: four labelled synthetic scenes, frame IDs, idle, reset");
        $finish;
    end
endmodule
