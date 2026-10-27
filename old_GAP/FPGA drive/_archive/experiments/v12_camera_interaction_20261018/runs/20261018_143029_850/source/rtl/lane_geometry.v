`timescale 1ns/1ps
// Experimental image-space lane structure. Not a calibrated vehicle controller.
// Mask, DE and VS must be aligned; four 8-row bands summarize narrow paint runs.
module lane_geometry #(
    parameter H_ACTIVE=1280, V_ACTIVE=720,
    parameter ROI_Y0=V_ACTIVE*9/16,
    parameter BAND0=V_ACTIVE-224, BAND_STEP=64,
    parameter MIN_SUPPORT=32, MIN_SEGMENT=12,
    parameter CENTER_MARGIN=24, MAX_RUN=64
)(
    input clk,rst_n,de,vs,white_mark,yellow_mark,
    input zebra_candidate,zebra_confirmed,
    input [10:0] zebra_y0,zebra_y1,
    output reg result_valid,
    output reg [15:0] frame_id,
    output reg [7:0] flags,
    output reg [1:0] left_kind,right_kind,departure,
    output reg signed [11:0] offset_px,
    output reg [10:0] lane_width,
    output reg [10:0] left_x0,left_y0,left_x1,left_y1,
    output reg [10:0] right_x0,right_y0,right_x1,right_y1,
    output reg [10:0] left_support,right_support,
    output [255:0] snapshot
);
    reg vs_d,de_d,active_frame,bad_frame;
    reg [10:0] x,y;
    wire frame_start=vs && !vs_d;
    wire row_end=de_d && !de;
    wire in_roi=y>=ROI_Y0 && y<V_ACTIVE-8 && x>=H_ACTIVE/10 && x<H_ACTIVE*9/10;
    wire mark=in_roi && (white_mark || yellow_mark);
    reg running;
    reg [10:0] run_start,run_last;
    reg [2:0] hole;
    wire finish_run=running && !mark && hole==4;
    wire [10:0] run_width=run_last-run_start+1'b1;
    wire [11:0] run_sum={1'b0,run_start}+{1'b0,run_last};
    wire [10:0] run_mid=run_sum[11:1];
    reg [4:0] row_runs;
    reg [1:0] row_found;
    reg [10:0] row_x[0:1];
    reg [10:0] totals[0:1],streak[0:1],gap[0:1],max_gap[0:1];
    reg [4:0] segments[0:1];
    reg [1:0] previous_good;
    reg [10:0] previous_x[0:1];
    reg [3:0] band_count[0:7];
    reg [10:0] band_min[0:7],band_max[0:7];
    reg [1:0] good;
    integer k,j;
    always @* begin
        good=0;
        for(k=0;k<2;k=k+1) begin
            good[k]=row_found[k] && row_runs<=6 && x==H_ACTIVE
                    && (!previous_good[k]
                        || ((row_x[k]>previous_x[k] ? row_x[k]-previous_x[k] : previous_x[k]-row_x[k])<=12));
        end
    end

    reg [1:0] side_valid;
    reg [1:0] kinds[0:1];
    reg [10:0] sx0[0:1],sy0[0:1],sx1[0:1],sy1[0:1],near_x[0:1];
    reg [1:0] near_valid;
    reg [3:0] band_ok[0:1];
    reg [11:0] center_sum;
    reg [10:0] width_now;
    reg signed [11:0] offset_now;
    reg pair_valid;
    reg [1:0] direction_now;
    reg [11:0] abs_offset;
    reg [14:0] departure_measure;
    integer s,b,n,index;
    reg [11:0] midpoint_sum;
    always @* begin
        side_valid=0; near_valid=0;
        midpoint_sum=0;
        for(s=0;s<2;s=s+1) begin
            sx0[s]=0; sy0[s]=0; sx1[s]=0; sy1[s]=0; near_x[s]=0;
            kinds[s]=0; band_ok[s]=0; n=0;
            for(b=0;b<4;b=b+1) begin
                index=s*4+b;
                band_ok[s][b]=band_count[index]>=6 && band_max[index]-band_min[index]<=64
                               && !(zebra_candidate && BAND0+b*BAND_STEP+3>=zebra_y0
                                    && BAND0+b*BAND_STEP-4<=zebra_y1);
                if(band_ok[s][b]) begin
                    midpoint_sum={1'b0,band_min[index]}+{1'b0,band_max[index]};
                    if(n==0) begin sx0[s]=midpoint_sum[11:1]; sy0[s]=BAND0+b*BAND_STEP; end
                    sx1[s]=midpoint_sum[11:1]; sy1[s]=BAND0+b*BAND_STEP;
                    n=n+1;
                    if(b==3) begin near_valid[s]=1; near_x[s]=midpoint_sum[11:1]; end
                end
            end
            side_valid[s]=n>=2 && sy1[s]>=BAND0+2*BAND_STEP && totals[s]>=MIN_SUPPORT;
            if(side_valid[s] && !zebra_candidate) begin
                if(totals[s]*4 >= (V_ACTIVE-8-ROI_Y0)*3 && max_gap[s]<=8) kinds[s]=1;
                else if(segments[s]>=2 && max_gap[s]>=12) kinds[s]=2;
            end
        end
        width_now=near_x[1]-near_x[0];
        pair_valid=(&side_valid) && (&near_valid) && near_x[1]>near_x[0]
                   && width_now>=H_ACTIVE/5 && width_now<=H_ACTIVE*4/5;
        center_sum={1'b0,near_x[0]}+{1'b0,near_x[1]};
        offset_now=$signed(H_ACTIVE/2)-$signed({1'b0,center_sum[11:1]});
        abs_offset=offset_now[11] ? -offset_now : offset_now;
        departure_measure=abs_offset*6;
        direction_now=0;
        if(pair_valid && departure_measure>=width_now)
            direction_now=offset_now[11] ? 2'd1 : 2'd2;
    end
    reg [1:0] previous_direction,warning_count;
    reg [10:0] saved_zebra_y0,saved_zebra_y1;
    wire frame_good=!bad_frame && x==H_ACTIVE;
    // Byte 0 is flags, all multibyte values are little-endian on the byte stream.
    assign snapshot={5'd0,saved_zebra_y1,5'd0,saved_zebra_y0,
                     5'd0,right_support,5'd0,left_support,
                     5'd0,right_y1,5'd0,right_x1,5'd0,right_y0,5'd0,right_x0,
                     5'd0,left_y1,5'd0,left_x1,5'd0,left_y0,5'd0,left_x0,
                     5'd0,lane_width,{{4{offset_px[11]}},offset_px},frame_id,
                     2'b00,departure,right_kind,left_kind,flags};
    integer i,t;
    always @(posedge clk) begin
        if(!rst_n) begin
            vs_d<=0; de_d<=0; active_frame<=0; bad_frame<=0; x<=0; y<=0;
            running<=0; run_start<=0; run_last<=0; hole<=0; row_runs<=0; row_found<=0;
            previous_good<=0;
            for(i=0;i<2;i=i+1) begin
                row_x[i]<=0; totals[i]<=0; streak[i]<=0; gap[i]<=0;
                max_gap[i]<=0; segments[i]<=0; previous_x[i]<=0;
            end
            for(i=0;i<8;i=i+1) begin band_count[i]<=0; band_min[i]<=2047; band_max[i]<=0; end
            result_valid<=0; frame_id<=0; flags<=8'h40;
            left_kind<=0; right_kind<=0; departure<=0; offset_px<=0; lane_width<=0;
            left_x0<=0; left_y0<=0; left_x1<=0; left_y1<=0;
            right_x0<=0; right_y0<=0; right_x1<=0; right_y1<=0;
            left_support<=0; right_support<=0;
            previous_direction<=0; warning_count<=0;
            saved_zebra_y0<=0; saved_zebra_y1<=0;
        end else begin
            vs_d<=vs; de_d<=de && !vs; result_valid<=0;
            if(frame_start) begin
                if(active_frame) begin
                    result_valid<=1; frame_id<=frame_id+1'b1; flags<=8'h60;
                    left_kind<=0; right_kind<=0; departure<=0; offset_px<=0; lane_width<=0;
                    left_x0<=0; left_y0<=0; left_x1<=0; left_y1<=0;
                    right_x0<=0; right_y0<=0; right_x1<=0; right_y1<=0;
                    left_support<=0; right_support<=0; saved_zebra_y0<=0; saved_zebra_y1<=0;
                    warning_count<=0; previous_direction<=0;
                end
                active_frame<=1; bad_frame<=de; x<=0; y<=0;
                running<=0; hole<=0; row_runs<=0; row_found<=0; previous_good<=0;
                for(i=0;i<2;i=i+1) begin totals[i]<=0; streak[i]<=0; gap[i]<=0; max_gap[i]<=0; segments[i]<=0; end
                for(i=0;i<8;i=i+1) begin band_count[i]<=0; band_min[i]<=2047; band_max[i]<=0; end
            end else if(active_frame && !vs) begin
                if(de) begin
                    if(x!=2047) x<=x+1'b1;
                    if(x>=H_ACTIVE) bad_frame<=1;
                    if(mark) begin
                        if(!running) run_start<=x;
                        run_last<=x; running<=1; hole<=0;
                    end else if(running) begin
                        if(hole<4) hole<=hole+1'b1;
                        else begin
                            running<=0;
                            if(run_width>=2 && run_width<=MAX_RUN) begin
                                if(row_runs!=31) row_runs<=row_runs+1'b1;
                                if(run_mid<H_ACTIVE/2-CENTER_MARGIN && (!row_found[0] || run_mid>row_x[0])) begin
                                    row_found[0]<=1; row_x[0]<=run_mid;
                                end
                                if(run_mid>H_ACTIVE/2+CENTER_MARGIN && (!row_found[1] || run_mid<row_x[1])) begin
                                    row_found[1]<=1; row_x[1]<=run_mid;
                                end
                            end
                        end
                    end
                end
                if(row_end) begin
                    x<=0; y<=y+1'b1; running<=0; hole<=0; row_runs<=0; row_found<=0;
                    if(x!=H_ACTIVE) bad_frame<=1;
                    if(y>=ROI_Y0 && y<V_ACTIVE-8) begin
                        previous_good<=good;
                        for(i=0;i<2;i=i+1) begin
                            if(good[i]) begin
                                previous_x[i]<=row_x[i]; totals[i]<=totals[i]+1'b1;
                                streak[i]<=streak[i]+1'b1; gap[i]<=0;
                                if(streak[i]==MIN_SEGMENT-1 && segments[i]!=31) segments[i]<=segments[i]+1'b1;
                                if(gap[i]>max_gap[i]) max_gap[i]<=gap[i];
                                for(t=0;t<4;t=t+1) begin
                                    if(y>=BAND0+t*BAND_STEP-4 && y<=BAND0+t*BAND_STEP+3) begin
                                        band_count[i*4+t]<=band_count[i*4+t]+1'b1;
                                        if(row_x[i]<band_min[i*4+t]) band_min[i*4+t]<=row_x[i];
                                        if(row_x[i]>band_max[i*4+t]) band_max[i*4+t]<=row_x[i];
                                    end
                                end
                            end else begin
                                streak[i]<=0;
                                if(totals[i]!=0 && gap[i]!=2047) gap[i]<=gap[i]+1'b1;
                            end
                        end
                    end
                    if(y==V_ACTIVE-1) begin
                        active_frame<=0; result_valid<=1; frame_id<=frame_id+1'b1;
                        flags<={1'b0,1'b1,!frame_good,zebra_confirmed && frame_good,
                                zebra_candidate && frame_good,pair_valid && frame_good,
                                side_valid[1] && frame_good,side_valid[0] && frame_good};
                        left_kind<=frame_good ? kinds[0] : 2'd0;
                        right_kind<=frame_good ? kinds[1] : 2'd0;
                        offset_px<=frame_good && pair_valid ? offset_now : 12'sd0;
                        lane_width<=frame_good && pair_valid ? width_now : 11'd0;
                        left_x0<=frame_good && side_valid[0] ? sx0[0] : 11'd0;
                        left_y0<=frame_good && side_valid[0] ? sy0[0] : 11'd0;
                        left_x1<=frame_good && side_valid[0] ? sx1[0] : 11'd0;
                        left_y1<=frame_good && side_valid[0] ? sy1[0] : 11'd0;
                        right_x0<=frame_good && side_valid[1] ? sx0[1] : 11'd0;
                        right_y0<=frame_good && side_valid[1] ? sy0[1] : 11'd0;
                        right_x1<=frame_good && side_valid[1] ? sx1[1] : 11'd0;
                        right_y1<=frame_good && side_valid[1] ? sy1[1] : 11'd0;
                        left_support<=frame_good ? totals[0] : 11'd0;
                        right_support<=frame_good ? totals[1] : 11'd0;
                        saved_zebra_y0<=frame_good && zebra_candidate ? zebra_y0 : 11'd0;
                        saved_zebra_y1<=frame_good && zebra_candidate ? zebra_y1 : 11'd0;
                        departure<=0;
                        if(!frame_good || direction_now==0) begin warning_count<=0; previous_direction<=0; end
                        else begin
                            previous_direction<=direction_now;
                            if(direction_now!=previous_direction) warning_count<=1;
                            else begin
                                if(warning_count!=3) warning_count<=warning_count+1'b1;
                                if(warning_count>=2) departure<=direction_now;
                            end
                        end
                    end
                end
            end
        end
    end
endmodule
