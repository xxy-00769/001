`timescale 1ns/1ps
module ram_smoke_tb;
    reg wc=0,rc=0,grs=0,rst=1,we=0;
    reg [31:0] wd=0;
    reg [11:0] wa=0;
    wire [255:0] q;
    integer i;
    always #13 wc=~wc;
    always #5 rc=~rc;
    GTP_GRS GRS_INST(.GRS_N(grs));
    wr_fram_buf dut(.wr_data(wd),.wr_addr(wa),.wr_en(we),.wr_clk(wc),.wr_rst(rst),
                    .rd_addr(9'd0),.rd_data(q),.rd_clk(rc),.rd_rst(rst));
    initial begin
        #100; grs=1;
        #100; rst=0;
        for(i=0;i<8;i=i+1) begin
            @(negedge wc); wd=32'h12340000+i; wa=i; we=1;
        end
        @(negedge wc); we=0;
        repeat(10) @(negedge rc);
        for(i=0;i<8;i=i+1)
            if(q[i*32+:32] !== 32'h12340000+i) $fatal(1,"RAM_SMOKE_FAIL lane=%0d data=%h",i,q[i*32+:32]);
        $display("RAM_SMOKE_PASS eight_words=8 original_DRM_primitive=1");
        $finish;
    end
endmodule
