`timescale 1ns/1ps
module m3_owner_tb;
    reg clk=0, video_clk=0;
    always #5 clk=~clk;
    always #11 video_clk=~video_clk;
    reg acquire=0,release_frame=0;wire net_grant,net_held;wire [1:0] net_bank;wire [31:0] net_id;
    reg rst_n=0, running=1, vs=0, de=0, result_valid=0;
    reg [31:0] id=0, result_id=0;
    reg [7:0] result_errors=0;
    reg line_event=0, write_request=0, write_done=0;
    reg output_sof=0, read_request=0, read_done=0;
    wire writer_vs, writer_de, writer_rst_n, write_issue, read_issue;
    wire [1:0] write_bank,read_bank;wire read_enabled,has_frame;reg selected=1;
    wire [31:0] published, rejected, faults, display_id;
    m3_front_owner #(.H_NUM(32), .V_NUM(2)) dut (
        .net_acquire(acquire),.net_release(release_frame),.net_grant(net_grant),.net_held(net_held),.net_bank(net_bank),.net_id(net_id),
        .clk(clk), .rst_n(rst_n), .video_clk(video_clk), .pipeline_running(running),
        .video_vs(vs), .video_de(de), .video_id(id), .video_time(id*10),
        .result_valid(result_valid), .result_id(result_id), .result_errors(result_errors),
        .writer_rst_n(writer_rst_n), .writer_vs(writer_vs), .writer_de(writer_de),
        .line_event(line_event), .write_request(write_request),
        .write_ready(1'b1), .write_done(write_done),
        .write_issue(write_issue), .write_bank(write_bank),
        .display_selected(selected), .output_sof(output_sof), .read_request(read_request), .read_ready(1'b1),
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
            (dut.pending && write_bank==dut.pending_bank) || (net_held && write_bank==net_bank)))
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
    task pin;begin @(negedge clk);acquire=1;wait(net_grant);@(negedge clk);acquire=0;repeat(5) @(negedge clk);end endtask
    task unpin;begin @(negedge clk);release_frame=1;@(negedge clk);release_frame=0;end endtask
    task capture(input integer tag);begin start_frame(tag);fork geometry();begin issue_line(1);issue_line(1);end join close_frame(tag,0);end endtask
    integer i;reg [1:0] saved_net;
    initial begin
     repeat(10) @(negedge clk);rst_n=1;
     capture(10);boundary();pin();check(net_id==10 && net_bank==read_bank,"same frame held by two readers");
     capture(11);boundary();saved_net=net_bank;
     check(net_id==10 && display_id==11 && net_bank!=read_bank,"independent different slots");
     for(i=12;i<20;i++) begin capture(i);boundary();check(net_bank==saved_net && net_id==10,"slow network retains pin while display progresses");end
     check(published==10,"no permanent capture stall with two readers");
     unpin();pin();$display("owner ids net=%0d display=%0d pending=%0d/%0d",net_id,display_id,dut.pending,dut.pending_id);check(net_id>=19,"network skips to newest completed frame");
     read_begin();@(negedge clk);selected=0;repeat(10) @(negedge clk);
     check(dut.have_reader && net_held,"hidden display pin retained until old command drains");
     read_finish();repeat(10) @(negedge clk);check(!dut.have_reader && net_held,"display release cannot release network");
     capture(20);capture(21);check(published==12,"hidden capture progresses");
     unpin();repeat(10) @(negedge clk);check(!net_held,"abort release");
     selected=1;boundary();capture(22);boundary();check(display_id==22,"display reselect");
     pin();rst_n=0;repeat(10) @(negedge clk);check(!net_held && !has_frame,"restart invalidates both pins");
     $display("M3_OWNER_PASS checks=%0d published_before_reset=13 same_and_different_readers=1 slow_reader_progress=1 abort_restart=1",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"owner timeout");end
endmodule
