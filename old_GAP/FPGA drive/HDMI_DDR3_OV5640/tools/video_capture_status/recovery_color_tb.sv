`timescale 1ns/1ps
// Tests the actual reset -> img_proc -> clean tuple after a stopped source.
// DDR/PHY are deliberately not replaced by an ideal frame store.
module capture_recovery_color_tb;
    localparam W=32,H=6;
    reg ref_clk=0, video_clk=0, video_run=1;
    always #7 ref_clk=~ref_clk;
    always #5 if(video_run) video_clk=~video_clk; else video_clk=0;
    reg rst_n=0,vs=0,de=0;
    reg [15:0] rgb=0;
    wire pipe_rst,healthy,timed_out,clean_vs,clean_de;
    wire [15:0] clean_rgb;
    video_capture_status #(.H_ACTIVE(W),.V_ACTIVE(H),
        .REF_HZ(1000),.TIMEOUT_MS(1000)) status (
        .ref_clk(ref_clk),.video_clk(video_clk),.rst_n(rst_n),
        .source_ready(1'b1),.video_vs(vs),.video_de(de),
        .pipeline_rst_n(pipe_rst),.healthy(healthy),.timed_out(timed_out)
    );
    img_proc #(.MODE(0),.H_ACTIVE(W),.V_ACTIVE(H)) processor (
        .clk(video_clk),.rst_n(pipe_rst),.rgb_in(rgb),.de_in(de),.vs_in(vs),
        .clean_rgb_out(clean_rgb),.clean_de_out(clean_de),.clean_vs_out(clean_vs)
    );
    function [15:0] sample(input integer tag,input integer y,input integer x);
        sample=(tag*16'h2927)^(y*16'h130d)^(x*16'h071f);
    endfunction
    integer current_tag=0,output_tag=0;
    integer rows=0,cols=0,frame_pixels=0,complete_frames=0,pixels=0,f,r,x;
    integer pre_reset_complete;
    reg prior_de=0,tracking=0;
    always @(posedge video_clk) begin
        #1;
        if(!pipe_rst) begin
            rows=0; cols=0; frame_pixels=0; prior_de=0; tracking=0;
        end else begin
            if(clean_vs) begin
                if(tracking && (frame_pixels!=W*H || rows!=H))
                    $fatal(1,"Unreset incomplete frame leaked into next clean frame");
                output_tag=current_tag; rows=0; cols=0; frame_pixels=0; tracking=1;
            end
            if(clean_de) begin
                if(!tracking || clean_rgb!==sample(output_tag,rows,cols))
                    $fatal(1,"Recovery mixed color/coordinates across frames");
                frame_pixels=frame_pixels+1; cols=cols+1; pixels=pixels+1;
            end else if(prior_de) begin
                if(cols!=W) $fatal(1,"Recovery changed clean row length");
                cols=0; rows=rows+1;
                if(rows==H) begin
                    if(frame_pixels!=W*H) $fatal(1,"Recovery frame size mismatch");
                    complete_frames=complete_frames+1;
                end
            end
            prior_de=clean_de;
        end
    end
    task start_frame(input integer tag);
        begin
            @(negedge video_clk); current_tag=tag; vs=1; de=0;
            repeat(8) @(negedge video_clk);
            vs=0;
        end
    endtask
    task raster(input integer tag,input integer count_rows);
        for(r=0;r<count_rows;r=r+1) begin
            for(x=0;x<W;x=x+1) begin
                rgb=sample(tag,r,x); de=1; @(negedge video_clk);
            end
            de=0; repeat(8) @(negedge video_clk);
        end
    endtask
    initial begin
        repeat(20) @(negedge video_clk); rst_n=1;
        repeat(20) @(negedge video_clk);
        start_frame(0); raster(0,2);
        video_run=0;
        repeat(1200) @(negedge ref_clk);
        if(!timed_out || pipe_rst || healthy)
            $fatal(1,"Stopped source did not reset actual processing path");
        video_run=1;
        for(f=1;f<=5;f=f+1) begin
            start_frame(f); raster(f,H);
            repeat(W+32) @(negedge video_clk);
        end
        if(!healthy || timed_out || complete_frames<3)
            $fatal(1,"Color path failed to recover");
        pre_reset_complete=complete_frames;
        // Exercise a global reset while the next frame has active data.
        start_frame(6); raster(6,2); rst_n=0;
        repeat(20) @(negedge video_clk); de=0; vs=0; rst_n=1;
        repeat(20) @(negedge video_clk);
        for(f=7;f<=9;f=f+1) begin
            start_frame(f); raster(f,H);
            repeat(W+32) @(negedge video_clk);
        end
        vs=1; repeat(8) @(negedge video_clk); vs=0;
        repeat(30) @(negedge ref_clk);
        if(!healthy || complete_frames!=pre_reset_complete+3)
            $fatal(1,"Unexpected reset/recovery completed frames: %0d",complete_frames);
        $display("CAPTURE_RECOVERY_RESULT frames=%0d pixels=%0d errors=0",complete_frames,pixels);
        $finish;
    end
    initial begin #150000; $fatal(1,"Recovery test timed out"); end
endmodule
