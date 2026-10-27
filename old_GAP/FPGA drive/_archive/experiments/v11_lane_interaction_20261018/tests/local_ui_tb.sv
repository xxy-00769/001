`timescale 1ns/1ps
module local_ui_tb;
    reg reset_n=0, src_clk=0, pix_clk=0, run_src=1, src_valid=0, de=0, vs=0;
    always #7 if(run_src) src_clk=~src_clk;
    always #5 pix_clk=~pix_clk;
    reg [255:0] src_snapshot=0;
    reg [3:0] key_n=15;
    reg [15:0] rgb_in=16'h1357;
    wire [15:0] rgb_out, source_frame, dropped_snapshots, rejected_results;
    wire [1:0] requested_direction, effective_direction, decision;
    wire fresh,alarm;
    lane_local_ui #(.H_ACTIVE(400),.V_ACTIVE(80),.DEBOUNCE_CYCLES(3),
        .STALE_CYCLES(100),.COMMAND_CYCLES(300)) camera(.*);
    wire [15:0] test_rgb,test_frame,test_drop,test_reject;
    wire [1:0] test_request,test_effective,test_decision;
    wire test_fresh,test_alarm;
    lane_local_ui #(.H_ACTIVE(400),.V_ACTIVE(80),.RULE_TEST(1),.TEST_FRAMES(1),
        .DEBOUNCE_CYCLES(3),.STALE_CYCLES(100),.COMMAND_CYCLES(300)) rule_test(
        .reset_n(reset_n),.src_clk(src_clk),.src_valid(src_valid),.src_snapshot(src_snapshot),
        .pix_clk(pix_clk),.de(de),.vs(vs),.key_n(key_n),.rgb_in(rgb_in),
        .rgb_out(test_rgb),.requested_direction(test_request),.effective_direction(test_effective),
        .decision(test_decision),.fresh(test_fresh),.alarm(test_alarm),.source_frame(test_frame),
        .dropped_snapshots(test_drop),.rejected_results(test_reject));
    task wait_pixels(input integer n);
        begin repeat(n) @(negedge pix_clk); end
    endtask
    task frame;
        begin @(negedge pix_clk); vs=1; wait_pixels(2); vs=0; wait_pixels(4); end
    endtask
    task key(input [3:0] value);
        begin @(negedge pix_clk); key_n=value; wait_pixels(10); key_n=15; wait_pixels(10); end
    endtask
    task send(input [15:0] id, input [3:0] types, input [7:0] flags);
        begin @(negedge src_clk); src_snapshot=0; src_snapshot[31:16]=id;
            src_snapshot[11:8]=types; src_snapshot[7:0]=flags; src_valid=1;
            @(negedge src_clk); src_valid=0; wait_pixels(14); end
    endtask
    initial begin
        wait_pixels(3); reset_n=1; wait_pixels(10);
        frame; send(100,4'h9,8'h47);
        key(14);
        if(!fresh || decision!=3 || alarm || effective_direction!=0 ||
            test_decision!=2 || test_effective!=1) $fatal(1,"button to lane decision");
        key(11);
        if(!alarm || effective_direction!=0) $fatal(1,"solid force alarm");
        send(101,4'h9,8'h47); frame;
        if(!camera.overlay.shown_alarm || !rule_test.overlay.shown_test ||
            camera.overlay.shown_test) $fatal(1,"control to overlay/mode label");
        key(7);
        if(alarm || requested_direction!=0) $fatal(1,"cancel");
        send(102,4'h6,8'h47); key(13);
        if(decision!=3 || effective_direction!=0) $fatal(1,"right solid");
        send(103,4'h0,8'h40);
        if(fresh || requested_direction!=0 || decision!=0) $fatal(1,"unknown cancels");
        send(104,4'ha,8'h47); key(14);
        if(decision!=2 || effective_direction!=1) $fatal(1,"camera dashed request");
        @(negedge src_clk); run_src=0;
        wait_pixels(110);
        if(fresh || alarm || requested_direction!=0 || effective_direction!=0 || decision!=0)
            $fatal(1,"stopped camera watchdog");
        frame;
        if(camera.overlay.shown_fresh) $fatal(1,"stale display");
        reset_n=0; wait_pixels(4);
        if(rgb_out!==rgb_in) $fatal(1,"reset pass-through");
        run_src=1; reset_n=1; wait_pixels(12); send(0,4'ha,8'h47);
        if(!fresh || source_frame!=0) $fatal(1,"full-reset sequence epoch");
        $display("PASS local_ui: keys -> control -> overlay, real-clock mailbox with synthetic snapshots, RULE TEST, camera-stop timeout, reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"local UI timeout"); end
endmodule
