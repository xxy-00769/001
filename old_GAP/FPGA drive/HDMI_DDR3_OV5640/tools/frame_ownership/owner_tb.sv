`timescale 1ns/1ps
module ownership_owner_tb;
    reg clk=0, video_clk=0;
    always #5 clk=~clk;
    always #11 video_clk=~video_clk;
    reg rst_n=0, running=1, vs=0, de=0, result_valid=0;
    reg [31:0] id=0, result_id=0;
    reg [7:0] result_errors=0;
    reg line_event=0, write_request=0, write_done=0;
    reg output_sof=0, read_request=0, read_done=0;
    wire writer_vs, writer_de, writer_rst_n, write_issue, read_issue;
    wire write_bank, read_bank, read_enabled, has_frame;
    wire [31:0] published, rejected, faults, display_id;
    frame_buffer_owner #(.H_NUM(32), .V_NUM(2)) dut (
        .clk(clk), .rst_n(rst_n), .video_clk(video_clk), .pipeline_running(running),
        .video_vs(vs), .video_de(de), .video_id(id), .video_time(id*10),
        .result_valid(result_valid), .result_id(result_id), .result_errors(result_errors),
        .writer_rst_n(writer_rst_n), .writer_vs(writer_vs), .writer_de(writer_de),
        .line_event(line_event), .write_request(write_request),
        .write_ready(1'b1), .write_done(write_done),
        .write_issue(write_issue), .write_bank(write_bank),
        .output_sof(output_sof), .read_request(read_request), .read_ready(1'b1),
        .read_done(read_done), .read_issue(read_issue),
        .read_bank(read_bank), .read_enabled(read_enabled), .has_frame(has_frame),
        .published_count(published), .rejected_count(rejected),
        .read_fault_count(faults), .display_id(display_id)
    );
    integer checks=0;
    task check(input bit condition, input [511:0] description);
        begin
            checks=checks+1;
            if(!condition) $fatal(1,"OWNER_CHECK: %s",description);
        end
    endtask
    always @(posedge clk) if(rst_n) begin
        if(dut.write_busy && !writer_rst_n)
            $fatal(1,"Isolated reset during native write");
        if(write_issue && ((dut.have_reader && write_bank==read_bank) ||
            (dut.pending && write_bank==dut.pending_bank)))
            $fatal(1,"Bank ownership violation");
    end
    task start_frame(input integer tag);
        begin
            repeat(50) @(negedge video_clk);
            id=tag; vs=1; @(negedge video_clk); vs=0;
            check(dut.active,"Frame accepted after grant");
        end
    endtask
    task geometry;
        integer y;
        begin
            for(y=0;y<2;y=y+1) begin
                de=1; repeat(32) @(negedge video_clk);
                de=0; repeat(10) @(negedge video_clk);
            end
        end
    endtask
    task close_frame(input integer tag, input integer errors);
        begin
            @(negedge video_clk); result_id=tag; result_errors=errors; result_valid=1;
            @(negedge video_clk); result_valid=0;
            repeat(60) @(negedge clk);
        end
    endtask
    task issue_line(input bit finish_line);
        begin
            @(negedge clk); line_event=1;
            @(negedge clk); line_event=0; write_request=1;
            #1; check(write_issue,"Native line command issued");
            @(negedge clk); write_request=0;
            repeat(5) @(negedge clk);
            if(finish_line) begin
                write_done=1; @(negedge clk); write_done=0;
                repeat(5) @(negedge clk);
            end
        end
    endtask
    task boundary;
        begin
            @(negedge clk); output_sof=1;
            @(negedge clk); output_sof=0;
            repeat(5) @(negedge clk);
        end
    endtask
    task read_begin;
        begin
            @(negedge clk); read_request=1;
            #1; check(read_issue,"Read command issued");
            @(negedge clk); read_request=0;
        end
    endtask
    task read_finish;
        begin
            @(negedge clk); read_done=1;
            @(negedge clk); read_done=0;
            repeat(5) @(negedge clk);
        end
    endtask
    initial begin
        repeat(10) @(negedge clk); rst_n=1;
        start_frame(10);
        fork geometry(); begin issue_line(1); issue_line(0); end join
        close_frame(10,0);
        check(published==0 && !has_frame,"Last write still outstanding: no publication");
        write_done=1; @(negedge clk); write_done=0;
        repeat(60) @(negedge clk);
        check(published==1 && has_frame,"Publish after final completion");
        boundary();
        check(read_enabled && read_bank==0 && display_id==10,"First completed frame selected");
        read_begin();
        start_frame(11);
        fork geometry(); begin issue_line(1); issue_line(1); end join
        close_frame(11,0);
        check(published==2 && dut.pending,"Second frame pending while previous read active");
        boundary();
        check(read_bank==0 && display_id==10 && !read_enabled && dut.pending,
            "Busy read at boundary pins old bank, disables output");
        read_finish(); boundary();
        check(read_bank==1 && display_id==11 && read_enabled && !dut.pending,
            "Next safe boundary swaps completed frame");
        boundary();
        check(display_id==11,"No new frame repeats complete frame");

        start_frame(12);
        fork geometry(); begin
            issue_line(0);
            @(negedge clk); line_event=1;
            @(negedge clk); line_event=0; write_request=1;
            #1; check(!write_issue,"Overlapping line cannot issue");
            @(negedge clk); write_request=0;
            write_done=1; @(negedge clk); write_done=0;
        end join
        close_frame(12,0);
        check(published==2 && rejected==1,"Overload rejects entire write frame");
        start_frame(13);
        fork geometry(); begin issue_line(1); issue_line(1); end join
        close_frame(13,1);
        check(published==2 && rejected==2,"Raw geometry error overrides normalized clean pixels");
        start_frame(14);
        issue_line(0);
        @(negedge video_clk); running=0;
        repeat(60) @(negedge clk);
        check(rejected==2 && dut.write_busy,"Abort does not reset an outstanding native write");
        write_done=1; @(negedge clk); write_done=0;
        repeat(60) @(negedge clk);
        check(rejected==3 && published==2,"Abort drains and rejects");
        running=1;
        start_frame(15);
        fork geometry(); begin issue_line(1); issue_line(1); end join
        close_frame(15,0); boundary();
        check(published==3 && display_id==15,"Capture recovers after abort");
        read_begin();
        @(negedge clk); read_request=1;
        @(negedge clk); read_request=0;
        check(!read_enabled && faults==2,"Missed read deadline disables frame");
        read_finish(); boundary();
        check(read_enabled && display_id==15,"Read failure recovers at boundary");
        rst_n=0; repeat(10) @(negedge clk);
        check(!has_frame && !read_enabled && published==0,"DDR reset invalidates ownership");
        rst_n=1;
        start_frame(20);
        fork geometry(); begin issue_line(1); issue_line(1); end join
        close_frame(20,0); boundary();
        check(published==1 && display_id==20,"Fresh frame after DDR reset");
        $display("OWNERSHIP_UNIT_RESULT checks=%0d errors=0",checks);
        $finish;
    end
    initial begin #1000000; $fatal(1,"Owner regression timeout"); end
endmodule
