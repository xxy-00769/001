`timescale 1ns/1ps
module adas_test_pattern_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    wire de,vs;
    wire [15:0] rgb;
    wire [2:0] phase;
    adas_test_pattern #(.PHASE_FRAMES(1)) dut(.clk(clk),.rst_n(rst_n),.de(de),.vs(vs),.rgb(rgb),.phase(phase));
    integer frames=-1,count=0,checked=0,x,y,shift,lx,rx;
    reg mark;
    reg [15:0] expected;
    always @(posedge clk) begin
        if(rst_n) begin
            if(vs) begin
                if(frames>=0 && count!=1280*720) $fatal(1,"Pattern frame size %0d",count);
                frames=frames+1; count=0;
                if(frames==6) begin
                    if(phase!==0 || checked!=6*1280*720) $fatal(1,"Phase wrap/count");
                    $display("PASS: 6 synthetic phases, 5529600 pixels, exact raster, frame counts and phase wrap");
                    $finish;
                end
                if(phase!==frames) $fatal(1,"Wrong phase %d expected %0d",phase,frames);
            end
            if(de) begin
                x=count%1280; y=count/1280;
                if(dut.x!==x || dut.image_y!==y) $fatal(1,"Pattern coordinate mismatch");
                shift=phase==1 ? -100 : (phase==2 ? 100 : 0);
                lx=500-(y-405)/2+shift; rx=780+(y-405)/2+shift;
                mark=phase<4 && y>=405 && (phase!=3 || y<=515 || (y>=548 && y<=643) || y>=672)
                     && ((x>=lx-3 && x<=lx+3) || (x>=rx-3 && x<=rx+3));
                if(phase==4) mark=y>=440 && y<=519 && x>=400 && x<680 && (x-400)%80<40;
                expected=mark ? 16'hFFFF : 16'h4228;
                // TEST glyphs are checked separately; all other pixels are exact.
                if(!(x>=32 && x<128 && y>=80 && y<108) && rgb!==expected)
                    $fatal(1,"Pattern phase %d at %0d,%0d got %h expected %h",phase,x,y,rgb,expected);
                if(x==32 && y==80 && rgb!==16'hFFE0) $fatal(1,"Missing permanent TEST label");
                count=count+1; checked=checked+1;
            end else if(rgb!==0) $fatal(1,"Nonzero blanking");
        end
    end
    initial begin repeat(4) @(negedge clk); rst_n=1; end
    initial begin #60000000; $fatal(1,"Timeout"); end
endmodule
