`timescale 1ns/1ps
// PGL50H native UI: one 256-bit beat spans eight 32-bit DDR addresses.
// No WVALID, RREADY or B channel. Reset rst_n together with the DDR controller.
module road_ddr_bridge #(
    parameter [31:0] ACC_BASE_WORD = 32'h00200000,
    parameter [31:0] ACC_LIMIT_WORD = 32'h00400000,
    parameter [28:0] VIDEO_LIMIT = 29'h00800000,
    parameter [7:0] VERIFY_RETRIES = 8'd15
) (
    input clk, rst_n, ddr_init_done, acc_rst_n,
    input mem_req_valid, mem_req_write,
    output mem_req_ready,
    input [31:0] mem_req_addr,
    input [127:0] mem_req_data,
    input [15:0] mem_req_strb,
    input [63:0] mem_req_tag,
    output mem_rsp_valid,
    input mem_rsp_ready,
    output reg [127:0] mem_rsp_data,
    output reg [63:0] mem_rsp_tag,
    output reg mem_rsp_error,
    output reg fault,
    output idle,

    input v_awvalid,
    output v_awready,
    input [27:0] v_awaddr,
    input [3:0] v_awid, v_awlen,
    input v_awap,
    input [255:0] v_wdata,
    input [31:0] v_wstrb,
    output v_wready, v_wlast,
    output [3:0] v_wid,
    input v_arvalid,
    output v_arready,
    input [27:0] v_araddr,
    input [3:0] v_arid, v_arlen,
    input v_arap,
    output [255:0] v_rdata,
    output [3:0] v_rid,
    output v_rvalid, v_rlast,

    output axi_awvalid,
    input axi_awready,
    output [27:0] axi_awaddr,
    output [3:0] axi_awuser_id, axi_awlen,
    output axi_awuser_ap,
    output [255:0] axi_wdata,
    output [31:0] axi_wstrb,
    input axi_wready, axi_wusero_last,
    input [3:0] axi_wusero_id,
    output axi_arvalid,
    input axi_arready,
    output [27:0] axi_araddr,
    output [3:0] axi_aruser_id, axi_arlen,
    output axi_aruser_ap,
    input [255:0] axi_rdata,
    input [3:0] axi_rid,
    input axi_rvalid, axi_rlast
);
localparam IDLE=3'd0, WCMD=3'd1, WDATA=3'd2, RCMD=3'd3, RDATA=3'd4;
localparam AWRITE=2'd0, AREAD=2'd1, AVERIFY=2'd2;
reg [2:0] state;
reg [1:0] phase;
reg pending, cancelled, response_valid, initialized;
reg owner_acc, verify_command, last_video_write;
reg [27:0] cmd_addr, acc_addr;
reg [3:0] cmd_id, cmd_len, remaining;
reg cmd_ap, acc_half;
reg [127:0] acc_data;
reg [15:0] acc_keep;
reg [7:0] retries;

wire enabled = rst_n && ddr_init_done && !fault;
wire accept_request = mem_req_valid && mem_req_ready;
wire choose_read = v_arvalid && (!v_awvalid || last_video_write);
assign v_arready = enabled && state==IDLE && choose_read;
assign v_awready = enabled && state==IDLE && v_awvalid && !choose_read;
assign mem_req_ready = enabled && acc_rst_n && !pending;
assign mem_rsp_valid = response_valid && acc_rst_n && rst_n;
assign idle = state==IDLE && !pending && !fault;
assign axi_awvalid = enabled && state==WCMD;
assign axi_arvalid = enabled && state==RCMD;
assign axi_awaddr = cmd_addr;
assign axi_araddr = cmd_addr;
assign axi_awuser_id = cmd_id;
assign axi_aruser_id = cmd_id;
assign axi_awlen = cmd_len;
assign axi_arlen = cmd_len;
assign axi_awuser_ap = cmd_ap;
assign axi_aruser_ap = cmd_ap;
assign axi_wdata = !owner_acc ? v_wdata :
    acc_half ? {acc_data,128'd0} : {128'd0,acc_data};
assign axi_wstrb = !enabled ? 32'd0 : !owner_acc ? v_wstrb :
    acc_half ? {acc_keep,16'd0} : {16'd0,acc_keep};

wire write_active = state==WDATA || (state==WCMD && axi_awready);
wire read_active = state==RDATA || (state==RCMD && axi_arready);
wire write_fire = enabled && write_active && axi_wready;
wire read_fire = enabled && read_active && axi_rvalid;
wire write_bad = write_fire &&
    (axi_wusero_id!=cmd_id || axi_wusero_last!=(remaining==0));
wire read_bad = read_fire && (axi_rid!=cmd_id || axi_rlast!=(remaining==0));
wire unexpected = enabled &&
    ((axi_wready && !write_active) || (axi_rvalid && !read_active));
assign v_wready = write_fire && !owner_acc && !write_bad;
assign v_wlast = v_wready && axi_wusero_last;
assign v_wid = axi_wusero_id;
assign v_rvalid = read_fire && !owner_acc && !read_bad;
assign v_rlast = v_rvalid && axi_rlast;
assign v_rdata = axi_rdata;
assign v_rid = axi_rid;

wire [28:0] video_aw_end = {1'b0,v_awaddr} + (({25'd0,v_awlen}+29'd1)<<3);
wire [28:0] video_ar_end = {1'b0,v_araddr} + (({25'd0,v_arlen}+29'd1)<<3);
wire partition_bad = ACC_BASE_WORD[0] || ACC_LIMIT_WORD[0] ||
    ACC_BASE_WORD>=ACC_LIMIT_WORD || ACC_LIMIT_WORD>32'h04000000 ||
    {ACC_BASE_WORD,2'b00} < {5'd0,VIDEO_LIMIT};
wire request_bad = partition_bad || mem_req_addr<ACC_BASE_WORD ||
    mem_req_addr>=ACC_LIMIT_WORD || |mem_req_addr[31:26];
wire video_aw_bad = |v_awaddr[2:0] || video_aw_end>VIDEO_LIMIT;
wire video_ar_bad = |v_araddr[2:0] || video_ar_end>VIDEO_LIMIT;
wire video_bad = (v_arready && video_ar_bad) || (v_awready && video_aw_bad);
wire [127:0] selected_read = acc_half ? axi_rdata[255:128] : axi_rdata[127:0];
reg verify_match;
integer lane;
always @* begin
    verify_match=1'b1;
    for(lane=0;lane<16;lane=lane+1)
        if(acc_keep[lane] && selected_read[lane*8+:8]!==acc_data[lane*8+:8])
            verify_match=1'b0;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state<=IDLE; phase<=AREAD; pending<=0; cancelled<=0; response_valid<=0;
        initialized<=0; fault<=0; owner_acc<=0; verify_command<=0; last_video_write<=1;
        cmd_addr<=0; cmd_id<=0; cmd_len<=0; remaining<=0; cmd_ap<=0;
        acc_addr<=0; acc_half<=0; acc_data<=0; acc_keep<=0; retries<=0;
        mem_rsp_data<=0; mem_rsp_tag<=0; mem_rsp_error<=0;
    end else begin
        if(ddr_init_done) initialized<=1;
        if(!acc_rst_n) begin
            cancelled<=1;
            response_valid<=0;
        end
        if(mem_rsp_valid && mem_rsp_ready) begin
            response_valid<=0; pending<=0;
        end
        if(accept_request) begin
            pending<=1; cancelled<=0; mem_rsp_tag<=mem_req_tag;
            acc_addr<={mem_req_addr[25:1],3'b000}; acc_half<=mem_req_addr[0];
            acc_data<=mem_req_data; acc_keep<=mem_req_strb; retries<=0;
            mem_rsp_data<=0; mem_rsp_error<=request_bad;
            phase<=mem_req_write ? AWRITE : AREAD;
            if(request_bad || (mem_req_write && mem_req_strb==0)) response_valid<=1;
        end
        if(enabled) begin
            case(state)
            IDLE: begin
                if(pending && (cancelled || !acc_rst_n)) begin
                    pending<=0; response_valid<=0;
                end
                // Video has priority at command boundaries. Alternate competing video channels.
                if(v_arready || v_awready) begin
                    owner_acc<=0;
                    cmd_addr<=v_arready ? v_araddr : v_awaddr;
                    cmd_id<=v_arready ? v_arid : v_awid;
                    cmd_len<=v_arready ? v_arlen : v_awlen;
                    remaining<=v_arready ? v_arlen : v_awlen;
                    cmd_ap<=v_arready ? v_arap : v_awap;
                    last_video_write<=v_awready;
                    if((v_arready && video_ar_bad) || (v_awready && video_aw_bad))
                        fault<=1;
                    else state<=v_arready ? RCMD : WCMD;
                end else if(pending && !response_valid && !cancelled && acc_rst_n) begin
                    owner_acc<=1; cmd_addr<=acc_addr; cmd_id<=4'hf;
                    cmd_len<=0; remaining<=0; cmd_ap<=0;
                    verify_command<=phase==AVERIFY;
                    state<=phase==AWRITE ? WCMD : RCMD;
                end
            end
            WCMD: if(axi_awready) state<=WDATA;
            RCMD: if(axi_arready) state<=RDATA;
            default: begin end
            endcase
            // Includes same-edge command acceptance and first data beat.
            if(write_fire && !write_bad) begin
                remaining<=remaining-1'b1;
                if(remaining==0) begin
                    state<=IDLE;
                    if(owner_acc) begin
                        if(cancelled || !acc_rst_n) pending<=0;
                        else phase<=AVERIFY;
                    end
                end
            end
            if(read_fire && !read_bad) begin
                remaining<=remaining-1'b1;
                if(remaining==0) begin
                    state<=IDLE;
                    if(owner_acc) begin
                        if(cancelled || !acc_rst_n) pending<=0;
                        else if(!verify_command || verify_match) begin
                            mem_rsp_data<=verify_command ? 128'd0 : selected_read;
                            mem_rsp_error<=0; response_valid<=1;
                        end else if(retries==VERIFY_RETRIES) begin
                            mem_rsp_data<=0; mem_rsp_error<=1; response_valid<=1;
                        end else retries<=retries+1'b1;
                    end
                end
            end
        end
        // Lost initialization or malformed native traffic requires common DDR/UI reset.
        if((initialized && !ddr_init_done) || write_bad || read_bad || unexpected || video_bad) begin
            fault<=1;
            if(acc_rst_n && !response_valid && ((pending && !cancelled) || accept_request)) begin
                response_valid<=1; mem_rsp_error<=1; mem_rsp_data<=0;
            end
        end
    end
end
endmodule
