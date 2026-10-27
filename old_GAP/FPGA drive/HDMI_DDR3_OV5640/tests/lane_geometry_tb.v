`timescale 1ns/1ps
module lane_geometry_tb;
    localparam W=320,H=256;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,de=0,vs=0,white=0,yellow=0,zc=0,zf=0;
    reg [10:0] zy0=0,zy1=0;
    wire valid;
    wire [255:0] snapshot;
    lane_geometry #(.H_ACTIVE(W),.V_ACTIVE(H),.ROI_Y0(32),.BAND0(48),.BAND_STEP(48)) dut (
        .clk(clk),.rst_n(rst_n),.de(de),.vs(vs),.white_mark(white),.yellow_mark(yellow),
        .zebra_candidate(zc),.zebra_confirmed(zf),.zebra_y0(zy0),.zebra_y1(zy1),
        .result_valid(valid),.snapshot(snapshot),.frame_id(),.flags(),.left_kind(),.right_kind(),
        .departure(),.offset_px(),.lane_width(),.left_x0(),.left_y0(),.left_x1(),.left_y1(),
        .right_x0(),.right_y0(),.right_x1(),.right_y1(),.left_support(),.right_support()
    );
    integer results=0,cases=0;
    always @(posedge clk) begin #1; if(rst_n && valid) results=results+1; end
    task idle;
        input integer n;
        integer i;
        begin for(i=0;i<n;i=i+1) begin @(negedge clk); de=0; white=0; yellow=0; end end
    endtask
    task sync_frame;
        begin @(negedge clk); de=0; vs=1; idle(3); @(negedge clk); vs=0; idle(4); end
    endtask
    task run_case;
        input [8*60-1:0] name;
        input integer shape,shift,expected_flags,expected_kinds,expected_warning,expected_offset;
        integer row,col,old_results,extra;
        reg active_row,left_pixel,right_pixel;
        begin
            old_results=results;
            sync_frame;
            for(row=0;row<H;row=row+1) begin
                for(col=0;col<W-(shape==7 && row==20);col=col+1) begin
                    active_row=row>=32 && row<248;
                    if(shape==1) active_row=active_row && (row<83 || (row>=100 && row<151) || row>=178);
                    if(shape==5) active_row=active_row && row>=178;
                    if(shape==6) active_row=active_row && !(row>=188 && row<=195);
                    if(shape==8) active_row=row<28;
                    left_pixel=active_row && col>=78+shift && col<=82+shift;
                    right_pixel=active_row && col>=238+shift && col<=242+shift;
                    if(shape==2) right_pixel=0;
                    if(shape==3) left_pixel=0;
                    if(shape==4 || shape==8) begin left_pixel=0; right_pixel=0; end
                    if(shape==9) begin
                        left_pixel=0; right_pixel=0;
                        for(extra=0;extra<8;extra=extra+1)
                            if(active_row && col>=38+extra*34 && col<=42+extra*34) left_pixel=1;
                    end
                    if(shape==10) begin
                        left_pixel=active_row && col>=100 && col<180;
                        right_pixel=active_row && col>=238 && col<=242;
                    end
                    if(shape==11) begin
                        left_pixel=active_row && col>=128 && col<=132;
                        right_pixel=active_row && col>=188 && col<=192;
                    end
                    @(negedge clk); de=1;
                    white=left_pixel || right_pixel; yellow=0;
                end
                idle(1+row%3);
            end
            idle(40);
            if(results!=old_results+1 || snapshot[7:0]!==expected_flags
               || snapshot[11:8]!==expected_kinds || snapshot[13:12]!==expected_warning
               || $signed(snapshot[47:32])!==expected_offset)
                $fatal(1,"%0s: flags=%h kinds=%h warn=%d off=%d results=%0d; expected %h/%h/%d/%d",name,
                       snapshot[7:0],snapshot[11:8],snapshot[13:12],$signed(snapshot[47:32]),results-old_results,
                       expected_flags,expected_kinds,expected_warning,expected_offset);
            if(snapshot[2] && (snapshot[63:48]!==160 || snapshot[111:96]!==80+shift || snapshot[175:160]!==240+shift))
                $fatal(1,"%0s: near endpoints or lane width incorrect",name);
            if(!snapshot[2] && snapshot[63:32]!==0) $fatal(1,"Invalid pair retained width/offset");
            if(snapshot[31:16]!==results) $fatal(1,"Frame ID mismatch");
            cases=cases+1;
            $display("PASS %0d: %0s",cases,name);
        end
    endtask
    integer row,col,old_results;
    initial begin
        idle(8); @(negedge clk); rst_n=1;
        run_case("centered continuous",0,0,'h47,'h5,0,0);
        run_case("camera right first frame",0,-32,'h47,'h5,0,32);
        run_case("camera right second frame",0,-32,'h47,'h5,0,32);
        run_case("camera right third frame",0,-32,'h47,'h5,2,32);
        run_case("centered clears immediately",0,0,'h47,'h5,0,0);
        run_case("camera left first frame",0,32,'h47,'h5,0,-32);
        run_case("camera left second frame",0,32,'h47,'h5,0,-32);
        run_case("camera left third frame",0,32,'h47,'h5,1,-32);
        run_case("left only clears pair and warning",2,0,'h41,'h1,0,0);
        run_case("right only",3,0,'h42,'h4,0,0);
        run_case("blank clears all",4,0,'h40,0,0,0);
        run_case("repeated painted segments",1,0,'h47,'hA,0,0);
        run_case("one short segment is not a lane",5,0,'h40,0,0,0);
        run_case("missing near band disables offset",6,0,'h43,'h5,0,0);
        run_case("malformed frame",7,0,'h60,0,0,0);
        run_case("above ROI",8,0,'h40,0,0,0);
        run_case("too many narrow runs",9,0,'h40,0,0,0);
        run_case("wide left blob rejected",10,0,'h42,'h4,0,0);
        run_case("implausibly narrow pair",11,0,'h43,'h5,0,0);
        zc=1; zf=1; zy0=140; zy1=200;
        run_case("crosswalk vetoes intersected bands",0,0,'h58,0,0,0);
        zc=0; zf=0;
        run_case("reacquire after crosswalk",0,0,'h47,'h5,0,0);
        old_results=results;
        sync_frame;
        for(row=0;row<200;row=row+1) begin
            for(col=0;col<W;col=col+1) begin @(negedge clk); de=1; white=(col==80 || col==240); end
            idle(2);
        end
        sync_frame;
        if(results!=old_results+1 || snapshot[7:0]!==8'h60 || snapshot[255:32]!==0)
            $fatal(1,"Interrupted frame retained stale state");
        old_results=results;
        idle(12000);
        if(results!=old_results) $fatal(1,"Blanking created results");
        @(negedge clk); rst_n=0; idle(4);
        if(snapshot!==256'h40 || valid!==0) $fatal(1,"Reset did not invalidate results");
        $display("PASS: %0d geometry cases plus interruption, blanking and reset",cases);
        $finish;
    end
    initial begin #30000000; $fatal(1,"Timeout"); end
endmodule
