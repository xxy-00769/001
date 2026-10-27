`timescale 1ns/1ps
module timing_tb;
    reg clk=0, rst_n=0;
    always #16.9230769 clk=~clk;
    wire fs, req, hs, vs, de, image;
    wire [23:0] probe;
    mpi7001_timing dut(clk,rst_n,fs,req,hs,vs,de,image,probe);
    integer i,h,v,de_count,image_count,line_count,hs_count,vs_count;
    reg [1:0] eh=0,ev=3,ed=0,ei=0;
    reg [23:0] expected_probe0=0,expected_probe1=0;
    function [23:0] probe_at(input integer x,input integer y);
        begin
            probe_at=0;
        end
    endfunction
    initial begin
        repeat(4) @(negedge clk);
        if (fs !== 0 || req !== 0 || probe !== 0) $fatal(1,"Reset must not hide first SOF");
        rst_n=1; #1;
        for(i=0;i<992*497*3;i=i+1) begin
            h=i%992; v=(i/992)%497;
            if(req !== (h>=256 && h<896 && v>=76 && v<436)) $fatal(1,"Read request coordinates");
            if(fs !== (v<3)) $fatal(1,"Frame start");
            eh={eh[0],h<80}; ev={ev[0],!(v<3)};
            ed={ed[0],h>=176 && h<976 && v>=16 && v<496};
            ei={ei[0],h>=256 && h<896 && v>=76 && v<436};
            expected_probe1=expected_probe0;
            expected_probe0=probe_at(h,v);
            @(posedge clk); #2;
            if({hs,vs,de,image} !== {eh[1],ev[1],ed[1],ei[1]}) $fatal(1,"Timing latency/polarity");
            if(probe !== expected_probe1) $fatal(1,"Diagnostic RGB/DE coordinates");
            @(negedge clk);
        end
        $display("TIMING_PASS frames=3 total=992x497 active=800x480 image=640x360 origin=80,60 HS=positive VS=negative");
        $finish;
    end
endmodule
