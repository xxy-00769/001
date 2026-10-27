`timescale 1ns/1ps
// Existing user road examples have no visible crosswalks. These are negatives,
// not a labelled evaluation set or evidence for general recognition accuracy.
module zebra_road_tb;
    localparam W=1280,H=720;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,de=0,vs=0;
    reg [15:0] rgb=0;
    wire valid,candidate,confirmed;
    zebra_detect dut (
        .clk(clk),.rst_n(rst_n),.de(de),.vs(vs),.rgb_in(rgb),
        .result_valid(valid),.candidate(candidate),.confirmed(confirmed),
        .box_x0(),.box_y0(),.box_x1(),.box_y1(),.stripes()
    );
    reg [31:0] vectors[0:W*H-1];
    integer frame,row,col,results=0;
    always @(posedge clk) begin
        #1;
        if(rst_n && valid) begin
            if(candidate!==0 || confirmed!==0) $fatal(1,"False candidate in road_%0d",results+1);
            results=results+1;
        end
    end
    initial begin
        repeat(8) @(negedge clk);
        rst_n=1;
        for(frame=0;frame<3;frame=frame+1) begin
            case(frame)
                0: $readmemh("output/road_1.hex",vectors);
                1: $readmemh("output/road_2.hex",vectors);
                2: $readmemh("output/road_3.hex",vectors);
            endcase
            @(negedge clk); vs=1; de=0;
            repeat(4) @(negedge clk);
            vs=0;
            for(row=0;row<H;row=row+1) begin
                for(col=0;col<W;col=col+1) begin
                    @(negedge clk); de=1; rgb=vectors[row*W+col][31:16];
                end
                @(negedge clk); de=0;
            end
            repeat(4) @(negedge clk);
            if(results!=frame+1) $fatal(1,"Missing frame result");
            $display("PASS: road_%0d no crosswalk candidate",frame+1);
        end
        $display("PASS: 3 existing road negatives, 2764800 pixels");
        $finish;
    end
endmodule
