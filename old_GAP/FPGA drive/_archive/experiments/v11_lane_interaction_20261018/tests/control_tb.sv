`timescale 1ns/1ps
module control_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, result_valid=0;
    reg [255:0] snapshot=0;
    reg [3:0] pressed=0;
    wire fresh, alarm;
    wire [1:0] requested_direction, effective_direction, decision;
    wire [15:0] source_frame, rejected_results;
    lane_change_control #(.STALE_CYCLES(20),.COMMAND_CYCLES(8)) dut(.*);
    integer checks=0, l, r, cmd, expected_kind;
    task tick;
        begin @(posedge clk); #1; checks=checks+1; end
    endtask
    task reset;
        begin @(negedge clk); rst_n=0; pressed=0; result_valid=0;
            tick; @(negedge clk); rst_n=1; end
    endtask
    task send(input [15:0] id, input [1:0] left_type, right_type, input [7:0] flags);
        begin @(negedge clk); snapshot=0;
            snapshot[31:16]=id; snapshot[9:8]=left_type;
            snapshot[11:10]=right_type; snapshot[7:0]=flags;
            result_valid=1; tick; @(negedge clk); result_valid=0;
        end
    endtask
    task key(input [3:0] bits);
        begin @(negedge clk); pressed=bits; tick; @(negedge clk); pressed=0; end
    endtask
    task expect_state(input [1:0] req, eff, dec, input valid_now, alarm_now);
        begin
            if ({requested_direction,effective_direction,decision,fresh,alarm} !==
                {req,eff,dec,valid_now,alarm_now})
                $fatal(1,"state got %d %d %d %b %b expected %d %d %d %b %b",
                    requested_direction,effective_direction,decision,fresh,alarm,
                    req,eff,dec,valid_now,alarm_now);
        end
    endtask
    initial begin
        // Every lane-kind pair and simultaneous command combination.
        for(l=0;l<4;l=l+1) for(r=0;r<4;r=r+1) for(cmd=0;cmd<16;cmd=cmd+1) begin
            reset; send(100,l,r,8'h47); key(cmd);
            if ((l!=1 && l!=2) || (r!=1 && r!=2)) expect_state(0,0,0,0,0);
            else if (cmd[3] || (&cmd[1:0]) || !(|cmd[1:0])) expect_state(0,0,1,1,0);
            else begin
                expected_kind=cmd[0] ? l:r;
                expect_state(cmd[0]?1:2,expected_kind==2?(cmd[0]?1:2):0,
                    expected_kind==2?2:3,1,expected_kind==1 && cmd[2]);
            end
        end
        reset; send(65534,1,2,8'h47); key(1); expect_state(1,0,3,1,0);
        key(4); expect_state(1,0,3,1,1);
        key(8); expect_state(0,0,1,1,0);
        key(4); expect_state(0,0,1,1,0);
        send(65535,2,1,8'h47); send(0,2,1,8'h47);
        if(source_frame!==0) $fatal(1,"frame wrap");
        send(0,1,1,8'h47); send(65535,1,1,8'h47); send(32768,1,1,8'h47);
        if(source_frame!==0 || rejected_results!==3) $fatal(1,"sequence rejection");
        key(1); expect_state(1,1,2,1,0);
        // Refresh snapshots without extending the pending command TTL.
        for(cmd=1;cmd<=5;cmd=cmd+1) send(cmd,2,1,8'h47);
        expect_state(0,0,1,1,0);
        key(1); send(6,2,1,8'h67); expect_state(0,0,0,0,0);
        send(7,2,1,8'h46); expect_state(0,0,0,0,0);
        send(8,2,1,8'h47); key(1); expect_state(1,1,2,1,0);
        repeat(25) tick;
        expect_state(0,0,0,0,0);
        send(8,2,1,8'h47); expect_state(0,0,0,0,0);
        send(7,2,1,8'h47); expect_state(0,0,0,0,0);
        send(9,2,1,8'h47); expect_state(0,0,1,1,0);
        // Exact freshness boundary and repeated duplicates do not refresh age.
        reset; send(10,2,2,8'h47);
        repeat(19) tick;
        expect_state(0,0,1,1,0);
        tick; expect_state(0,0,0,0,0);
        reset; send(10,2,2,8'h47);
        repeat(12) send(10,2,2,8'h47);
        expect_state(0,0,0,0,0);
        reset; expect_state(0,0,0,0,0);
        $display("PASS control: 256 lane/command combinations, freshness, wrap, invalid, TTL; ticks=%0d",checks);
        $finish;
    end
    initial begin #1000000; $fatal(1,"control timeout"); end
endmodule
