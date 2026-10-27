`timescale 1ns/1ps
module video_tb;
reg grs_n=0;
GTP_GRS GRS_INST(.GRS_N(grs_n));
initial #100 grs_n=1;
reg clk=0, vin_clk=0, vout_clk=0;
always #5 clk=~clk;
always #13.468 vin_clk=~vin_clk;
real out_half=13.468;
always #(out_half) vout_clk=~vout_clk;
reg rst_n=0, ddr_init_done=0, acc_rst_n=0;
reg wr_fsync=0, wr_en=0, rd_fsync=0, rd_en=0;
reg [15:0] wr_data=0;
wire init_done, vout_de;
wire [15:0] vout_data;
reg mem_req_valid=0, mem_req_write=0, mem_rsp_ready=0;
wire mem_req_ready, mem_rsp_valid, mem_rsp_error, fault, idle;
reg [31:0] mem_req_addr=32'h00200000;
reg [127:0] mem_req_data=0;
reg [15:0] mem_req_strb=16'hffff;
reg [63:0] mem_req_tag=0;
wire [127:0] mem_rsp_data;
wire [63:0] mem_rsp_tag;
wire axi_awvalid, axi_awready, axi_arvalid, axi_arready, axi_awuser_ap, axi_aruser_ap;
wire axi_wready, axi_wusero_last, axi_rvalid, axi_rlast;
wire [27:0] axi_awaddr, axi_araddr;
wire [3:0] axi_awuser_id, axi_awlen, axi_aruser_id, axi_arlen, axi_wusero_id, axi_rid;
wire [255:0] axi_wdata, axi_rdata;
wire [31:0] axi_wstrb;
reg gapped=0;
video_ddr_probe dut(.*);
video_memory model(.*);
integer scenario=0, frames=0, camera_frame=0, epoch=0;
integer debug_commands=0;
integer pixels=0, errors=0, first_errors=0, checked_frames=0;
integer acc_done=0, acc_max_latency=0, video_max_wait=0;
integer acc_active_requests=0, reset_checks=0, total_frames=0;
integer ui_ticks=0, aw_wait=0, ar_wait=0;
integer write_checked=0, write_errors=0;
integer cam_pairs=0, write_consumed=0, read_supplied=0, read_consumed=0;
integer wr_peak=0, rd_peak=0, wr_min=8192, rd_min=8192;
integer frame_pixels=0, target_frame=0, out_x=0, out_y=0;
integer row_epoch[0:115199];
integer bank_frame[0:1];
reg monitor=0, output_started=0;
reg rd_fsync_last=0;
function [15:0] pattern(input integer f, input integer x, input integer y);
begin pattern=((f*16'h29a7) ^ (y*16'h031d) ^ (x*16'h9e37)) & 16'hffff; end
endfunction
task camera(input integer f);
integer x,y;
begin
    @(negedge vin_clk); wr_fsync=1; wr_en=0;
    repeat(1650*5) @(negedge vin_clk);
    wr_fsync=0;
    repeat(1650*20) @(negedge vin_clk);
    for(y=0;y<720;y=y+1) begin
        for(x=0;x<1280;x=x+1) begin
            wr_en=1; wr_data=pattern(f,x,y); @(negedge vin_clk);
        end
        wr_en=0;
        repeat(370) @(negedge vin_clk);
    end
    repeat(1650*5) @(negedge vin_clk);
end
endtask
task display_frame;
integer x,y;
begin
    @(negedge vout_clk); rd_fsync=1; rd_en=0;
    repeat(1650*5) @(negedge vout_clk);
    rd_fsync=0;
    repeat(1650*20) @(negedge vout_clk);
    for(y=0;y<720;y=y+1) begin
        for(x=0;x<1280;x=x+1) begin rd_en=1; @(negedge vout_clk); end
        rd_en=0; repeat(370) @(negedge vout_clk);
    end
    repeat(1650*5) @(negedge vout_clk);
end
endtask
task transaction(input bit write_op, input integer n);
integer start_tick;
reg [127:0] expected;
begin
    @(negedge clk);
    mem_req_write=write_op; mem_req_addr=32'h00200000+(n%128);
    expected={4{32'h56780000+n}};
    mem_req_data=expected; mem_req_tag={32'hade51200,32'(n)};
    mem_req_valid=1; start_tick=ui_ticks;
    do @(posedge clk); while(!mem_req_ready);
    @(negedge clk); mem_req_valid=0;
    wait(mem_rsp_valid);
    // Hold a completed response while the real framebuffer keeps running.
    repeat(37) @(negedge clk);
    if(mem_rsp_error || mem_rsp_tag!=={32'hade51200,32'(n)} ||
       (!write_op && mem_rsp_data!==expected)) $fatal(1,"Accelerator response mismatch");
    if(ui_ticks-start_tick>acc_max_latency) acc_max_latency=ui_ticks-start_tick;
    mem_rsp_ready=1;
    @(negedge clk); mem_rsp_ready=0; acc_done=acc_done+1;
end
endtask
integer i, f, beat_index, pixel_index, expected_f, bank, offset, occupancy;
reg [15:0] expected_pixel;
always @(posedge vin_clk) if(rst_n && wr_en) begin
    cam_pairs=cam_pairs+1;
    occupancy=cam_pairs-write_consumed;
    if(occupancy>wr_peak) wr_peak=occupancy;
end
always @(posedge clk) begin
    ui_ticks=ui_ticks+1;
    if(ui_ticks>25000000) $fatal(1,"Global timeout");
    if(rst_n && fault) $fatal(1,"Bridge fault");
    if(rst_n) begin
        if(mem_req_valid && mem_req_ready && (wr_en || rd_en))
            acc_active_requests=acc_active_requests+1;
        if(debug_commands<12 && ((axi_awvalid && axi_awready) || (axi_arvalid && axi_arready))) begin
            $display("COMMAND t=%0t wr=%0d aw=%h ar=%h len=%0d cam=%0d init=%b",
                $time,axi_awvalid && axi_awready,axi_awaddr,axi_araddr,
                axi_awvalid ? axi_awlen : axi_arlen,camera_frame,init_done);
            debug_commands=debug_commands+1;
        end
        if(dut.v_awvalid && !dut.v_awready) aw_wait=aw_wait+1; else aw_wait=0;
        if(dut.v_arvalid && !dut.v_arready) ar_wait=ar_wait+1; else ar_wait=0;
        if(aw_wait>video_max_wait) video_max_wait=aw_wait;
        if(ar_wait>video_max_wait) video_max_wait=ar_wait;
        if(dut.v_wready) begin
            write_consumed=write_consumed+16;
            occupancy=cam_pairs-write_consumed;
            if(occupancy>wr_peak) wr_peak=occupancy;
            if(occupancy<wr_min) wr_min=occupancy;
            offset=model.wa & 28'h03fffff;
            bank=model.wa[22];
            beat_index=offset>>3;
            expected_f=bank_frame[bank];
            for(i=0;i<16;i=i+1) begin
                pixel_index=beat_index*16+i;
                expected_pixel=pattern(expected_f,pixel_index%1280,pixel_index/1280);
                write_checked=write_checked+1;
                if(dut.v_wdata[i*16+:16]!==expected_pixel) begin
                    write_errors=write_errors+1;
                    if(first_errors<8) begin
                        $display("WRITE_MISMATCH tick=%0d frame=%0d pixel=%0d got=%h expected=%h",
                            ui_ticks,expected_f,pixel_index,dut.v_wdata[i*16+:16],expected_pixel);
                        first_errors=first_errors+1;
                    end
                end
            end
            row_epoch[bank*57600+beat_index]=expected_f;
        end
        if(dut.v_rvalid) begin
            read_supplied=read_supplied+16;
            occupancy=read_supplied-read_consumed;
            if(occupancy>rd_peak) rd_peak=occupancy;
        end
    end
end
always @(posedge vout_clk) begin
    #2;
    if(rd_fsync && !rd_fsync_last) begin
        if(output_started) begin
            if(frame_pixels!=921600) $fatal(1,"Output frame length %0d",frame_pixels);
            checked_frames=checked_frames+1;
        end
        output_started=1; frame_pixels=0; out_x=0; out_y=0;
        // Independent expected identity: display starts one camera period late.
        target_frame=epoch*10+checked_frames+1;
    end
    rd_fsync_last=rd_fsync;
    if(vout_de && monitor) begin
        expected_pixel=pattern(target_frame,out_x,out_y);
        pixels=pixels+1; frame_pixels=frame_pixels+1; read_consumed=read_consumed+1;
        occupancy=read_supplied-read_consumed;
        if(occupancy<rd_min) rd_min=occupancy;
        if(vout_data!==expected_pixel) begin
            errors=errors+1;
            if(first_errors<8) begin
                $display("PIXEL_MISMATCH frame=%0d x=%0d y=%0d got=%h expected=%h",
                    target_frame,out_x,out_y,vout_data,expected_pixel);
                first_errors=first_errors+1;
            end
        end
        if(out_x==1279) begin out_x=0; out_y=out_y+1; end else out_x=out_x+1;
    end
end
integer fd;
final begin
    $display("FINAL pixels=%0d errors=%0d write_checked=%0d write_errors=%0d acc=%0d reads=%0d writes=%0d rd_count=%0d wr_count=%0d",
        pixels,errors,write_checked,write_errors,acc_done,model.video_reads,model.video_writes,
        dut.video.rd_buf.wr_cnt,dut.video.wr_buf.rd_cnt);
end
initial begin
    if(!$value$plusargs("SCENARIO=%d",scenario)) scenario=0;
    if(!$value$plusargs("FRAMES=%d",frames)) frames=3;
    gapped=scenario==1;
    if(scenario==2) out_half=13.2;
    bank_frame[0]=0; bank_frame[1]=0;
    for(i=0;i<115200;i=i+1) row_epoch[i]=-1;
    for(epoch=0;epoch<(scenario==3 ? 2 : 1);epoch=epoch+1) begin
        rst_n=0; ddr_init_done=0; acc_rst_n=0; monitor=0;
        wr_fsync=0; wr_en=0; rd_fsync=0; rd_en=0;
        checked_frames=0; output_started=0; rd_fsync_last=0; frame_pixels=0;
        cam_pairs=0; write_consumed=0; read_supplied=0; read_consumed=0;
        repeat(20) @(negedge clk);
        if(epoch>0) begin
            if(init_done!==0 || dut.video.rd_buf.wr_frame_cnt!==0 ||
               dut.video.wr_buf.rd_frame_cnt!==0)
                $fatal(1,"Common reset retained video-ready/frame ownership");
            reset_checks=reset_checks+1;
        end
        rst_n=1;
        repeat(20) @(negedge clk);
        ddr_init_done=1; acc_rst_n=1;
        // Permit the real reset synchronizers to settle before the first camera VS.
        repeat(8) @(negedge vin_clk);
        fork
            begin
                for(f=1;f<=frames+1;f=f+1) begin
                    camera_frame=epoch*10+f;
                    bank_frame[f%2]=camera_frame; camera(camera_frame);
                end
            end
            begin
                wait(init_done);
                monitor=1;
                repeat(frames) display_frame;
                repeat(10) @(negedge vout_clk);
            end
            begin
                wait(init_done && rd_en);
                for(integer n=0;n<128;n=n+1) begin
                    transaction(1,n); transaction(0,n);
                    repeat(frames*25000) @(negedge clk);
                end
            end
        join
        if(frame_pixels==921600) checked_frames=checked_frames+1;
        total_frames=total_frames+checked_frames;
    end
    for(i=64;i<128;i=i+1)
        if(model.acc_mem[i]!=={8{32'hc5a53219}}) $fatal(1,"Accelerator guard corrupted");
    fd=$fopen("counts.txt","w");
    $fdisplay(fd,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
        scenario,pixels,errors,write_checked,write_errors,total_frames,acc_done,
        video_max_wait,acc_max_latency,wr_peak,wr_min,rd_peak,rd_min,ui_ticks,
        acc_active_requests,reset_checks);
    $fclose(fd);
    $display("RESULT scenario=%0d pixels=%0d errors=%0d write_pixels=%0d write_errors=%0d frames=%0d acc=%0d",
        scenario,pixels,errors,write_checked,write_errors,total_frames,acc_done);
    if(errors || write_errors) $display("REJECT: video integrity");
    else if(total_frames!=frames*epoch || pixels!=frames*epoch*921600 || acc_done!=256*epoch ||
            acc_active_requests<128*epoch || wr_peak>8192 || wr_min<0 || rd_peak>8192 || rd_min<0 ||
            video_max_wait>4444 || acc_max_latency>4444)
        $fatal(1,"Incomplete coverage");
    else $display("PASS: actual framebuffer integration");
    $finish;
end
endmodule
