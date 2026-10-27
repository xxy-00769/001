`timescale 1ns/1ps
module capture_status_tb;
    localparam W=16, H=4;
    reg ref_clk=0, video_clk=0, ref_run=1, video_run=1;
    always #7 if (ref_run) ref_clk=~ref_clk; else ref_clk=0;
    always #5 if (video_run) video_clk=~video_clk; else video_clk=0;
    reg rst_n=0, ready=0, vs=0, de=0, display_vs=0;
    wire pipeline_rst_n, healthy, timed_out, snapshot_valid, show_video;
    wire [31:0] timeout_count;
    wire [255:0] snapshot;
    video_capture_status #(.H_ACTIVE(W),.V_ACTIVE(H),.SOURCE_ID(2),
        .REF_HZ(100000),.TIMEOUT_MS(2500)) dut (
        .ref_clk(ref_clk),.video_clk(video_clk),.rst_n(rst_n),
        .source_ready(ready),.video_vs(vs),.video_de(de),
        .pipeline_rst_n(pipeline_rst_n),.healthy(healthy),
        .timed_out(timed_out),.timeout_count(timeout_count),
        .snapshot_valid(snapshot_valid),.snapshot(snapshot)
    );
    video_present_guard guard (
        .clk(ref_clk),.rst_n(rst_n),.healthy(healthy),
        .vs(display_vs),.show_video(show_video)
    );
    integer checks=0, reports=0, expected_id=0, fd;
    reg [255:0] latest;
    reg [31:0] last_timestamp=0;
    always @(posedge ref_clk) begin
        #1;
        if (rst_n && snapshot_valid) begin
            latest=snapshot;
            reports=reports+1;
            $fdisplay(fd,"%0d,%0d,%0d,%0d,%0h,%0d,%0d,%0d",
                snapshot[31:0],snapshot[63:32],snapshot[95:64],
                snapshot[111:96],snapshot[119:112],snapshot[159:128],
                snapshot[191:160],snapshot[223:192]);
        end
    end
    task check(input bit condition, input string label_text);
        begin
            if (!condition) $fatal(1,"CHECK FAILED: %s",label_text);
            checks=checks+1;
        end
    endtask
    task idle(input integer n);
        repeat(n) @(negedge video_clk);
    endtask
    task sof(input bit collide);
        begin
            vs=1; de=collide;
            idle(3);
            vs=0; de=0;
        end
    endtask
    task line(input integer length, input bit blank_after);
        begin
            @(negedge video_clk);
            de=1;
            idle(length);
            de=0;
            if (blank_after) idle(3);
        end
    endtask
    task raster(input integer count_rows);
        integer r;
        for(r=0;r<count_rows;r=r+1) line(W,1);
    endtask
    task close_check(input integer count_pixels, input integer count_rows,
                     input [7:0] error_bits, input bit collide);
        integer before_count,k;
        begin
            before_count=reports;
            sof(collide);
            k=0;
            while(reports==before_count && k<100) begin
                @(negedge ref_clk); k=k+1;
            end
            check(reports==before_count+1,"one report per closing boundary");
            check(latest[31:0]==expected_id,"monotonic source frame ID");
            check(latest[95:64]==count_pixels,"exact pixel count");
            check(latest[111:96]==count_rows,"exact DE segment count");
            check(latest[119:112]==error_bits,"exact error bitmap");
            check(latest[127:120]==2,"source/channel tag");
            check(latest[63:32]>=last_timestamp,"monotonic timestamp");
            check(healthy==(error_bits==0),"health matches report validity");
            last_timestamp=latest[63:32];
            expected_id=expected_id+1;
            idle(8); // Let this boundary deassert and its mailbox acknowledge.
        end
    endtask
    task display_boundary;
        begin
            @(negedge ref_clk); display_vs=1;
            repeat(2) @(negedge ref_clk);
            display_vs=0;
            repeat(2) @(negedge ref_clk);
        end
    endtask
    task wait_timeout(input integer total);
        integer k;
        begin
            k=0;
            while(!timed_out && k<300000) begin
                @(negedge ref_clk); k=k+1;
            end
            check(timed_out,"independent watchdog expires");
            check(timeout_count==total,"one count per timeout episode");
            check(!healthy && !pipeline_rst_n,"fault inhibits processing");
            repeat(10) @(negedge ref_clk);
            check(!show_video,"fault blanks display without removing sync");
        end
    endtask
    integer i, before_reports, before_timeout;
    reg [255:0] held_mailbox;
    initial begin
        fd=$fopen("frames.csv","w");
        if(!fd) $fatal(1,"Cannot create evidence");
        $fdisplay(fd,"id,time_ms,pixels,rows,errors,good,bad,mailbox_drops");
        idle(10);
        check(!pipeline_rst_n && !show_video,"reset inhibits pipeline/display");
        rst_n=1; idle(8);
        check(!pipeline_rst_n,"unconfigured camera stays reset");
        ready=1; idle(8);
        check(pipeline_rst_n && !healthy,"ready releases pipeline, not health");
        sof(0); idle(3);
        check(reports==0,"first VS opens, does not complete a frame");
        raster(H); close_check(W*H,H,0,0);
        repeat(4) @(negedge ref_clk);
        display_boundary();
        check(!show_video,"first output boundary remains blank");
        display_boundary();
        check(show_video,"second output boundary resumes display");
        raster(H); close_check(W*H,H,0,0);
        line(W-1,1); raster(H-1); close_check(W*H-1,H,8'h01,0);
        repeat(5) @(negedge ref_clk);
        check(!show_video,"malformed row blanks display");
        line(W+1,1); raster(H-1); close_check(W*H+1,H,8'h01,0);
        line(W-1,1); line(W+1,1); raster(H-2);
        close_check(W*H,H,8'h01,0); // Same pixel total is not enough.
        raster(H-1); close_check(W*(H-1),H-1,8'h02,0);
        raster(H+1); close_check(W*(H+1),H+1,8'h02,0);
        raster(1); close_check(W,1,8'h02,0); // Early VS.
        close_check(0,0,8'h02,0); // Repeated empty frame.
        raster(H); close_check(W*H,H,8'h04,1);
        raster(H); close_check(W*H,H,8'h04,0); // Colliding next SOF.
        raster(H-1); line(W,0);
        close_check(W*H,H,0,0); // Last row ends on VS itself.
        before_reports=reports;
        vs=1; idle(20); vs=0; idle(3);
        // A held VS only gives one new edge, therefore one empty report.
        repeat(8) @(negedge ref_clk);
        check(reports==before_reports+1,"held VS is not repeated frames");
        expected_id=expected_id+1;
        line(70000,1); raster(H-1);
        close_check(70000+W*(H-1),H,8'h09,0);
        for(i=0;i<65535;i=i+1) line(1,1);
        line(1,0); // Row 65536 closes on VS, not in the ordinary DE-fall path.
        close_check(65536,65535,8'h0b,0);
        // A stopped video clock cannot stop the reference-domain watchdog.
        line(W,1);
        video_run=0;
        wait_timeout(1);
        check(video_clk==0,"pixel clock really stopped");
        video_run=1; idle(10);
        check(!pipeline_rst_n,"clock restart alone cannot clear timeout");
        close_check(W,1,8'h12,0);
        idle(10);
        check(pipeline_rst_n && !timed_out,"returning boundary clears watchdog");
        raster(H); close_check(W*H,H,8'h10,0);
        raster(H); close_check(W*H,H,0,0);
        // Pixel clock active but no new frame boundary.
        de=0;
        wait_timeout(2);
        close_check(0,0,8'h12,0);
        raster(H); close_check(W*H,H,8'h10,0);
        raster(H); close_check(W*H,H,0,0);
        check(latest[63:32]>0,"timestamp advances in free-running domain");
        // Exercise a slow status consumer: mailbox must stay frozen, and
        // dropped reports cannot stall input or corrupt later counters.
        @(negedge ref_clk); ref_run=0;
        raster(H); sof(0);
        held_mailbox=dut.mailbox;
        repeat(5) begin idle(2); sof(0); end
        check(dut.mailbox===held_mailbox,"pending bundled data stays immutable");
        ref_run=1;
        repeat(12) @(negedge ref_clk);
        idle(12); raster(H); sof(0);
        repeat(12) @(negedge ref_clk);
        check(latest[223:192]>=5,"mailbox drops explicitly counted");
        check(latest[31:0]==expected_id+6,"IDs reveal omitted metadata reports");
        expected_id=latest[31:0]+1;
        // Source disable mid-frame cancels it; stale status cannot show video.
        line(W,1); ready=0; idle(8);
        repeat(8) @(negedge ref_clk);
        check(!healthy && !pipeline_rst_n,"source disable clears health/reset");
        before_reports=reports; ready=1; idle(10); sof(0);
        repeat(8) @(negedge ref_clk);
        check(reports==before_reports,"re-enable waits for a fresh frame");
        raster(H); close_check(W*H,H,0,0);
        // Global reset midway through pixels starts a new ID/time epoch.
        de=1; idle(7); rst_n=0; idle(8); de=0; vs=0;
        check(!healthy && !timed_out && timeout_count==0,"reset clears statistics");
        expected_id=0; last_timestamp=0;
        rst_n=1; idle(10); sof(0); raster(H); close_check(W*H,H,0,0);
        check(latest[159:128]==1 && latest[191:160]==0,"reset counter epoch");
        $display("CAPTURE_STATUS_RESULT checks=%0d reports=%0d errors=0",checks,reports);
        $fclose(fd);
        $finish;
    end
    initial begin #20000000; $fatal(1,"Test timed out"); end
endmodule
