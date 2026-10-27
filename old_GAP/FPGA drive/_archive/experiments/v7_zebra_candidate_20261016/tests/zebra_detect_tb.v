`timescale 1ns/1ps
module zebra_detect_tb #(parameter W=320);
    localparam H=96;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, de=0, vs=0;
    reg [15:0] rgb=0;
    wire valid, candidate, confirmed;
    wire [10:0] x0,y0,x1,y1;
    wire [4:0] stripes;
    zebra_detect #(.H_ACTIVE(W),.V_ACTIVE(H)) dut (
        .clk(clk),.rst_n(rst_n),.de(de),.vs(vs),.rgb_in(rgb),
        .result_valid(valid),.candidate(candidate),.confirmed(confirmed),
        .box_x0(x0),.box_y0(y0),.box_x1(x1),.box_y1(y1),.stripes(stripes)
    );
    integer results=0, cases=0;
    always @(posedge clk) begin
        #1;
        if(rst_n && valid) results=results+1;
    end
    task idle;
        input integer n;
        integer i;
        begin
            for(i=0;i<n;i=i+1) begin @(negedge clk); de=0; rgb=0; end
        end
    endtask
    task sync_frame;
        begin
            @(negedge clk); vs=1; de=0;
            idle(3);
            @(negedge clk); vs=0;
            idle(4);
        end
    endtask
    task run_case;
        input [8*48-1:0] name;
        input integer start_x,width,gap,bars,top,bottom,shift_rows,short_row;
        input [15:0] paint,background;
        input expected_candidate, expected_confirmed;
        integer row,col,bar,start,old_results;
        reg painted;
        begin
            old_results=results;
            sync_frame;
            for(row=0;row<H;row=row+1) begin
                for(col=0;col<W-(short_row && row==20);col=col+1) begin
                    painted=0;
                    start=start_x+((shift_rows && row%2) ? 40 : 0);
                    for(bar=0;bar<bars;bar=bar+1)
                        if(row>=top && row<=bottom && col>=start+bar*(width+gap)
                           && col<start+bar*(width+gap)+width) painted=1;
                    @(negedge clk); de=1; rgb=painted ? paint : background;
                end
                idle(1+row%5);
            end
            idle(100);
            if(results != old_results+1 || candidate !== expected_candidate || confirmed !== expected_confirmed)
                $fatal(1,"%0s: results=%0d candidate=%b confirmed=%b expected=%b/%b",name,
                       results-old_results,candidate,confirmed,expected_candidate,expected_confirmed);
            if(expected_candidate && (x0!==start_x || x1!==start_x+(bars-1)*(width+gap)+width-1
                                      || y0!==top || y1!==bottom || stripes!==bars))
                $fatal(1,"%0s: bbox %0d,%0d..%0d,%0d stripes=%0d",name,x0,y0,x1,y1,stripes);
            if(!expected_candidate && {x0,y0,x1,y1,stripes} !== 49'd0)
                $fatal(1,"%0s: stale geometry",name);
            cases=cases+1;
            $display("PASS case %0d: %0s",cases,name);
        end
    endtask
    integer i,j,old_results;
    initial begin
        idle(8); @(negedge clk); rst_n=1;
        if(W==1280) begin
            run_case("maximum width",300,160,8,4,40,55,0,0,16'hFFFF,16'h4228,1,0);
            run_case("over maximum width",300,161,8,4,40,55,0,0,16'hFFFF,16'h4228,0,0);
            run_case("maximum gap",300,40,160,4,40,55,0,0,16'hFFFF,16'h4228,1,0);
            run_case("over maximum gap",300,40,161,4,40,55,0,0,16'hFFFF,16'h4228,0,0);
            run_case("exact minimum span",300,40,32,4,40,55,0,0,16'hFFFF,16'h4228,1,0);
            run_case("below minimum span",300,40,31,4,40,55,0,0,16'hFFFF,16'h4228,0,0);
            run_case("three bars insufficient",300,80,80,3,40,55,0,0,16'hFFFF,16'h4228,0,0);
            $display("PASS: zebra detector %0d full-width limit cases",cases);
            $finish;
        end
        run_case("empty",64,16,16,0,40,55,0,0,16'hFFFF,16'h4228,0,0);
        run_case("first positive",64,16,16,4,40,55,0,0,16'hFFFF,16'h4228,1,0);
        run_case("second positive",64,16,16,4,40,55,0,0,16'hFFFF,16'h4228,1,1);
        run_case("yellow rejection and clearing",64,16,16,4,40,55,0,0,16'hFFE0,16'h4228,0,0);
        run_case("cyan rejection",64,16,16,4,40,55,0,0,16'h07FF,16'h4228,0,0);
        run_case("large white surface",32,250,16,1,40,70,0,0,16'hFFFF,16'h4228,0,0);
        run_case("two lane lines",64,16,80,2,40,70,0,0,16'hFFFF,16'h4228,0,0);
        run_case("above ROI",64,16,16,4,4,28,0,0,16'hFFFF,16'h4228,0,0);
        run_case("too narrow bars",64,11,16,4,40,55,0,0,16'hFFFF,16'h4228,0,0);
        run_case("minimum bar and gap widths",64,12,8,4,40,55,0,0,16'hFFFF,16'h4228,1,0);
        run_case("minimum widths confirmation",64,12,8,4,40,55,0,0,16'hFFFF,16'h4228,1,1);
        run_case("too narrow gaps",64,16,7,4,40,55,0,0,16'hFFFF,16'h4228,0,0);
        run_case("bright gaps without contrast",64,16,16,4,40,55,0,0,16'hFFFF,16'h8410,0,0);
        run_case("11 rows insufficient",64,16,16,4,40,50,0,0,16'hFFFF,16'h4228,0,0);
        run_case("12 rows sufficient",64,16,16,4,40,51,0,0,16'hFFFF,16'h4228,1,0);
        run_case("last row included, new location",64,16,16,4,84,95,0,0,16'hFFFF,16'h4228,1,0);
        run_case("last row confirmation",64,16,16,4,84,95,0,0,16'hFFFF,16'h4228,1,1);
        run_case("row discontinuity rejection",64,16,16,4,40,70,1,0,16'hFFFF,16'h4228,0,0);
        run_case("left candidate",40,16,16,4,40,55,0,0,16'hFFFF,16'h4228,1,0);
        run_case("disjoint candidate does not confirm",170,16,16,4,40,55,0,0,16'hFFFF,16'h4228,1,0);
        run_case("disjoint candidate next frame",170,16,16,4,40,55,0,0,16'hFFFF,16'h4228,1,1);
        run_case("malformed short row invalidates frame",64,16,16,4,40,55,0,1,16'hFFFF,16'h4228,0,0);
        run_case("after bad frame starts fresh",64,16,16,4,40,55,0,0,16'hFFFF,16'h4228,1,0);
        old_results=results;
        sync_frame;
        for(i=0;i<50;i=i+1) begin
            for(j=0;j<W;j=j+1) begin @(negedge clk); de=1; rgb=16'hFFFF; end
            idle(2);
        end
        sync_frame;
        if(results!=old_results+1 || candidate!==0 || confirmed!==0)
            $fatal(1,"Incomplete frame retained confirmation");
        old_results=results;
        idle(12000);
        if(results!=old_results) $fatal(1,"Blanking replayed result");
        @(negedge clk); rst_n=0;
        idle(2);
        if({candidate,confirmed,x0,y0,x1,y1,stripes} !== 51'd0) $fatal(1,"Reset failed");
        $display("PASS: zebra detector %0d complete-frame cases plus interrupted-frame, blanking and reset checks",cases);
        $finish;
    end
    initial begin #20000000; $fatal(1,"Timeout"); end
endmodule

module zebra_limits_tb;
    zebra_detect_tb #(.W(1280)) test();
endmodule
