`timescale 1ns/1ps
module capture_full_color_tb;
    localparam W=1280,H=720;
    reg ref_clk=0, video_clk=0;
    always #7 ref_clk=~ref_clk;
    always #5 video_clk=~video_clk;
    reg rst_n=0,vs=0,de=0;
    reg [15:0] rgb=0;
    wire pipe_rst,healthy,timed_out,snapshot_valid;
    wire [31:0] timeout_count;
    wire [255:0] snapshot;
    wire clean_de,clean_vs;
    wire [15:0] clean_rgb;
    video_capture_status #(.REF_HZ(100000000),.TIMEOUT_MS(50)) status (
        .ref_clk(ref_clk),.video_clk(video_clk),.rst_n(rst_n),
        .source_ready(1'b1),.video_vs(vs),.video_de(de),
        .pipeline_rst_n(pipe_rst),.healthy(healthy),.timed_out(timed_out),
        .timeout_count(timeout_count),.snapshot_valid(snapshot_valid),.snapshot(snapshot)
    );
    img_proc #(.MODE(0),.H_ACTIVE(W),.V_ACTIVE(H)) processor (
        .clk(video_clk),.rst_n(pipe_rst),.rgb_in(rgb),.de_in(de),.vs_in(vs),
        .clean_rgb_out(clean_rgb),.clean_de_out(clean_de),.clean_vs_out(clean_vs)
    );
    function [15:0] sample(input integer f,input integer y,input integer x);
        sample=((f*16'h19d7) ^ (y*16'h031d) ^ (x*16'h9e37)) & 16'hffff;
    endfunction
    integer pixels=0,frames=0,reports=0,frame_pixels=0,rows=0,cols=0;
    integer f,y,x;
    reg de_d=0;
    always @(posedge video_clk) begin
        #1;
        if (clean_vs) begin
            if (frames>0 && (frame_pixels!=W*H || rows!=H))
                $fatal(1,"Incomplete preceding clean frame");
            frames=frames+1; frame_pixels=0; rows=0; cols=0;
        end
        if(clean_de) begin
            if(clean_rgb!==sample(frames-1,rows,cols))
                $fatal(1,"Color mismatch frame=%0d y=%0d x=%0d",frames-1,rows,cols);
            cols=cols+1; pixels=pixels+1; frame_pixels=frame_pixels+1;
        end else if(de_d) begin
            if(cols!=W) $fatal(1,"Wrong clean DE row length");
            rows=rows+1; cols=0;
        end
        de_d=clean_de;
        if(timed_out) $fatal(1,"Watchdog falsely expired during normal raster");
    end
    always @(posedge ref_clk) begin
        #1;
        if(snapshot_valid) begin
            if(snapshot[31:0]!=reports || snapshot[95:64]!=W*H ||
               snapshot[111:96]!=H || snapshot[119:112]!=0)
                $fatal(1,"Full raster metadata mismatch");
            reports=reports+1;
        end
    end
    initial begin
        repeat(20) @(negedge video_clk);
        rst_n=1;
        repeat(20) @(negedge video_clk);
        for(f=0;f<3;f=f+1) begin
            vs=1; repeat(8) @(negedge video_clk); vs=0;
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W;x=x+1) begin
                    de=1; rgb=sample(f,y,x); @(negedge video_clk);
                end
                de=0; repeat(32) @(negedge video_clk);
            end
            repeat(W+128) @(negedge video_clk);
        end
        vs=1; repeat(8) @(negedge video_clk); vs=0;
        repeat(50) @(negedge ref_clk);
        if(pixels!=2764800 || frames!=3 || reports!=3 || rows!=H ||
           frame_pixels!=W*H || !healthy || timeout_count!=0)
            $fatal(1,"Wrong full-color totals");
        $display("CAPTURE_COLOR_RESULT frames=%0d reports=%0d pixels=%0d errors=0",
            frames,reports,pixels);
        $finish;
    end
    initial begin #50000000; $fatal(1,"Full frame test timed out"); end
endmodule
