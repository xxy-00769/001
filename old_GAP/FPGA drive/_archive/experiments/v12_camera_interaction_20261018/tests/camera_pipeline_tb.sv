`timescale 1ns/1ps
module camera_pipeline_tb;
    localparam W=1280,H=720;
    reg src_clk=0,pix_clk=0,run_src=1,reset_n=0,de=0,vs=0,display_vs=0;
    always #7 if(run_src) src_clk=~src_clk;
    always #5 pix_clk=~pix_clk;
    reg [15:0] rgb=0;
    reg [3:0] key_n=15;
    wire src_valid,proc_de,proc_vs;
    wire [15:0] proc_rgb,rgb_out,source_frame,dropped,rejected;
    wire [255:0] snapshot;
    wire [1:0] requested,effective,decision;
    wire fresh,alarm;
    img_proc #(.MODE(4),.ZEBRA_ENABLE(1),.ADAS_ENABLE(1)) camera (
        .clk(src_clk),.rst_n(reset_n),.rgb_in(rgb),.de_in(de),.vs_in(vs),
        .rgb_out(proc_rgb),.de_out(proc_de),.vs_out(proc_vs),
        .adas_valid(src_valid),.adas_snapshot(snapshot));
    lane_local_ui #(.RULE_TEST(0),.DEBOUNCE_CYCLES(3),
        .STALE_CYCLES(2000000),.COMMAND_CYCLES(1000000)) ui (
        .reset_n(reset_n),.src_clk(src_clk),.src_valid(src_valid),
        .src_snapshot(snapshot),.pix_clk(pix_clk),.de(1'b0),.vs(display_vs),
        .key_n(key_n),.rgb_in(16'h1357),.rgb_out(rgb_out),
        .requested_direction(requested),.effective_direction(effective),
        .decision(decision),.fresh(fresh),.alarm(alarm),.source_frame(source_frame),
        .dropped_snapshots(dropped),.rejected_results(rejected));
    reg [31:0] vectors[0:W*H-1];
    reg [255:0] oracle[0:13];
    reg [255:0] expected,held;
    reg [1023:0] path;
    integer results=0,received=0,pixels=0,row,col,old_results;
    always @(posedge src_clk) begin
        #1;
        if(reset_n && src_valid) begin
            if(snapshot!==expected)
                $fatal(1,"camera snapshot got %h expected %h",snapshot,expected);
            results=results+1;
        end
        if(reset_n && proc_de) pixels=pixels+1;
    end
    always @(posedge pix_clk) begin
        #1;
        if(reset_n && ui.g_camera.mailbox.dst_valid) begin
            if(ui.g_camera.mailbox.dst_snapshot!==expected)
                $fatal(1,"atomic image-pipeline mailbox mismatch");
            received=received+1;
        end
        if(reset_n && rgb_out!==16'h1357) $fatal(1,"blanking RGB changed");
    end
    task idle(input integer n);
        begin repeat(n) begin @(negedge src_clk); de=0; rgb=0; end end
    endtask
    task wait_display(input integer n);
        begin repeat(n) @(negedge pix_clk); end
    endtask
    task key(input [3:0] value);
        begin @(negedge pix_clk); key_n=value; wait_display(12);
            key_n=15; wait_display(12); end
    endtask
    task show;
        begin @(negedge pix_clk); display_vs=1; wait_display(2);
            display_vs=0; wait_display(4);
            if(ui.overlay.shown_test) $fatal(1,"synthetic mode on camera build");
        end
    endtask
    task image_frame(input integer fixture,input integer broken);
        begin
            case(fixture)
                0:path="fixtures/frame_00.hex";
                5:path="fixtures/frame_05.hex";
                7:path="fixtures/frame_07.hex";
                default:$fatal(1,"unsupported fixture");
            endcase
            $readmemh(path,vectors);
            expected=broken ? 256'h60 : oracle[fixture];
            expected[31:16]=results+1;
            old_results=results;
            @(negedge src_clk); vs=1; idle(3);
            @(negedge src_clk); vs=0; idle(10000);
            for(row=0;row<H;row=row+1) begin
                for(col=0;col<W-(broken && row==20);col=col+1) begin
                    @(negedge src_clk); de=1; rgb=vectors[row*W+col][31:16];
                end
                idle(1+row%3);
            end
            idle(15000); wait_display(20);
            if(results!=old_results+1 || received!=results || source_frame!=results)
                $fatal(1,"image/mailbox frame count mismatch");
            if(dropped!=0 || rejected!=0) $fatal(1,"unexpected drops/rejects");
            show;
        end
    endtask
    initial begin
        $readmemh("fixtures/snapshots.hex",oracle);
        idle(8); reset_n=1; idle(10);
        image_frame(0,0);
        if(!fresh) $fatal(1,"solid image not usable");
        key(14);
        if(decision!=3 || alarm || effective!=0) $fatal(1,"image solid-left blocking");
        key(11); show;
        if(!alarm || !ui.overlay.shown_alarm) $fatal(1,"image solid alarm");
        key(7);
        if(requested!=0 || alarm) $fatal(1,"cancel");
        image_frame(7,0); key(13);
        if(decision!=2 || effective!=2 || alarm) $fatal(1,"image dashed-right request");
        image_frame(5,0);
        if(fresh || requested!=0 || alarm) $fatal(1,"blank image did not clear");
        image_frame(7,1);
        if(fresh || requested!=0) $fatal(1,"bad frame became usable");
        image_frame(7,0); key(14);
        if(!fresh || effective!=1) $fatal(1,"reacquire dashed-left");
        @(negedge src_clk); run_src=0;
        wait_display(2000010); show;
        if(fresh || requested!=0 || effective!=0 || alarm || ui.overlay.shown_fresh)
            $fatal(1,"stopped camera left live result");
        // A common reset starts a new frame sequence even when source was stopped.
        reset_n=0; wait_display(5); run_src=1; idle(5);
        results=0; received=0; reset_n=1; idle(10);
        image_frame(0,0);
        if(!fresh || source_frame!=1 || alarm) $fatal(1,"common reset/recovery");
        $display("PASS camera_pipeline: 6 full RGB frames, actual img_proc, atomic CDC, solid/dashed keys, blank/bad clearing, source-stop timeout, common reset; synthetic fixtures, NOT hardware recognition acceptance");
        $finish;
    end
    initial begin #180000000; $fatal(1,"camera pipeline timeout"); end
endmodule
