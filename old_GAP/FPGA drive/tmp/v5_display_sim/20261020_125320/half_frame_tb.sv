`timescale 1ns/1ps
module ownership_full_frame_tb #(
    parameter DISPLAY_PATH=0
);
    localparam W=1280, H=720;
    reg grs_n=0;
    GTP_GRS GRS_INST(.GRS_N(grs_n));
    initial #100 grs_n=1;
    reg core_clk=0, video_clk=0, out_clk=0;
    always #5 core_clk=~core_clk;
    always #13.468 video_clk=~video_clk;
    always #16.9230769 out_clk=~out_clk;
    reg rst_n=0, vs=0, de=0;
    reg [15:0] rgb=0;
    wire pipeline_running, clean_vs, clean_de;
    wire [15:0] clean_rgb;
    wire [31:0] open_id, open_time, clean_id, clean_time, result_id;
    wire result_valid;
    wire [7:0] result_errors;
    video_capture_status #(.REF_HZ(100000000), .TIMEOUT_MS(200)) monitor (
        .ref_clk(core_clk), .video_clk(video_clk), .rst_n(rst_n),
        .source_ready(1'b1), .video_vs(vs), .video_de(de),
        .pipeline_rst_n(pipeline_running),
        .frame_open_id(open_id), .frame_open_time(open_time),
        .frame_result_valid(result_valid), .frame_result_id(result_id),
        .frame_result_errors(result_errors)
    );
    wire [15:0] raw_clean_rgb, display_rgb;
    wire raw_clean_vs, raw_clean_de, display_vs, display_de;
    wire [31:0] raw_clean_id, raw_clean_time, display_id, display_time;
    assign clean_rgb=DISPLAY_PATH ? display_rgb : raw_clean_rgb;
    assign clean_vs=DISPLAY_PATH ? display_vs : raw_clean_vs;
    assign clean_de=DISPLAY_PATH ? display_de : raw_clean_de;
    assign clean_id=DISPLAY_PATH ? display_id : raw_clean_id;
    assign clean_time=DISPLAY_PATH ? display_time : raw_clean_time;
    // Test boundary: known source pixels into the production frame buffer.
    // Unchanged image algorithms are not part of this display-only regression.
    reg [1:0] vs_pipe=0, de_pipe=0;
    reg [15:0] rgb_pipe0=0, rgb_pipe1=0;
    reg source_vs_d=0;
    reg [31:0] tagged_id=0, tagged_time=0;
    always @(posedge video_clk) begin
        if (!pipeline_running) begin
            vs_pipe<=0; de_pipe<=0; rgb_pipe0<=0; rgb_pipe1<=0;
            source_vs_d<=0; tagged_id<=0; tagged_time<=0;
        end else begin
            vs_pipe<={vs_pipe[0],vs}; de_pipe<={de_pipe[0],de};
            source_vs_d<=vs;
            if (vs && !source_vs_d) begin tagged_id<=open_id; tagged_time<=open_time; end
            rgb_pipe0<=rgb; rgb_pipe1<=rgb_pipe0;
        end
    end
    assign raw_clean_vs=vs_pipe[1], display_vs=vs_pipe[1];
    assign raw_clean_de=de_pipe[1], display_de=de_pipe[1];
    assign raw_clean_rgb=rgb_pipe1, display_rgb=rgb_pipe1;
    assign raw_clean_id=tagged_id, display_id=tagged_id;
    assign raw_clean_time=tagged_time, display_time=tagged_time;
    reg out_vs=0, out_de=0;
    wire init_done, valid;
    wire [15:0] pixel;
    wire [27:0] awaddr, araddr;
    wire [3:0] awlen, arlen;
    wire awvalid, arvalid, wvalid;
    wire [255:0] wdata;
    reg awready=0, wready=0, wlast=0, arready=0, rvalid=0, rlast=0;
    reg [255:0] rdata=0;
    reg stall_reads=0;
    reg raw_vs_d=0;
    reg [31:0] opening_times[0:15];
    always @(posedge video_clk) begin
        raw_vs_d <= vs;
        if(vs && !raw_vs_d) opening_times[open_id]=open_time;
    end
    fram_buf #(.DISPLAY_HALF(1)) dut (
        .vin_clk(video_clk), .wr_fsync(clean_vs), .wr_en(clean_de), .wr_data(clean_rgb),
        .pipeline_running(pipeline_running),
        .wr_frame_id(clean_id), .wr_frame_time(clean_time),
        .source_result_valid(result_valid), .source_result_id(result_id),
        .source_result_errors(result_errors),
        .ddr_clk(core_clk), .ddr_rstn(rst_n), .init_done(init_done),
        .vout_clk(out_clk), .rd_fsync(out_vs), .rd_en(out_de),
        .vout_de(valid), .vout_data(pixel),
        .axi_awaddr(awaddr), .axi_awlen(awlen), .axi_awvalid(awvalid), .axi_awready(awready),
        .axi_wdata(wdata), .axi_wvalid(wvalid), .axi_wready(wready), .axi_wlast(wlast),
        .axi_bid(4'd0), .axi_araddr(araddr), .axi_arlen(arlen),
        .axi_arvalid(arvalid), .axi_arready(arready),
        .axi_rdata(rdata), .axi_rvalid(rvalid), .axi_rlast(rlast), .axi_rid(4'd0)
    );
    // External native-port memory BFM only. The production controllers and
    // generated line RAMs/Pango primitives remain in the DUT.
    reg [255:0] memory [0:115199];
    function integer index_of(input [27:0] address);
        begin
            if (address[21:0] >= W*H/2 || address[2:0]!=0 || address[27:23]!=0)
                $fatal(1,"DDR address outside existing two-bank layout: %h",address);
            index_of=address[22]*57600+address[21:0]/8;
        end
    endfunction
    function [15:0] pattern(input integer tag, input integer row, input integer col);
        pattern=((tag*16'h19d7)^(row*16'h031d)^(col*16'h9e37))&16'hffff;
    endfunction
    integer writes=0, reads=0, checked_writes=0, write_errors=0;
    integer wi, wa, wl, wb, wy, wx, wt, lane;
    integer ri, ra, rl, rb;
    initial begin
        wait(rst_n);
        forever begin
            @(negedge core_clk); awready=1;
            do @(posedge core_clk); while (!awvalid);
            wa=awaddr; wl=awlen+1; wi=index_of(awaddr);
            if (dut.owner.have_reader && awaddr[22]==dut.read_bank)
                $fatal(1,"Writing pinned display bank");
            wt=dut.owner.active_id;
            @(negedge core_clk); awready=0;
            repeat(3) @(negedge core_clk);
            for(wb=0;wb<wl;wb=wb+1) begin
                if(wb%5==3) repeat(3) @(negedge core_clk);
                wready=1; wlast=(wb==wl-1);
                @(posedge core_clk);
                if(!wvalid) $fatal(1,"Native write data missing");
                memory[wi+wb]=wdata;
                wy=((wa & 'h3fffff)/8+wb)/80;
                wx=(((wa & 'h3fffff)/8+wb)%80)*16;
                for(lane=0;lane<16;lane=lane+1) begin
                    if(wt!=3 && wdata[lane*16+:16] !== pattern(wt,wy,wx+lane)) begin
                        if(write_errors<8)
                            $display("WRITE_MISMATCH id=%0d y=%0d x=%0d got=%h expected=%h",
                                wt,wy,wx+lane,wdata[lane*16+:16],pattern(wt,wy,wx+lane));
                        write_errors=write_errors+1;
                    end
                    checked_writes=checked_writes+1;
                end
                writes=writes+1;
                @(negedge core_clk); wready=0; wlast=0;
            end
        end
    end
    initial begin
        wait(rst_n);
        forever begin
            @(negedge core_clk); arready=1;
            do @(posedge core_clk); while(!arvalid);
            ra=araddr; rl=arlen+1; ri=index_of(araddr);
            if(!dut.owner.have_reader || araddr[22]!=dut.read_bank)
                $fatal(1,"Read not pinned to display bank");
            @(negedge core_clk); arready=0;
            while(stall_reads) @(negedge core_clk);
            repeat(2) @(negedge core_clk);
            for(rb=0;rb<rl;rb=rb+1) begin
                if(rb==15) repeat(4) @(negedge core_clk);
                rdata=memory[ri+rb]; rvalid=1; rlast=rb==rl-1;
                @(posedge core_clk); reads=reads+1;
                @(negedge core_clk); rvalid=0; rlast=0;
            end
        end
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
                if(columns!=W/2) $fatal(1,"Incorrect output row width");
                $fdisplay(row_file,"%0d,%0d,%0d,%0d",output_tag,rows,columns,errors);
                $fflush(row_file); columns=0; rows=rows+1;
            end
        end
        de_d=valid;
    end
    task capture(input integer tag, input integer bad_raw);
        integer y,x,width;
        begin
            @(negedge video_clk);
            // Previous close marker has already opened this source frame.
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
            $display("SOURCE_CAPTURE tag=%0d published=%0d",tag,dut.published_count); $fflush();
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
            for(y=0;y<H/2;y=y+1) begin
                for(x=0;x<W/2;x=x+1) begin out_de=1; @(negedge out_clk); end
                out_de=0; repeat(370) @(negedge out_clk);
            end
            repeat(100) @(negedge out_clk);
            if(pixels!=W*H/4 || rows!=H/2 || errors!=0 || reads-old_reads!=28800)
                $fatal(1,"Incomplete frame id=%0d pixels=%0d rows=%0d errors=%0d beats=%0d",
                    tag,pixels,rows,errors,reads-old_reads);
            frames=frames+1; checking=0;
            $display("OWNERSHIP_FRAME id=%0d pixels=%0d rows=%0d last_row_pixels=640 errors=0",tag,pixels,rows);
        end
    endtask
    initial begin
        row_file=$fopen("rows.csv","w");
        $fdisplay(row_file,"frame_id,row,pixels,cumulative_errors");
        repeat(40) @(negedge video_clk); rst_n=1;
        repeat(100) @(negedge video_clk);
        vs=1; repeat(8) @(negedge video_clk); vs=0;
        capture(0,0);
        wait(init_done);
        if(dut.published_count!=1 || write_errors!=0) $fatal(1,"First commit invalid");
        // No output boundary: pending frame occupies the bank and new input
        // frames are dropped in their entirety.
        capture(1,0);
        if(dut.published_count!=1) $fatal(1,"Overwrote pending frame");
        display_frame(0);
        // Input and display clocks/rates differ; concurrent acquisition may
        // write only the other bank. Repeat the old completed frame meanwhile.
        fork
            capture(2,0);
            display_frame(0);
        join
        if(dut.published_count!=2 || write_errors!=0) $fatal(1,"Second commit invalid");
        display_frame(2);
        capture(3,1);
        if(dut.published_count!=2 || dut.rejected_count!=1)
            $fatal(1,"Bad raw row geometry was published");
        display_frame(2);
        capture(4,0);
        if(dut.published_count!=3 || write_errors!=0) $fatal(1,"Recovery commit invalid");
        display_frame(4);
        // A read extends over the next VS. Never release its bank, and black
        // every output pixel until the next safe frame boundary.
        stall_reads=1;
        @(negedge out_clk); out_vs=1;
        repeat(8) @(negedge out_clk); out_vs=0;
        wait(dut.owner.read_busy);
        repeat(40) @(negedge out_clk);
        out_vs=1; repeat(8) @(negedge out_clk); out_vs=0;
        repeat(40) @(negedge out_clk);
        if(dut.owner.read_enabled || dut.display_id!=4)
            $fatal(1,"Outstanding read not pinned/disabled");
        stall_reads=0;
        wait(!dut.owner.read_busy);
        repeat(100) @(negedge out_clk);
        black_checking=1;
        repeat(2) begin
            out_de=1;
            repeat(W/2) begin
                @(negedge out_clk);
                if(valid && pixel!==0) $fatal(1,"Faulted output not black");
            end
            out_de=0; repeat(370) @(negedge out_clk);
        end
        repeat(10) @(negedge out_clk);
        black_checking=0;
        if(black_pixels!=1280) $fatal(1,"Incomplete black-output coverage");
        $display("OWNERSHIP_BLACK pixels=%0d errors=0",black_pixels);
        display_frame(4);
        if(write_errors!=0 || dut.read_fault_count!=1)
            $fatal(1,"Unexpected integrated write/read errors");
        $display("OWNERSHIP_FULL_RESULT frames=%0d pixels=%0d writes=%0d reads=%0d published=%0d rejected=%0d errors=0",
            frames,frames*W*H/4,writes,reads,dut.published_count,dut.rejected_count);
        $fclose(row_file);
        $finish;
    end
    initial begin #400000000; $fatal(1,"Integrated ownership timeout"); end
endmodule
