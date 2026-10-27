`timescale 1ns/1ps
module pipeline_tb;
    reg clk=0,vc=0,rst=0,vs=0,de=0;
    always #5 clk=~clk;
    always #13 vc=~vc;
    wire running,rv; wire [31:0] id,time_tag,rid;
    wire [7:0] errors;
    video_capture_status #(.H_ACTIVE(32),.V_ACTIVE(2)) monitor(
        .ref_clk(clk),.video_clk(vc),.rst_n(rst),.source_ready(1'b1),
        .video_vs(vs),.video_de(de),.pipeline_rst_n(running),
        .frame_open_id(id),.frame_open_time(time_tag),
        .frame_result_valid(rv),.frame_result_id(rid),.frame_result_errors(errors));
    wire pv,pd; wire [31:0] pid,pt;
    capture_pipe pipe(.clk(vc),.rst_n(running),.vs(vs),.de(de),.rgb(16'h1234),
        .frame_id(id),.frame_time(time_tag),.out_vs(pv),.out_de(pd),
        .out_id(pid),.out_time(pt),.out_rgb());
    reg request=0,finish=0,line_event=0;
    wire writer_vs,writer_de,issue; wire [31:0] pubs,rejects;
    frame_buffer_owner #(.H_NUM(32),.V_NUM(2)) owner(
        .clk(clk),.rst_n(rst),.video_clk(vc),.pipeline_running(running),
        .video_vs(pv),.video_de(pd),.video_id(pid),.video_time(pt),
        .result_valid(rv),.result_id(rid),.result_errors(errors),
        .writer_vs(writer_vs),.writer_de(writer_de),.writer_rst_n(),
        .line_event(line_event),.write_request(request),.write_ready(1'b1),
        .write_done(finish),.write_issue(issue),.write_bank(),
        .display_selected(1'b1), .output_sof(1'b0),.read_request(1'b0),.read_ready(1'b1),.read_done(1'b0),
        .read_issue(),.read_bank(),.read_enabled(),.has_frame(),.read_completed_gray(),
        .published_count(pubs),.rejected_count(rejects),.read_fault_count(),.display_id(),.display_time());
    reg d1=0,d2=0,d3=0;
    always @(posedge clk) begin
        d1<=writer_de; d2<=d1; d3<=d2;
        line_event<=d3&&!d2;
        request<=line_event;
        finish<=issue;
    end
    initial begin
        #100;rst=1;repeat(100) @(negedge vc);
        vs=1;repeat(8) @(negedge vc);vs=0;
        repeat(20) @(negedge vc);
        repeat(2) begin de=1;repeat(32) @(negedge vc);de=0;repeat(15) @(negedge vc);end
        vs=1;repeat(8) @(negedge vc);vs=0;
        repeat(100) @(negedge vc);
        if(pubs!=1 || rejects!=0) $fatal(1,"pipeline publish=%0d reject=%0d id=%0d end_id=%0d good=%0d lines=%0d/%0d",
            pubs,rejects,owner.active_id,owner.end_id,owner.end_good,owner.issued_lines,owner.completed_lines);
        $display("PIPELINE_PASS published=%0d rejected=%0d",pubs,rejects);$finish;
    end
endmodule
