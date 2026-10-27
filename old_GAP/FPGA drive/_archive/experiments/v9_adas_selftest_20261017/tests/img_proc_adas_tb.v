`timescale 1ns/1ps
module img_proc_adas_tb;
    localparam W=1280,H=720,FRAMES=14;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,de=0,vs=0;
    reg [15:0] rgb=0;
    wire [15:0] result;
    wire out_de,out_vs,status_valid;
    wire [255:0] snapshot;
    img_proc #(.MODE(4),.ZEBRA_ENABLE(1),.ADAS_ENABLE(1)) dut (
        .clk(clk),.rst_n(rst_n),.de_in(de),.vs_in(vs),.rgb_in(rgb),
        .rgb_out(result),.de_out(out_de),.vs_out(out_vs),.adas_valid(status_valid),.adas_snapshot(snapshot)
    );
    wire [7:0] packet_data;
    wire packet_valid,sample_ready;
    wire [15:0] drops;
    reg packet_ready=0;
    adas_packet encoder(.clk(clk),.rst_n(rst_n),.sample_valid(status_valid),.sample(snapshot),
        .sample_ready(sample_ready),.dropped_samples(drops),.data(packet_data),.valid(packet_valid),.ready(packet_ready));
    reg [31:0] vectors[0:W*H-1];
    reg [255:0] expected_results[0:FRAMES-1];
    reg [1023:0] path;
    reg previous_vs=0;
    integer output_frame=-1,count=0,checked=0,results=0,bytes=0,cycle=0,frame,row,col;
    integer preview[0:3];
    integer preview_index=-1,packets;
    always @(negedge clk) begin cycle=cycle+1; packet_ready=cycle%5!=0; end
    always @(posedge clk) begin
        if(rst_n && packet_valid && packet_ready) begin $fwrite(packets,"%c",packet_data); bytes=bytes+1; end
        if(rst_n && status_valid && !sample_ready) $fatal(1,"Packet snapshot lost");
        #1;
        if(rst_n && status_valid) begin
            if(results>=FRAMES || snapshot!==expected_results[results])
                $fatal(1,"Snapshot %0d got %h expected %h",results,snapshot,expected_results[results]);
            $display("PASS result %0d: flags=%h type=%h offset=%d",results,snapshot[7:0],snapshot[15:8],$signed(snapshot[47:32]));
            results=results+1;
        end
        if(rst_n) begin
            if(out_vs && !previous_vs) begin
                if(output_frame>=0 && count!=W*H) $fatal(1,"Frame pixel count %0d",count);
                output_frame=output_frame+1; count=0;
                case(output_frame) 1:preview_index=0; 4:preview_index=1; 8:preview_index=2; 11:preview_index=3; default:preview_index=-1; endcase
            end
            previous_vs=out_vs;
            if(out_de) begin
                if(output_frame<0 || output_frame>=FRAMES || count>=W*H) $fatal(1,"Unexpected output pixel");
                if(result!==vectors[count][15:0])
                    $fatal(1,"Frame %0d pixel %0d,%0d got %h expected %h",output_frame,count%W,count/W,result,vectors[count][15:0]);
                if(preview_index>=0)
                    $fwrite(preview[preview_index],"%c%c%c",{result[15:11],result[15:13]},
                            {result[10:5],result[10:9]},{result[4:0],result[4:2]});
                count=count+1; checked=checked+1;
            end
        end
    end
    task idle;
        input integer cycles;
        integer i;
        begin for(i=0;i<cycles;i=i+1) begin @(negedge clk); de=0; rgb=0; end end
    endtask
    initial begin
        $readmemh("output/adas/snapshots.hex",expected_results);
        packets=$fopen("output/adas/rtl_pipeline_packets.bin","wb");
        for(frame=0;frame<4;frame=frame+1) begin
            $sformat(path,"output/adas/rtl_preview_%0d.ppm",frame);
            preview[frame]=$fopen(path,"wb");
            if(!preview[frame]) $fatal(1,"Cannot open preview");
            $fwrite(preview[frame],"P6\n1280 720\n255\n");
        end
        idle(16); @(negedge clk); rst_n=1;
        for(frame=0;frame<FRAMES;frame=frame+1) begin
            $sformat(path,"output/adas/frame_%02d.hex",frame);
            $readmemh(path,vectors);
            @(negedge clk); vs=1;
            idle(3);
            @(negedge clk); vs=0;
            idle(10000);
            for(row=0;row<H;row=row+1) begin
                for(col=0;col<W;col=col+1) begin
                    @(negedge clk); de=1; rgb=vectors[row*W+col][31:16];
                end
                idle(1+row%3);
            end
            idle(15000);
        end
        if(checked!=FRAMES*W*H || results!=FRAMES || count!=W*H || output_frame!=FRAMES-1
           || drops!=0 || bytes!=FRAMES*38) $fatal(1,"Counters: pixels=%0d results=%0d bytes=%0d drops=%0d",checked,results,bytes,drops);
        for(frame=0;frame<4;frame=frame+1) $fclose(preview[frame]);
        $fclose(packets);
        $display("PASS: %0d full-pipeline pixels, %0d snapshots, %0d packet bytes; RGB/masks/geometry/HUD/crosswalk/clearing",checked,results,bytes);
        $finish;
    end
    initial begin #180000000; $fatal(1,"Timeout"); end
endmodule
