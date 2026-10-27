`timescale 1ns/1ps
module img_proc_selftest_tb;
    localparam W=1280,H=720;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    wire de,vs;
    wire [15:0] rgb,result;
    wire out_de,out_vs,status_valid;
    wire [255:0] snapshot;
    adas_test_pattern #(.PHASE_FRAMES(1)) source(.clk(clk),.rst_n(rst_n),.de(de),.vs(vs),.rgb(rgb),.phase());
    img_proc #(.MODE(4),.ZEBRA_ENABLE(1),.ADAS_ENABLE(1)) dut (
        .clk(clk),.rst_n(rst_n),.de_in(de),.vs_in(vs),.rgb_in(rgb),.rgb_out(result),.de_out(out_de),.vs_out(out_vs),
        .adas_valid(status_valid),.adas_snapshot(snapshot));
    reg [31:0] vectors[0:W*H-1];
    reg [255:0] expected[0:13];
    reg previous_vs=0;
    integer frame=-1,count=0,checked=0,results=0,x,y,preview;
    always @(posedge clk) begin
        #1;
        if(rst_n) begin
            if(out_vs && !previous_vs) begin
                if(frame>=0 && count!=W*H) $fatal(1,"Selftest incomplete frame");
                frame=frame+1; count=0;
                if(frame==0) $readmemh("output/adas/frame_00.hex",vectors);
                else if(frame==1) $readmemh("output/adas/frame_01.hex",vectors);
                else $fatal(1,"Selftest did not finish");
            end
            previous_vs=out_vs;
            if(out_de) begin
                x=count%W; y=count/W;
                if(!(x>=32 && x<128 && y>=80 && y<108)) begin
                    if(result!==vectors[count][15:0]) $fatal(1,"Selftest frame %0d at %0d,%0d got %h expected %h",frame,x,y,result,vectors[count][15:0]);
                    checked=checked+1;
                end
                if(x==32 && y==80 && result!==16'hFFE0) $fatal(1,"Missing TEST watermark");
                if(frame==1) $fwrite(preview,"%c%c%c",{result[15:11],result[15:13]},
                                     {result[10:5],result[10:9]},{result[4:0],result[4:2]});
                count=count+1;
            end
            if(status_valid) begin
                if(snapshot!==expected[results]) $fatal(1,"Selftest result %0d mismatch",results);
                results=results+1;
                if(results==2) begin
                    if(frame!=1 || count!=W*H || checked!=2*(W*H-96*28)) $fatal(1,"Selftest count mismatch");
                    $fclose(preview);
                    $display("PASS: synthetic source through full pipeline, 2 complete frames, %0d oracle pixels plus TEST watermark, 2 snapshots",checked);
                    $finish;
                end
            end
        end
    end
    initial begin
        $readmemh("output/adas/snapshots.hex",expected);
        preview=$fopen("output/adas/rtl_selftest.ppm","wb");
        $fwrite(preview,"P6\n1280 720\n255\n");
        repeat(8) @(negedge clk);
        rst_n=1;
    end
    initial begin #22000000; $fatal(1,"Timeout"); end
endmodule
