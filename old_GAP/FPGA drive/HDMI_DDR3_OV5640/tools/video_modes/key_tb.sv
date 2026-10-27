`timescale 1ns/1ps
module video_modes_key_tb;
    reg ref_clk=0, video_clk=0, rst_n=0, video_rst_n=0, key_n=1;
    always #10 ref_clk=~ref_clk;
    always #13.468 video_clk=~video_clk;
    wire [2:0] requested_mode;
    video_mode_key #(.STABLE_CYCLES(8)) dut(.*);
    integer checks=0, i;
    reg [2:0] gray_before;
    always @(negedge ref_clk) begin
        if (rst_n && dut.mode_gray != gray_before &&
            ((dut.mode_gray ^ gray_before) & ((dut.mode_gray ^ gray_before)-1)) != 0)
            $fatal(1,"Gray ring changed more than one bit");
        gray_before=dut.mode_gray;
    end
    task cycles(input integer n);
        repeat(n) @(negedge ref_clk);
    endtask
    task expect_mode(input integer mode);
        begin
            cycles(12);
            if(requested_mode !== mode) $fatal(1,"Mode got %d expected %d",requested_mode,mode);
            checks=checks+1;
        end
    endtask
    task press;
        begin
            key_n=0; cycles(2); key_n=1; cycles(2); key_n=0; cycles(2);
            key_n=1; cycles(2); key_n=0; cycles(24);
        end
    endtask
    task release_key;
        begin
            key_n=1; cycles(2); key_n=0; cycles(2); key_n=1; cycles(24);
        end
    endtask
    initial begin
        cycles(5); rst_n=1; video_rst_n=1;
        expect_mode(0);
        key_n=0; cycles(2); key_n=1; expect_mode(0);
        for(i=1;i<=12;i=i+1) begin
            press(); expect_mode(i%6);
            cycles(200); expect_mode(i%6); // no auto-repeat on long hold
            key_n=1; cycles(2); key_n=0; expect_mode(i%6); // release bounce
            release_key(); expect_mode(i%6);
        end
        press(); expect_mode(1);
        video_rst_n=0; cycles(8);
        if(requested_mode!==0) $fatal(1,"Video reset did not clear receiver");
        video_rst_n=1; expect_mode(1); // selected request survives capture recovery
        rst_n=0; video_rst_n=0; cycles(8);
        rst_n=1; video_rst_n=1;
        expect_mode(0); cycles(100); expect_mode(0); // held during reset, not armed
        release_key(); press(); expect_mode(1);
        $display("KEY_RESULT checks=%0d errors=0",checks);
        $finish;
    end
    initial begin #1000000; $fatal(1,"Key test timeout"); end
endmodule
