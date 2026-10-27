`timescale 1ns/1ps
module overlay_tb;
    localparam W=400, H=80;
    reg clk=0, rst_n=0, de=0, vs=0;
    always #5 clk=~clk;
    reg [15:0] rgb_in=16'h39e7;
    reg test_mode=1, fresh=0, alarm=0;
    reg [1:0] decision=0, requested_direction=0, effective_direction=0;
    reg [15:0] source_frame=16'h1234;
    wire [15:0] rgb_out;
    lane_change_overlay #(.H_ACTIVE(W),.V_ACTIVE(H)) dut(.*);
    integer x,y,mode,fd,unchanged=0,red=0,yellow=0,arrow_pixels;
    reg [15:0] pixel;
    task start_frame;
        begin @(negedge clk); vs=1; @(negedge clk); vs=0; end
    endtask
    initial begin
        repeat(3) @(negedge clk);
        de=1; #1; if(rgb_out!==rgb_in) $fatal(1,"reset pass-through");
        de=0; rst_n=1;
        for(mode=0;mode<5;mode=mode+1) begin
            test_mode=(mode<2); fresh=(mode!=0); alarm=(mode==2);
            decision=mode==0?0:mode==1?2:mode==2?3:mode==3?2:1;
            requested_direction=mode==1 || mode==2 ? 1 : mode==3 ? 2:0;
            effective_direction=mode==1?1:mode==3?2:0;
            start_frame;
            case(mode)
                0:fd=$fopen("overlay_unknown.ppm","w");
                1:fd=$fopen("overlay_left.ppm","w");
                2:fd=$fopen("overlay_alarm.ppm","w");
                3:fd=$fopen("overlay_right.ppm","w");
                4:fd=$fopen("overlay_straight.ppm","w");
            endcase
            if(!fd) $fatal(1,"preview open");
            $fdisplay(fd,"P3\n%0d %0d\n255",W,H);
            arrow_pixels=0;
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W;x=x+1) begin
                    @(negedge clk); de=1;
                    rgb_in={x[4:0],y[5:0],5'd7};
                    // New state in mid-frame must not tear the displayed panel.
                    if(y==20 && x==0) begin
                        fresh=0; alarm=0; decision=0; test_mode=0;
                    end
                    #1;
                    if(dut.x!==x || dut.y!==y) $fatal(1,"pixel position %d,%d got %d,%d",x,y,dut.x,dut.y);
                    pixel=rgb_out;
                    if(x<80 || x>=384 || y<16 || y>=64) begin
                        if(pixel!==rgb_in) $fatal(1,"outside panel modified");
                        unchanged=unchanged+1;
                    end
                    if(mode==2 && y==63 && x>=80 && x<384 && pixel!==16'hf800)
                        $fatal(1,"frame atomic red border");
                    if(x>=328 && x<368 && y>=24 && y<56) begin
                        if(mode==0 && dut.arrow) $fatal(1,"unknown arrow");
                        if(dut.arrow) arrow_pixels=arrow_pixels+1;
                    end
                    if(pixel==16'hf800) red=red+1;
                    if(pixel==16'hffe0) yellow=yellow+1;
                    $fdisplay(fd,"%0d %0d %0d",
                        {pixel[15:11],3'b0},{pixel[10:5],2'b0},{pixel[4:0],3'b0});
                end
                @(negedge clk); de=0; #1;
                if(rgb_out!==rgb_in) $fatal(1,"blanking modified");
            end
            $fclose(fd);
            if(mode!=0 && arrow_pixels<60) $fatal(1,"missing arrow mode %0d",mode);
            if(dut.shown_test!==(mode<2)) $fatal(1,"test label tearing");
        end
        if(red<500 || yellow<300) $fatal(1,"missing status pixels");
        $display("PASS overlay: 160000 pixels, position, blank/reset, frame atomicity, 5 previews; unchanged=%0d",unchanged);
        $finish;
    end
    initial begin #5000000; $fatal(1,"overlay timeout"); end
endmodule
