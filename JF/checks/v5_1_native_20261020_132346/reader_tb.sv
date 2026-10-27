`timescale 1ns/1ps
module reader_tb;
    reg dc=0,pc=0,rst=0,trst=0,grs=0,manual_fs=0;
    always #5 dc=~dc;
    always #16.9230769 pc=~pc;
    GTP_GRS GRS_INST(.GRS_N(grs));
    wire fs,req,hs,vs,de,image,valid;
    wire [15:0] pixel;
    wire [27:0] addr;
    wire [31:0] len;
    wire command;
    wire done,ren,ready;
    wire [255:0] data;
    mpi7001_timing timing(.clk(pc),.rst_n(trst),.frame_sync(fs),.read_request(req),
        .hs(hs),.vs(vs),.de(de),.image_area(image),.diagnostic_rgb());
    rd_buf #(.ADDR_WIDTH(28),.H_NUM(1280),.V_NUM(360),.PIX_WIDTH(16),
             .LINE_ADDR_WIDTH(22),.FRAME_CNT_WIDTH(6),.DISPLAY_HALF(1)) dut(
        .ddr_clk(dc),.ddr_rstn(rst),.vout_clk(pc),.rd_fsync(fs),
        .rd_en(req),.vout_de(valid),.vout_data(pixel),.init_done(1'b1),
        .ddr_rreq(command),.ddr_raddr(addr),.ddr_rd_len(len),.ddr_rrdy(ready),
        .ddr_rdone(done),.ddr_rdata(data),.ddr_rdata_en(ren));
    function [15:0] pattern(input integer y,input integer x);
        pattern=(y*16'h031d)^(x*16'h9e37)^16'h15a7;
    endfunction

    wire [27:0] native_addr;
    wire [3:0] native_len;
    wire native_valid;
    reg native_ready=0, native_rvalid=0, native_rlast=0;
    reg [255:0] native_data=0;
    wr_rd_ctrl_top #(.MEM_DQ_WIDTH(32)) controller (
        .clk(dc),.rstn(rst),
        .wr_cmd_en(1'b0),.wr_cmd_addr(28'd0),.wr_cmd_len(32'd80),
        .wr_ctrl_data(256'd0),.axi_awready(1'b0),.axi_wready(1'b0),
        .axi_wlast(1'b0),.axi_bid(4'd0),.axi_bresp(2'd0),.axi_bvalid(1'b0),
        .rd_cmd_en(command),.rd_cmd_addr(addr),.rd_cmd_len(len),
        .rd_cmd_ready(ready),.rd_cmd_done(done),
        .read_ready(1'b1),.read_rdata(data),.read_en(ren),
        .axi_araddr(native_addr),.axi_arlen(native_len),
        .axi_arvalid(native_valid),.axi_arready(native_ready),
        .axi_rdata(native_data),.axi_rvalid(native_rvalid),
        .axi_rlast(native_rlast),.axi_rid(4'd0),.axi_rresp(2'd0));
    integer beat,lane,row,col,transactions=0,base,burst_len,expected_base=0;
    always @(posedge dc) if(command) begin
        if(addr[21:0] !== expected_base || len !== 80 || !ready)
            $fatal(1,"Line command mismatch addr=%h expected=%h",addr,expected_base);
        expected_base=(expected_base==718*640) ? 0 : expected_base+1280;
    end
    initial begin
        wait(rst);
        forever begin
            @(negedge dc); native_ready=1;
            do @(posedge dc); while(!native_valid);
            base=native_addr[21:0]/8; burst_len=native_len+1;
            if(native_addr[2:0]!=0 || burst_len!=16)
                $fatal(1,"Native address/burst length");
            @(negedge dc); native_ready=0;
            repeat(2+transactions%7) @(negedge dc);
            for(beat=0;beat<burst_len;beat=beat+1) begin
                if(beat%5==3) repeat(3) @(negedge dc);
                row=(base+beat)/80; col=((base+beat)%80)*16;
                for(lane=0;lane<16;lane=lane+1)
                    native_data[lane*16+:16]=pattern(row,col+lane);
                native_rvalid=1; native_rlast=beat==burst_len-1;
                @(negedge dc); native_rvalid=0; native_rlast=0;
            end
            transactions=transactions+1;
        end
    end
    integer x=0,y=0,pixels=0,frames=0;
    reg vd=0;
    always @(posedge pc) begin
        #2;
        if(trst) begin
            if(valid !== image) $fatal(1,"RGB and panel timing not aligned");
            if(valid) begin
                if(pixel !== pattern(y*2,x*2))
                    $fatal(1,"Pixel mismatch frame=%0d x=%0d y=%0d got=%h expected=%h",frames,x,y,pixel,pattern(y*2,x*2));
                x=x+1; pixels=pixels+1;
            end else if(vd) begin
                if(x!=640) $fatal(1,"Row width %0d",x);
                x=0; y=y+1;
                if(y==360) begin
                    y=0; frames=frames+1;
                    $display("READER_FRAME_PASS frame=%0d pixels=230400 last_row=360 source_last_row=718 last_pixel_x=1278",frames); $fflush();
                    if(frames==2) begin
                        $display("READER_PASS frames=2 pixels=%0d errors=0 transactions=%0d",pixels,transactions);
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
