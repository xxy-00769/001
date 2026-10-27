`timescale 1ns/1ps
module camera_case #(parameter SOURCE=0, parameter HEIGHT=720)(
    output [27:0] awaddr, araddr, output [3:0] awlen, arlen,
    output awvalid, arvalid, output [255:0] wdata,
    input awready,wready,wlast,arready,rvalid,rlast,
    input [255:0] rdata, output reg stall_reads=0, output reg finished=0, output reg bad_capture=0
);
    localparam W=1280, H=HEIGHT, OW=640, OH=HEIGHT/2;

    reg core_clk=0, video_clk=0, out_clk=0;
    always #5 core_clk=~core_clk;
    always #(SOURCE ? 14.7 : 13.468) video_clk=~video_clk;
    always #(SOURCE ? 13.7 : 13.1) out_clk=~out_clk;
    reg rst_n=0, vs=0, de=0;
    reg [15:0] rgb=0;
    wire pipeline_running, clean_vs, clean_de;
    wire [15:0] clean_rgb;
    wire [31:0] open_id, open_time, clean_id, clean_time, result_id;
    wire result_valid;
    wire [7:0] result_errors;
    video_capture_status #(.SOURCE_ID(SOURCE),.H_ACTIVE(W),.V_ACTIVE(H),.REF_HZ(100000000), .TIMEOUT_MS(200)) monitor (
        .ref_clk(core_clk), .video_clk(video_clk), .rst_n(rst_n),
        .source_ready(1'b1), .video_vs(vs), .video_de(de),
        .pipeline_rst_n(pipeline_running),
        .frame_open_id(open_id), .frame_open_time(open_time),
        .frame_result_valid(result_valid), .frame_result_id(result_id),
        .frame_result_errors(result_errors)
    );
    capture_pipe processor(.clk(video_clk),.rst_n(pipeline_running),
        .rgb(rgb),.vs(vs),.de(de),.frame_id(open_id),.frame_time(open_time),
        .out_rgb(clean_rgb),.out_vs(clean_vs),.out_de(clean_de),
        .out_id(clean_id),.out_time(clean_time));
    reg out_vs=0, out_de=0;
    wire init_done, valid;
    wire [15:0] pixel;
    reg raw_vs_d=0;
    reg [31:0] opening_times[0:15];
    always @(posedge video_clk) begin
        raw_vs_d <= vs;
        if(vs && !raw_vs_d) opening_times[open_id]=open_time;
    end
    fram_buf #(.SOURCE_ID(SOURCE),.H_NUM(W),.V_NUM(H),.DISPLAY_HALF(1)) dut (
        .vin_clk(video_clk), .wr_fsync(clean_vs), .wr_en(clean_de), .wr_data(clean_rgb),
        .pipeline_running(pipeline_running),
        .wr_frame_id(clean_id), .wr_frame_time(clean_time),
        .source_result_valid(result_valid), .source_result_id(result_id),
        .source_result_errors(result_errors),
        .ddr_clk(core_clk), .ddr_rstn(rst_n), .init_done(init_done),
        .vout_clk(out_clk), .display_selected(1'b1), .rd_fsync(out_vs), .rd_en(out_de),
        .vout_de(valid), .vout_data(pixel),
        .axi_awaddr(awaddr), .axi_awlen(awlen), .axi_awvalid(awvalid), .axi_awready(awready),
        .axi_wdata(wdata), .axi_wvalid(wvalid), .axi_wready(wready), .axi_wlast(wlast),
        .axi_bid(4'd0), .axi_araddr(araddr), .axi_arlen(arlen),
        .axi_arvalid(arvalid), .axi_arready(arready),
        .axi_rdata(rdata), .axi_rvalid(rvalid), .axi_rlast(rlast), .axi_rid(4'd0)
    );
    function [15:0] pattern(input integer tag, input integer row, input integer col);
        pattern=((SOURCE*16'h4ac3)^(tag*16'h19d7)^(row*16'h031d)^(col*16'h9e37))&16'hffff;
    endfunction
    integer writes=0,reads=0,write_errors=0;
    always @(posedge core_clk) begin
        if(HEIGHT==8 && wready && writes==0)
            $display("FIRST_BEAT src=%0d rdaddr=%h saved=%h live=%h data=%h",SOURCE,
                dut.wr_buf.rd_addr,dut.wr_buf.rd_wdata_1d,dut.wr_buf.rd_wdata,wdata);
        if(HEIGHT==8 && dut.owner.state==2 && dut.owner.settle_count==0)
            $display("DRAIN src=%0d endgood=%0d writebad=%0d lines=%0d/%0d captured=%0d",
                SOURCE,dut.owner.end_good,dut.owner.write_bad,dut.owner.issued_lines,dut.owner.completed_lines,dut.owner.captured_good);
        if(wready) writes<=writes+1;
        if(rvalid) reads<=reads+1;
        if(dut.write_issue && ((dut.owner.have_reader && dut.write_bank==dut.read_bank) ||
            (dut.owner.pending && dut.write_bank==dut.owner.pending_bank)))
            $fatal(1,"source %0d overwrote held bank",SOURCE);
    end
    always @(posedge video_clk) if(HEIGHT==8 && rst_n) begin
        if(dut.owner.writer_de && dut.owner.rows==0 && dut.owner.columns<4)
            $display("FIRST_INPUT src=%0d col=%0d rgb=%h wraddr=%h enable=%0d wen=%0d x=%0d reset=%0d",SOURCE,
                dut.owner.columns,clean_rgb,dut.wr_buf.wr_addr,dut.wr_buf.wr_enable,dut.wr_buf.write_en,dut.wr_buf.x_cnt,dut.wr_buf.wr_rst);
        if(result_valid) $display("VERDICT src=%0d id=%0d errors=%h activeid=%0d active=%0d rows=%0d cols=%0d bad=%0d geom=%0d vs=%0d",
            SOURCE,result_id,result_errors,dut.owner.active_id,dut.owner.active,dut.owner.rows,dut.owner.columns,dut.owner.clean_bad,dut.owner.geometry_done,clean_vs);
        if(dut.owner.sof) $display("SOF src=%0d tag=%0d accept=%0d active=%0d rows=%0d cols=%0d",
            SOURCE,clean_id,dut.owner.accept,dut.owner.active,dut.owner.rows,dut.owner.columns);
    end
    integer output_tag=0, rows=0, columns=0, pixels=0, errors=0, frames=0;
    reg checking=0, black_checking=0, de_d=0;
    integer black_pixels=0;
    integer row_file;
    always @(posedge out_clk) begin
        #2;
        if(black_checking && valid) begin
            if(pixel!==0) $fatal(1,"Faulted output not black");
            black_pixels=black_pixels+1;
        end
        if(checking) begin
            if(valid) begin
                if(pixel !== pattern(output_tag,rows*2,columns*2)) begin
                    if(errors<8) $display("READ_MISMATCH id=%0d y=%0d x=%0d got=%h expected=%h",
                        output_tag,rows,columns,pixel,pattern(output_tag,rows*2,columns*2));
                    errors=errors+1;
                end
                pixels=pixels+1; columns=columns+1;
            end else if(de_d) begin
                if(columns!=OW) $fatal(1,"Incorrect output row width");
                $fdisplay(row_file,"%0d,%0d,%0d,%0d",output_tag,rows,columns,errors);
                columns=0; rows=rows+1;
            end
        end
        de_d=valid;
    end
    task capture(input integer bad_raw, output integer tag);
        integer y,x,width;
        begin
            repeat(60) @(negedge video_clk);
            bad_capture=bad_raw;
            tag=open_id;
            vs=1; repeat(8) @(negedge video_clk); vs=0;
            repeat(20) @(negedge video_clk);
            for(y=0;y<H;y=y+1) begin
                width=W;
                if(bad_raw && y==2) width=W-1;
                if(bad_raw && y==3) width=W+1;
                for(x=0;x<width;x=x+1) begin
                    de=1; rgb=pattern(tag,y,x); @(negedge video_clk);
                end
                de=0; repeat(100) @(negedge video_clk);
            end
            repeat(W+200) @(negedge video_clk);
            vs=1; repeat(8) @(negedge video_clk); vs=0;
            repeat(200) @(negedge video_clk);
            bad_capture=0;
        end
    endtask
    task display_frame(input integer tag);
        integer y,x,old_reads;
        begin
            output_tag=tag; rows=0; columns=0; pixels=0; errors=0; checking=1;
            old_reads=reads;
            @(negedge out_clk); out_vs=1;
            repeat(8) @(negedge out_clk); out_vs=0;
            repeat(2000) @(negedge out_clk);
            if(dut.display_id!=tag || dut.display_time!==opening_times[tag])
                $fatal(1,"Wrong committed frame ID/time");
            for(y=0;y<OH;y=y+1) begin
                for(x=0;x<OW;x=x+1) begin out_de=1; @(negedge out_clk); end
                out_de=0; repeat(370) @(negedge out_clk);
            end
            repeat(100) @(negedge out_clk);
            if(pixels!=OW*OH || rows!=OH || errors!=0 || reads-old_reads!=80*OH)
                $fatal(1,"Incomplete frame id=%0d pixels=%0d rows=%0d errors=%0d beats=%0d",
                    tag,pixels,rows,errors,reads-old_reads);
            frames=frames+1; checking=0;
            $display("OWNERSHIP_FRAME id=%0d pixels=%0d rows=%0d last_row_pixels=640 errors=0",tag,pixels,rows);
        end
    endtask
    integer first_tag,second_tag,bad_tag,last_tag,drop_tag;
    initial begin: driver
        row_file=$fopen(SOURCE ? "rear_rows.csv" : "front_rows.csv","w");
        $fdisplay(row_file,"frame_id,row,pixels,cumulative_errors");
        repeat(SOURCE ? 83 : 40) @(negedge video_clk); rst_n=1;
        repeat(100) @(negedge video_clk);
        capture(0,first_tag);
        if(!init_done || dut.published_count!=1) $fatal(1,"First commit invalid src=%0d pub=%0d rejected=%0d",SOURCE,dut.published_count,dut.rejected_count);
        if(HEIGHT>8) begin
            display_frame(first_tag);
            $display("FULL_SOURCE_PASS source=%0d frame=%0d stored_rows=%0d output_pixels=%0d",SOURCE,first_tag,H,OW*OH);
            $fclose(row_file); finished=1; disable driver;
        end
        capture(0,drop_tag);
        if(dut.published_count!=1 || dut.owner.dropped_count==0) $fatal(1,"Pending overwrite/drop accounting");
        display_frame(first_tag);
        fork
            capture(0,second_tag);
            display_frame(first_tag);
        join
        if(dut.published_count!=2) $fatal(1,"Second commit invalid");
        display_frame(second_tag);
        capture(1,bad_tag);
        if(dut.published_count!=2 || dut.rejected_count!=1) $fatal(1,"Bad geometry was published");
        display_frame(second_tag);
        capture(0,last_tag);
        if(dut.published_count!=3) $fatal(1,"Recovery commit invalid");
        display_frame(last_tag);
        // A read extends over the next VS. Never release its bank, and black
        // every output pixel until the next safe frame boundary.
        stall_reads=1;
        @(negedge out_clk); out_vs=1;
        repeat(8) @(negedge out_clk); out_vs=0;
        wait(dut.owner.read_busy);
        repeat(40) @(negedge out_clk);
        out_vs=1; repeat(8) @(negedge out_clk); out_vs=0;
        repeat(40) @(negedge out_clk);
        if(dut.owner.read_enabled || dut.display_id!=last_tag)
            $fatal(1,"Outstanding read not pinned/disabled");
        stall_reads=0;
        wait(!dut.owner.read_busy);
        repeat(100) @(negedge out_clk);
        black_checking=1;
        repeat(2) begin
            out_de=1;
            repeat(W) begin
                @(negedge out_clk);
                if(valid && pixel!==0) $fatal(1,"Faulted output not black");
            end
            out_de=0; repeat(370) @(negedge out_clk);
        end
        repeat(10) @(negedge out_clk);
        black_checking=0;
        if(black_pixels!=2560) $fatal(1,"Incomplete black-output coverage");
        $display("OWNERSHIP_BLACK pixels=%0d errors=0",black_pixels);
        display_frame(last_tag);
        if(write_errors!=0 || dut.read_fault_count!=1)
            $fatal(1,"Unexpected integrated write/read errors");
        $display("OWNERSHIP_FULL_RESULT frames=%0d pixels=%0d writes=%0d reads=%0d published=%0d rejected=%0d errors=0",
            frames,frames*OW*OH,writes,reads,dut.published_count,dut.rejected_count);
        $fclose(row_file);
        finished=1;
    end
    initial begin #400000000; $fatal(1,"Integrated ownership timeout"); end
endmodule
