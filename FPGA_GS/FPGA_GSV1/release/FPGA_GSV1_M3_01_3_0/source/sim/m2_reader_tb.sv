`timescale 1ns/1ps
module m2_reader_tb #(parameter QUARTER=0,LEGACY=0,DELAY_NS=0);
    reg dc=0,pc=0,rst=0,trst=0,grs=0,manual_fs=0;
    always #5 dc=~dc;
    always #16.9230769 pc=~pc;
    GTP_GRS GRS_INST(.GRS_N(grs));
    wire fs,raw_req,req,hs,vs,de,image,valid;
    wire [9:0] rx,px;wire [8:0] ry,py;
    assign req=raw_req && (!QUARTER || (rx<400 && ry<240));
    wire [15:0] pixel;
    wire [27:0] addr;
    wire [31:0] len;
    wire command;
    reg done=0,ren=0;
    reg [255:0] data=0;
    mpi7001_timing timing(.clk(pc),.rst_n(trst),.frame_sync(fs),.read_request(raw_req),
        .hs(hs),.vs(vs),.de(de),.image_area(image),.diagnostic_rgb(),.raw_x(rx),.raw_y(ry),.active_x(px),.active_y(py));
    generate if(LEGACY) begin
    rd_buf #(.ADDR_WIDTH(28),.H_NUM(1280),.V_NUM(360),.PIX_WIDTH(16),
             .LINE_ADDR_WIDTH(22),.FRAME_CNT_WIDTH(6),.DISPLAY_HALF(1)) dut(
        .ddr_clk(dc),.ddr_rstn(rst),.vout_clk(pc),.rd_fsync(fs),
        .rd_en(req),.vout_de(valid),.vout_data(pixel),.init_done(1'b1),
        .ddr_rreq(command),.ddr_raddr(addr),.ddr_rd_len(len),.ddr_rrdy(1'b1),
        .ddr_rdone(done),.ddr_rdata(data),.ddr_rdata_en(ren));
    end else begin
      m2_rd_buf #(.H_NUM(1280),.V_NUM(720),.ADDR_WIDTH(28)) dut(
        .ddr_clk(dc),.ddr_rstn(rst),.vout_clk(pc),.rd_fsync(fs),.rd_en(req),
        .quarter(QUARTER!=0),.selected(1'b1),.enabled(1'b1),
        .vout_de(valid),.vout_data(pixel),.ddr_rreq(command),.ddr_raddr(addr),
        .ddr_rd_len(len),.ddr_rrdy(1'b1),.ddr_rdone(done),.ddr_rdata(data),.ddr_rdata_en(ren));
    end endgenerate
    function [15:0] pattern(input integer y,input integer x);
        pattern=(y*16'h031d)^(x*16'h9e37)^16'h15a7;
    endfunction
    integer beat,lane,row,col,transactions=0,errors=0;
    initial begin
        wait(rst);
        forever begin
            @(posedge dc);
            if(command) begin
                if(len!==80 || addr[21:0]%1280!=0 || addr[21:0]/640>=720)
                    $fatal(1,"Bad stride/line transaction addr=%h len=%0d",addr,len);
                row=addr[21:0]/640;
                repeat(2) @(negedge dc);
                if(row==8 && DELAY_NS!=0) begin #(DELAY_NS); @(negedge dc); end
                for(beat=0;beat<80;beat=beat+1) begin
                    if(beat%9==7) repeat(3) @(negedge dc);
                    for(lane=0;lane<16;lane=lane+1) data[lane*16+:16]=pattern(row,beat*16+lane);
                    ren=1; done=(beat==79);
                    @(negedge dc); ren=0; done=0;
                end
                transactions=transactions+1;
            end
        end
    end
    integer x=0,y=0,pixels=0,frames=0;
    reg vd=0;
    always @(posedge pc) begin
        #2;
        if(trst) begin
            if(valid !== (image && (!QUARTER || (px<400 && py<240)))) $fatal(1,"RGB and panel timing not aligned");
            if(valid) begin
                if(pixel !== pattern(y*(QUARTER ? 4 : 2),x*(QUARTER ? 4 : 2))) begin
                  errors++;
                  if(!LEGACY) $fatal(1,"M2 reader mismatch q=%0d x=%0d y=%0d got=%h",QUARTER,x,y,pixel);
                end
                x=x+1; pixels=pixels+1;
            end else if(vd) begin
                if(x!=(QUARTER ? 320 : 640)) $fatal(1,"Row width %0d",x);
                x=0; y=y+1;
                if(y==(QUARTER ? 180 : 360)) begin
                    y=0; frames=frames+1;
                    if(frames==2) begin
                        if(LEGACY && errors==0 && DELAY_NS!=0) $fatal(1,"baseline delay did not distinguish");
                        $display("M2_READER_PASS quarter=%0d legacy=%0d delay_ns=%0d frames=2 pixels=%0d transactions=%0d mismatches=%0d",QUARTER,LEGACY,DELAY_NS,pixels,transactions,errors);
                        $finish;
                    end
                end
            end
            vd=valid;
        end
    end
    initial begin
        #100; grs=1;
        #200; rst=1;
        repeat(100) @(negedge pc); trst=1;
    end
    initial begin #50000000; $fatal(1,"Reader timeout"); end
endmodule
