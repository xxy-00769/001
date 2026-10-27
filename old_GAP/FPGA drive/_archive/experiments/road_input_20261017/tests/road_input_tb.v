`timescale 1ns/1ps
module road_input_tb #(
    parameter W=64, H=32
);
    localparam OW=W/8, OH=H/8, N=OW*OH;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, de=0, vs=0, release_frame=0, read_en=0;
    reg [15:0] rgb=0;
    reg [13:0] read_addr=0;
    wire read_valid, available;
    wire [15:0] data;
    wire [31:0] frame_id, dropped, invalid;
    road_input_buffer #(.H_ACTIVE(W),.V_ACTIVE(H)) dut (
        .clk(clk),.rst_n(rst_n),.de(de),.vs(vs),.rgb(rgb),
        .release_frame(release_frame),.read_en(read_en),.read_addr(read_addr),
        .read_valid(read_valid),.read_data(data),.frame_available(available),
        .frame_id(frame_id),.dropped_frames(dropped),.invalid_frames(invalid)
    );
    reg [31:0] a[0:W*H-1], b[0:W*H-1];
    reg [2047:0] path_a, path_b;
    integer errors=0, reads=0, thumbnails=0, variant=0;
    integer index, expected_pixel, k, test_case;
    reg check_thumbnail=0;
    always @(posedge clk) begin
        #1;
        if (rst_n && dut.pv && check_thumbnail) begin
            thumbnails=thumbnails+1;
            if (dut.px>=OW || dut.py>=OH) $fatal(1,"Thumbnail coordinate out of range");
            index=((dut.py*8+7)*W)+(dut.px*8+7);
            expected_pixel=variant ? b[index][15:0] : a[index][15:0];
            if (dut.value !== expected_pixel[15:0]) begin
                if (errors<8) $display("Thumbnail mismatch x=%0d y=%0d got=%h expected=%h",dut.px,dut.py,dut.value,expected_pixel[15:0]);
                errors=errors+1;
            end
        end
    end
    task idle;
        input integer n;
        integer t;
        begin
            for(t=0;t<n;t=t+1) begin @(negedge clk); de=0; rgb=0; end
        end
    endtask
    task start_frame;
        begin
            idle(5);
            @(negedge clk); vs=1;
            idle(3);
            @(negedge clk); vs=0;
            idle(5);
        end
    endtask
    task reset;
        begin
            @(negedge clk); rst_n=0; de=0; vs=0; read_en=0; release_frame=0;
            idle(5);
            @(negedge clk); rst_n=1;
            idle(4);
            if(available || read_valid || data!=0) $fatal(1,"Reset leaked stale data");
        end
    endtask
    task rows;
        input integer first, last, v, defect;
        integer yy,xx,limit,addr;
        begin
            variant=v;
            for(yy=first;yy<last;yy=yy+1) begin
                limit=W;
                if(yy==H/2 && defect==1) limit=W-1;
                if(yy==H/2 && defect==2) limit=W+1;
                for(xx=0;xx<limit;xx=xx+1) begin
                    addr=(yy%H)*W+(xx%W);
                    @(negedge clk); de=1; rgb=v ? b[addr][31:16] : a[addr][31:16];
                end
                idle(1+(yy%7));
            end
            idle(5);
        end
    endtask
    task read_frame;
        input integer v;
        integer n,addr;
        reg [15:0] want;
        begin
            for(n=0;n<N;n=n+1) begin
                addr=((n/OW)*8+7)*W+(n%OW)*8+7;
                want=v ? b[addr][15:0] : a[addr][15:0];
                @(negedge clk); read_en=1; read_addr=n;
                @(posedge clk); #2;
                if(!read_valid || data!==want) begin
                    if(errors<8) $display("Read mismatch at %0d: %h expected %h valid %b",n,data,want,read_valid);
                    errors=errors+1;
                end
                reads=reads+1;
            end
            @(negedge clk); read_addr=N;
            @(posedge clk); #2;
            if(read_valid || data!=0) $fatal(1,"Out-of-range read was accepted");
            @(negedge clk); read_en=0;
        end
    endtask
    task release_snapshot;
        begin
            @(negedge clk); release_frame=1; read_en=1; read_addr=0;
            @(posedge clk); #2;
            if(available || read_valid || data!=0) $fatal(1,"Release/read collision exposed data");
            @(negedge clk); release_frame=0; read_en=0;
            idle(2);
        end
    endtask
    task start_with_release;
        input integer publishing;
        begin
            idle(5);
            @(negedge clk); vs=1;
            @(posedge clk); #2;
            @(negedge clk); release_frame=1; read_en=1; read_addr=0;
            @(posedge clk); #2;
            if(read_valid || data!=0 || available!==publishing[0])
                $fatal(1,"Frame-boundary release priority mismatch");
            @(negedge clk); release_frame=0; read_en=0; vs=0;
            idle(5);
        end
    endtask
    initial begin
        if(!$value$plusargs("A=%s",path_a) || !$value$plusargs("B=%s",path_b)) $fatal(1,"Missing vectors");
        $readmemh(path_a,a); $readmemh(path_b,b);
        reset;
        check_thumbnail=1;
        start_frame;
        rows(0,H,0,0);
        if(available) $fatal(1,"Published before frame dimensions were sealed");
        start_frame;
        if(!available || frame_id!=1) $fatal(1,"First frame did not publish");
        read_frame(0);
        rows(0,H,1,0);
        read_frame(0);
        start_frame;
        if(frame_id!=1 || dropped!=1) $fatal(1,"Held frame was replaced");
        rows(0,H/2,1,0);
        release_snapshot;
        rows(H/2,H,1,0);
        start_frame;
        if(available || dropped!=2) $fatal(1,"Mid-frame release allowed partial capture");
        rows(0,H,1,0);
        start_frame;
        if(!available || frame_id!=4 || invalid!=0) $fatal(1,"New complete frame did not recover");
        read_frame(1);
        if(thumbnails!=4*N) $fatal(1,"Thumbnail count mismatch %0d",thumbnails);
        check_thumbnail=0;
        reset;
        // Empty, short row, long row, missing row, extra row, and VS/DE overlap.
        if(W==64) begin
            for(test_case=0;test_case<6;test_case=test_case+1) begin
                reset;
                start_frame;
                case(test_case)
                    0: idle(20);
                    1: rows(0,H,0,1);
                    2: rows(0,H,0,2);
                    3: rows(0,H-1,0,0);
                    4: rows(0,H+1,0,0);
                    5: begin @(negedge clk); vs=1; de=1; idle(3); @(negedge clk); vs=0; idle(5); end
                endcase
                start_frame;
                if(available || invalid==0) $fatal(1,"Malformed frame %0d published or not reported",test_case);
                check_thumbnail=1;
                rows(0,H,0,0);
                start_frame;
                if(!available) $fatal(1,"No recovery after malformed frame %0d",test_case);
                read_frame(0);
                check_thumbnail=0;
            end
            // Reset while a block is accumulating, with stale line/frame RAM.
            reset; start_frame; rows(0,3,1,0); reset; start_frame;
            check_thumbnail=1;
            rows(0,H,0,0); start_frame; read_frame(0); check_thumbnail=0;
            // Release coincident with publication must retain the new snapshot.
            reset; start_frame; check_thumbnail=1; rows(0,H,0,0);
            start_with_release(1); read_frame(0);
            rows(0,H,1,0);
            // Release of an old snapshot at the next FS permits a whole new frame.
            start_with_release(0); rows(0,H,1,0); start_frame;
            if(!available || frame_id!=3) $fatal(1,"Boundary release did not admit the new frame");
            read_frame(1); check_thumbnail=0;
            // The very first malformed sync is counted even without a prior frame.
            reset;
            @(negedge clk); vs=1; de=1;
            idle(3); @(negedge clk); vs=0; idle(5);
            if(invalid!=1 || available) $fatal(1,"First VS/DE overlap was not rejected");
            start_frame; check_thumbnail=1; rows(0,H,0,0); start_frame;
            if(!available) $fatal(1,"No recovery from first malformed sync");
            read_frame(0); check_thumbnail=0;
        end
        if(errors!=0) $fatal(1,"%0d errors",errors);
        $display("PASS: %0dx%0d input; %0d thumbnail pixels; %0d frozen reads; protected snapshots and complete-frame publication",W,H,thumbnails,reads);
        $finish;
    end
    initial begin #500000000; $fatal(1,"Test timeout"); end
endmodule
