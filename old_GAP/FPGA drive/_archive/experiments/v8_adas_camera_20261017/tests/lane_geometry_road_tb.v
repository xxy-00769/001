`timescale 1ns/1ps
module lane_geometry_road_tb;
    localparam W=1280,H=720;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,de=0,vs=0;
    reg [1:0] marks=0;
    wire valid;
    wire [255:0] snapshot;
    lane_geometry dut(.clk(clk),.rst_n(rst_n),.de(de),.vs(vs),.white_mark(marks[1]),.yellow_mark(marks[0]),
        .zebra_candidate(1'b0),.zebra_confirmed(1'b0),.zebra_y0(11'd0),.zebra_y1(11'd0),
        .result_valid(valid),.snapshot(snapshot),.frame_id(),.flags(),.left_kind(),.right_kind(),.departure(),.offset_px(),.lane_width(),
        .left_x0(),.left_y0(),.left_x1(),.left_y1(),.right_x0(),.right_y0(),.right_x1(),.right_y1(),.left_support(),.right_support());
    reg [31:0] vectors[0:W*H-1];
    reg [255:0] expected[0:2];
    reg [1023:0] path;
    integer frame,row,col,results=0;
    always @(posedge clk) begin
        #1;
        if(rst_n && valid) begin
            if(snapshot!==expected[results]) $fatal(1,"Road %0d got %h expected %h",results+1,snapshot,expected[results]);
            results=results+1;
            $display("PASS road_%0d geometry: flags=%h kinds=%h offset=%d",results,snapshot[7:0],snapshot[11:8],$signed(snapshot[47:32]));
        end
    end
    initial begin
        $readmemh("output/adas/roads_snapshots.hex",expected);
        repeat(4) @(negedge clk);
        rst_n=1;
        for(frame=0;frame<3;frame=frame+1) begin
            $sformat(path,"output/road_%0d.hex",frame+1);
            $readmemh(path,vectors);
            @(negedge clk); vs=1; de=0;
            repeat(4) @(negedge clk);
            vs=0;
            for(row=0;row<H;row=row+1) begin
                for(col=0;col<W;col=col+1) begin @(negedge clk); de=1; marks=vectors[row*W+col][1:0]; end
                @(negedge clk); de=0; marks=0;
            end
            repeat(8) @(negedge clk);
        end
        if(results!=3) $fatal(1,"Missing results");
        $display("PASS: 3 road geometry results match independent frame model; 2764800 mask pixels");
        $finish;
    end
endmodule
