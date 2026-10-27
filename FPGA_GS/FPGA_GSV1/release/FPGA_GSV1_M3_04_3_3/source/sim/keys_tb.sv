`timescale 1ns/1ps
module keys_tb;
    reg clk=0,pc=0,rst=0,fs=0;
    always #10 clk=~clk;
    always #17 pc=~pc;
    reg [5:0] key=63;
    wire [3:0] led; wire request,selected; wire [5:0] pressed;
    m1_keys #(.DEBOUNCE_CYCLES(4)) dut(.clk(clk),.rst_n(rst),.key_n(key),
        .intent_led(led),.view_request(request),.pressed(pressed));
    m1_view_select select_view(.clk(pc),.rst_n(rst),.frame_sync(fs),
        .view_request(request),.selected_view(selected));
    reg [9:0] x=12; reg [8:0] y=12;
    wire area,pixel;
    m1_osd osd(.x(x),.y(y),.rear(selected),.area(area),.pixel(pixel));
    integer counts[0:4]; integer i,checks=0;
    always @(posedge clk) if(rst) for(integer j=0;j<5;j=j+1) if(pressed[j]) counts[j]++;
    task check(input bit condition,input [255:0] message);
        begin checks++; if(!condition) $fatal(1,"%s",message); end
    endtask
    task hold_key(input integer index);
        begin @(negedge clk); key[index]=0; repeat(12) @(negedge clk); end
    endtask
    task release_key(input integer index);
        begin @(negedge clk); key[index]=1; repeat(12) @(negedge clk); end
    endtask
    task boundary;
        begin @(negedge pc); fs=1; repeat(8) @(negedge pc); fs=0; end
    endtask
    initial begin
        for(i=0;i<5;i++) counts[i]=0;
        #100; rst=1; repeat(12) @(negedge clk);
        check(led==8 && selected==0,"reset front / stop");
        for(i=0;i<3;i++) begin hold_key(i); check(led==(1<<i),"intent mapping"); release_key(i); end
        hold_key(3); hold_key(0); check(led==8,"held stop priority"); release_key(0); release_key(3);
        repeat(3) begin @(negedge clk); key[4]=0; @(negedge clk); key[4]=1; end
        repeat(10) @(negedge clk); check(counts[4]==0,"bounce ignored");
        hold_key(4); check(request==1 && selected==0,"change deferred until SOF");
        boundary; check(selected==1,"rear committed on SOF");
        repeat(40) @(negedge clk); boundary;
        check(selected==1 && counts[4]==1,"long hold one event");
        release_key(4); hold_key(4); check(selected==1,"no midframe switch");
        boundary; check(selected==0 && counts[4]==2,"second press front");
        release_key(4);
        x=11; #1; check(!area,"OSD left bound");
        x=12; y=12; #1; check(area,"OSD origin");
        x=44; #1; check(!area,"OSD right bound");
        x=12; y=28; #1; check(!area,"OSD bottom bound");
        $display("KEYS_PASS checks=%0d key5_events=%0d",checks,counts[4]); $finish;
    end
endmodule
