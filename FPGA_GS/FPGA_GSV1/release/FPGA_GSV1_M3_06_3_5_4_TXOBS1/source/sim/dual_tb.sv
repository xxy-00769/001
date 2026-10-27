`timescale 1ns/1ps
module dual_tb #(parameter HEIGHT=720);
    reg grs_n=0; GTP_GRS GRS_INST(.GRS_N(grs_n));
    initial #100 grs_n=1;
    reg clk=0, rst=0;
    always #5 clk=~clk;
    initial #500 rst=1;
    wire [55:0] saw,sar;
    wire [7:0] swlen,srlen;
    wire [1:0] swv,srv,swr,srr,sready,slast,svalid,srlast,done,stall,bad_capture;
    wire [511:0] swdata;
    wire [27:0] aw,ar; wire [3:0] wl,rl;
    wire awv,arv; wire [255:0] wd;
    reg awr=0,arr=0,wr=0,last=0,rv=0,rlast=0;
    reg [255:0] rd=0;
    dual_ddr_arbiter dut(.clk(clk),.rst_n(rst),
        .s_awaddr(saw),.s_awlen(swlen),.s_awvalid(swv),.s_awready(swr),
        .s_wdata(swdata),.s_wstrb(64'hffffffffffffffff),.s_wready(sready),.s_wlast(slast),
        .s_araddr(sar),.s_arlen(srlen),.s_arvalid(srv),.s_arready(srr),
        .s_rvalid(svalid),.s_rlast(srlast),.awaddr(aw),.awlen(wl),.awvalid(awv),.awready(awr),
        .wdata(wd),.wstrb(),.wready(wr),.wlast(last),.araddr(ar),.arlen(rl),
        .arvalid(arv),.arready(arr),.rvalid(rv),.rlast(rlast));
    genvar g;
    generate for(g=0;g<2;g=g+1) begin: cam
        camera_case #(.SOURCE(g),.HEIGHT(HEIGHT)) source(
            .awaddr(saw[g*28+:28]),.araddr(sar[g*28+:28]),
            .awlen(swlen[g*4+:4]),.arlen(srlen[g*4+:4]),.awvalid(swv[g]),.arvalid(srv[g]),
            .wdata(swdata[g*256+:256]),.awready(swr[g]),.wready(sready[g]),.wlast(slast[g]),
            .arready(srr[g]),.rvalid(svalid[g]),.rlast(srlast[g]),.rdata(rd),
            .stall_reads(stall[g]),.finished(done[g]),.bad_capture(bad_capture[g]));
    end endgenerate
    reg [255:0] memory[0:230399];
    function integer idx(input [27:0] address);
        begin
            if(address[27:24]!=0 || address[21:0]>=460800 || address[2:0]!=0)
                $fatal(1,"Bad DDR frame address %h",address);
            idx=address[23]*115200+address[22]*57600+address[21:0]/8;
        end
    endfunction
    function [15:0] expected(input integer src,tag,row,col);
        expected=((src*16'h4ac3)^(tag*16'h19d7)^(row*16'h031d)^(col*16'h9e37))&16'hffff;
    endfunction
    integer skip_oracle;
    integer base,n,beat,src,tag,row,col,lane,write_pixels=0,errors=0,bursts=0;
    initial begin
        wait(rst);
        forever begin
            @(negedge clk); awr=1;
            do @(posedge clk); while(!awv);
            base=idx(aw); n=wl+1; src=aw[23];
            skip_oracle=bad_capture[src];
            tag=src ? cam[1].source.dut.owner.active_id : cam[0].source.dut.owner.active_id;
            row=aw[21:0]/640; col=(aw[21:0]%640)*2;
            @(negedge clk); awr=0;
            repeat(3+bursts%4) @(negedge clk);
            for(beat=0;beat<n;beat=beat+1) begin
                if(beat%5==3 || beat==n-1) repeat(3) @(negedge clk);
                wr=1; last=beat==n-1;
                @(posedge clk);
                if(sready!==(src ? 2'b10 : 2'b01)) $fatal(1,"Write response crossed source");
                memory[base+beat]=wd;
                for(lane=0;lane<16;lane=lane+1) begin
                    if(!skip_oracle && wd[lane*16+:16]!==expected(src,tag,row,col+beat*16+lane)) begin
                        if(errors<4) $display("WRITE_MISMATCH src=%0d tag=%0d row=%0d col=%0d got=%h expected=%h",
                            src,tag,row,col+beat*16+lane,wd[lane*16+:16],expected(src,tag,row,col+beat*16+lane));
                        errors=errors+1;
                    end
                    write_pixels=write_pixels+1;
                end
                @(negedge clk); wr=0; last=0;
            end
            bursts=bursts+1;
        end
    end
    integer rb,rn,rr,rs,read_bursts=0;
    initial begin
        wait(rst);
        forever begin
            @(negedge clk); arr=1;
            do @(posedge clk); while(!arv);
            rb=idx(ar); rn=rl+1; rs=ar[23];
            @(negedge clk); arr=0;
            while(stall[rs]) @(negedge clk);
            repeat(2+read_bursts%3) @(negedge clk);
            for(rr=0;rr<rn;rr=rr+1) begin
                if(rr==rn-1 || rr%5==3) repeat(4) @(negedge clk);
                rd=memory[rb+rr]; rv=1; rlast=rr==rn-1;
                @(posedge clk);
                if(svalid!==(rs ? 2'b10 : 2'b01)) $fatal(1,"Read response crossed source");
                @(negedge clk); rv=0; rlast=0;
            end
            read_bursts=read_bursts+1;
        end
    end
    initial begin
        wait(&done);
        if(errors!=0) $fatal(1,"DDR write oracle errors %0d",errors);
        $display("DUAL_PASS sources=2 frames=%0d output_pixels=%0d write_pixels=%0d write_bursts=%0d read_bursts=%0d errors=0",(HEIGHT>8 ? 2 : 12),(HEIGHT>8 ? 2 : 12)*640*(HEIGHT/2),write_pixels,bursts,read_bursts);
        $finish;
    end
    initial begin #400000000; $fatal(1,"dual timeout"); end
endmodule
