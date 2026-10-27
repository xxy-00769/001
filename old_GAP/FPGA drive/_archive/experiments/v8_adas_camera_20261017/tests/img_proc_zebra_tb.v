`timescale 1ns/1ps
module img_proc_zebra_tb;
    localparam W=1280,H=720;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,de=0,vs=0;
    reg [15:0] rgb=0;
    wire [15:0] result;
    wire out_de,out_vs;
    img_proc #(.MODE(4),.ZEBRA_ENABLE(1)) dut (
        .clk(clk),.rst_n(rst_n),.de_in(de),.vs_in(vs),.rgb_in(rgb),
        .rgb_out(result),.de_out(out_de),.vs_out(out_vs)
    );
    reg [31:0] vectors [0:W*H-1];
    reg previous_vs=0;
    reg [15:0] expected;
    integer output_frame=-1,count=0,checked=0,results=0,frame,row,col,ox,oy;
    integer preview;
    always @(posedge clk) begin
        #1;
        if(rst_n && dut.g_zebra.result_valid) begin
            if(dut.g_zebra.candidate !== (results<3)
               || dut.g_zebra.confirmed !== (results==1 || results==2))
                $fatal(1,"Detector frame %0d: candidate=%b confirmed=%b",results,dut.g_zebra.candidate,dut.g_zebra.confirmed);
            if(results<3 && (dut.g_zebra.x0!==400 || dut.g_zebra.x1!==679
                             || dut.g_zebra.y0!==440 || dut.g_zebra.y1!==519))
                $fatal(1,"Wrong full-pipeline candidate coordinates");
            results=results+1;
        end
        if(rst_n) begin
            if(out_vs && !previous_vs) begin
                if(output_frame>=0 && count!=W*H) $fatal(1,"Frame pixel count %0d",count);
                output_frame=output_frame+1; count=0;
            end
            previous_vs=out_vs;
            if(out_de) begin
                if(output_frame<0 || output_frame>4 || count>=W*H) $fatal(1,"Unexpected output pixels");
                ox=count%W; oy=count/W;
                expected=output_frame<3 ? vectors[count][15:0] : 16'h4228;
                if(ox>=16 && ox<48 && oy>=16 && oy<40 && ox%8<4)
                    expected=output_frame==1 ? 16'hFD20
                             : ((output_frame==2 || output_frame==3) ? 16'hF81F : 16'h8410);
                else if((output_frame==2 || output_frame==3) && ox>=400 && ox<=679 && oy>=440 && oy<=519
                        && (ox==400 || ox==679 || oy==440 || oy==519)) expected=16'hF81F;
                if(result!==expected)
                    $fatal(1,"Frame %0d pixel %0d,%0d got %h expected %h",output_frame,ox,oy,result,expected);
                if(output_frame==2)
                    $fwrite(preview,"%c%c%c",{result[15:11],result[15:13]},
                            {result[10:5],result[10:9]},{result[4:0],result[4:2]});
                count=count+1; checked=checked+1;
            end
        end
    end
    task idle;
        input integer cycles;
        integer i;
        begin
            for(i=0;i<cycles;i=i+1) begin @(negedge clk); de=0; rgb=0; end
        end
    endtask
    initial begin
        $readmemh("output/zebra/positive.hex",vectors);
        preview=$fopen("output/zebra/rtl_confirmed.ppm","wb");
        if(!preview) $fatal(1,"Cannot open RTL preview");
        $fwrite(preview,"P6\n1280 720\n255\n");
        idle(16); @(negedge clk); rst_n=1;
        for(frame=0;frame<5;frame=frame+1) begin
            @(negedge clk); vs=1;
            idle(3);
            @(negedge clk); vs=0;
            idle(10000);
            for(row=0;row<H;row=row+1) begin
                for(col=0;col<W;col=col+1) begin
                    @(negedge clk); de=1;
                    rgb=frame<3 ? vectors[row*W+col][31:16] : 16'h4228;
                end
                // One-clock blanking exercises the tightest supported line gap.
                idle(1+row%3);
            end
            idle(15000);
        end
        if(checked!=5*W*H || results!=5 || count!=W*H || output_frame!=4)
            $fatal(1,"pixels=%0d results=%0d frame=%0d count=%0d",checked,results,output_frame,count);
        $fclose(preview);
        $display("PASS: %0d full-pipeline pixels, 5 frame results, v4 paint oracle and v7 annotations",checked);
        $finish;
    end
    initial begin #70000000; $fatal(1,"Timeout"); end
endmodule
