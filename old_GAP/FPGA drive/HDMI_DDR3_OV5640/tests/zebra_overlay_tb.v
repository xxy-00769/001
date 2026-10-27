`timescale 1ns/1ps
module zebra_overlay_tb;
    localparam W=160,H=96;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,de=0,vs=0,enable=1,valid=0,candidate=0,confirmed=0;
    reg [15:0] rgb=16'h1234;
    reg [10:0] x0=60,y0=50,x1=110,y1=80;
    wire [15:0] output_rgb;
    zebra_overlay #(.H_ACTIVE(W),.V_ACTIVE(H)) dut (
        .clk(clk),.rst_n(rst_n),.de(de),.vs(vs),.enable(enable),.rgb_in(rgb),
        .result_valid(valid),.candidate(candidate),.confirmed(confirmed),
        .box_x0(x0),.box_y0(y0),.box_x1(x1),.box_y1(y1),.rgb_out(output_rgb)
    );
    integer frame,row,col,pixels=0;
    reg [15:0] expected;
    initial begin
        repeat(4) @(negedge clk);
        rst_n=1;
        for(frame=0;frame<5;frame=frame+1) begin
            @(negedge clk); vs=1; de=0;
            // Exercise same-clock result and VS acceptance on frame 1.
            valid=frame==1; candidate=frame==1; confirmed=0;
            @(negedge clk); vs=0; valid=0;
            for(row=0;row<H;row=row+1) begin
                for(col=0;col<W;col=col+1) begin
                    @(negedge clk); de=1;
                    enable=frame!=4;
                    valid=row==45 && col==10;
                    if(valid) begin candidate=frame<2; confirmed=frame==1; end
                    expected=16'h1234;
                    if(frame!=4) begin
                        if(col>=16 && col<48 && row>=16 && row<40 && col%8<4)
                            expected=frame==1 ? 16'hFD20 : (frame==2 ? 16'hF81F : 16'h8410);
                        else if(frame==2 && col>=60 && col<=110 && row>=50 && row<=80
                                && (col==60 || col==110 || row==50 || row==80)) expected=16'hF81F;
                    end
                    #1;
                    if(output_rgb!==expected) $fatal(1,"Frame %0d pixel %0d,%0d: got %h expected %h",frame,col,row,output_rgb,expected);
                    pixels=pixels+1;
                end
                @(negedge clk); de=0; valid=0;
                #1;
                if(output_rgb!==rgb) $fatal(1,"Paint in blanking");
            end
        end
        $display("PASS: zebra overlay %0d pixels, frame-frozen results, no fill, disable and blanking",pixels);
        $finish;
    end
endmodule
