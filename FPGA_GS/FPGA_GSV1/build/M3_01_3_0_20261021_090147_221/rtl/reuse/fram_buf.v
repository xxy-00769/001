`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Meyesemi
// Engineer: Nill
// 
// Create Date: 15/03/23 14:17:29
// Design Name: 
// Module Name: fram_buf
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`define UD #1
module fram_buf #(
    parameter M2_READER = 0,
    parameter M3_FRONT = 0,
    parameter SOURCE_ID = 0, // 0 FRONT, 1 REAR, 2 LEFT, 3 RIGHT
    parameter DISPLAY_HALF = 0, // display-only 2x nearest-neighbour reduction
    parameter                     MEM_ROW_WIDTH        = 15    ,
    parameter                     MEM_COLUMN_WIDTH     = 10    ,
    parameter                     MEM_BANK_WIDTH       = 3     ,
    parameter                     CTRL_ADDR_WIDTH = MEM_ROW_WIDTH + MEM_BANK_WIDTH + MEM_COLUMN_WIDTH,
    parameter                     MEM_DQ_WIDTH         = 32    ,
    parameter                     H_NUM                = 12'd1280,//12'd1920,
    parameter                     V_NUM                = 12'd720,//12'd1080,//12'd106,//
    parameter                     PIX_WIDTH            = 16//24 
)(
    input net_acquire,net_release,output net_grant,net_held,
    output [1:0] net_bank,output [31:0] net_id,net_time,latest_frame_id,
    input                         vin_clk,
    input                         wr_fsync,
    input                         wr_en,
    input  [PIX_WIDTH- 1'b1 : 0]  wr_data,
    input                         pipeline_running,
    input [31:0]                  wr_frame_id, wr_frame_time,
    input                         source_result_valid,
    input [31:0]                  source_result_id,
    input [7:0]                   source_result_errors,
    output reg                    init_done=0,
    
    input                         ddr_clk,
    input                         ddr_rstn,
    
    input                         vout_clk,
    input                         rd_fsync,
    input                         display_selected,
    input                         display_quarter,
    input                         rd_en,
    output                        vout_de,
    output [PIX_WIDTH- 1'b1 : 0]  vout_data,
    
    output [CTRL_ADDR_WIDTH-1:0]  axi_awaddr     ,
    output [3:0]                  axi_awid       ,
    output [3:0]                  axi_awlen      ,
    output [2:0]                  axi_awsize     ,
    output [1:0]                  axi_awburst    ,
    input                         axi_awready    ,
    output                        axi_awvalid    ,
                                                  
    output [MEM_DQ_WIDTH*8-1:0]   axi_wdata      ,
    output [MEM_DQ_WIDTH -1 :0]   axi_wstrb      ,
    input                         axi_wlast      ,
    output                        axi_wvalid     ,
    input                         axi_wready     ,
    input  [3 : 0]                axi_bid        ,                                      
                                                  
    output [CTRL_ADDR_WIDTH-1:0]  axi_araddr     ,
    output [3:0]                  axi_arid       ,
    output [3:0]                  axi_arlen      ,
    output [2:0]                  axi_arsize     ,
    output [1:0]                  axi_arburst    ,
    output                        axi_arvalid    ,
    input                         axi_arready    ,
                                                  
    output                        axi_rready     ,
    input  [MEM_DQ_WIDTH*8-1:0]   axi_rdata      ,
    input                         axi_rvalid     ,
    input                         axi_rlast      ,
    input  [3:0]                  axi_rid            
);
    parameter LEN_WIDTH       = 32;
    parameter LINE_ADDR_WIDTH = 22;//19;//1440 * 1080 = 1 555 200 = 21'h17BB00
    parameter FRAME_CNT_WIDTH = CTRL_ADDR_WIDTH - LINE_ADDR_WIDTH;
    
    wire                        ddr_wreq;     
    wire [CTRL_ADDR_WIDTH- 1'b1 : 0] ddr_waddr;    
    wire [LEN_WIDTH- 1'b1 : 0]  ddr_wr_len;   
    wire                        ddr_wrdy;     
    wire                        ddr_wdone;    
    wire [8*MEM_DQ_WIDTH-1 : 0] ddr_wdata;    
    wire                        ddr_wdata_req;
    
    wire                        rd_cmd_en   ;
    wire [CTRL_ADDR_WIDTH-1:0]  rd_cmd_addr ;
    wire [LEN_WIDTH- 1'b1: 0]   rd_cmd_len  ;
    wire                        rd_cmd_ready;
    wire                        rd_cmd_done;
                                
    wire                        read_ready  = 1'b1;
    wire [MEM_DQ_WIDTH*8-1:0]   read_rdata  ;
    wire                        read_en     ;
    wire                        ddr_wr_bac;
    wire writer_rst_n, writer_vs, writer_de, line_event, output_sof;
    wire write_issue, read_issue, read_enabled, has_frame;
    wire [(M3_FRONT ? 2:1)-1:0] write_bank,read_bank;
    wire [11:0] read_completed_gray;
    wire [PIX_WIDTH-1:0] raw_vout_data;
    wire [CTRL_ADDR_WIDTH-1:0] owned_waddr = M3_FRONT && write_bank==2 ?
        28'h2000000 | ddr_waddr[21:0] :
        {{(CTRL_ADDR_WIDTH-LINE_ADDR_WIDTH-3){1'b0}}, SOURCE_ID[1:0], write_bank[0],
        ddr_waddr[LINE_ADDR_WIDTH-1:0]};
    wire [CTRL_ADDR_WIDTH-1:0] owned_raddr = M3_FRONT && read_bank==2 ?
        28'h2000000 | rd_cmd_addr[21:0] :
        {{(CTRL_ADDR_WIDTH-LINE_ADDR_WIDTH-3){1'b0}}, SOURCE_ID[1:0], read_bank[0],
        rd_cmd_addr[LINE_ADDR_WIDTH-1:0]};
    wire [31:0] published_count /* synthesis syn_keep = 1 */;
    wire [31:0] rejected_count /* synthesis syn_keep = 1 */;
    wire [31:0] read_fault_count /* synthesis syn_keep = 1 */;
    wire [31:0] display_id /* synthesis syn_keep = 1 */;
    wire [31:0] display_time /* synthesis syn_keep = 1 */;
    reg [1:0] selected_d;
    always @(posedge ddr_clk or negedge ddr_rstn)
        if(!ddr_rstn) selected_d <= 0;
        else selected_d <= {selected_d[0],display_selected};
    generate if(M3_FRONT) begin: front_three_slots
    m3_front_owner #(.H_NUM(H_NUM), .V_NUM(V_NUM)) owner (
        .clk(ddr_clk), .rst_n(ddr_rstn), .video_clk(vin_clk),
        .pipeline_running(pipeline_running), .video_vs(wr_fsync), .video_de(wr_en),
        .video_id(wr_frame_id), .video_time(wr_frame_time),
        .result_valid(source_result_valid), .result_id(source_result_id),
        .result_errors(source_result_errors),
        .writer_rst_n(writer_rst_n), .writer_vs(writer_vs), .writer_de(writer_de),
        .line_event(line_event), .write_request(ddr_wreq),
        .write_ready(ddr_wrdy), .write_done(ddr_wdone),
        .write_issue(write_issue), .write_bank(write_bank),
        .output_sof(output_sof), .display_selected(selected_d[1]), .read_request(rd_cmd_en),
        .read_ready(rd_cmd_ready), .read_done(rd_cmd_done),
        .read_issue(read_issue), .read_bank(read_bank), .read_enabled(read_enabled),
        .has_frame(has_frame), .read_completed_gray(read_completed_gray),
        .published_count(published_count), .rejected_count(rejected_count),
        .read_fault_count(read_fault_count), .display_id(display_id), .display_time(display_time)
        ,.net_acquire(net_acquire),.net_release(net_release),.net_grant(net_grant),.net_held(net_held),
        .net_bank(net_bank),.net_id(net_id),.net_time(net_time),.latest_id(latest_frame_id)
    );
    end else begin: two_slots
    frame_buffer_owner #(.H_NUM(H_NUM), .V_NUM(V_NUM)) owner (
        .clk(ddr_clk), .rst_n(ddr_rstn), .video_clk(vin_clk),
        .pipeline_running(pipeline_running), .video_vs(wr_fsync), .video_de(wr_en),
        .video_id(wr_frame_id), .video_time(wr_frame_time),
        .result_valid(source_result_valid), .result_id(source_result_id),
        .result_errors(source_result_errors),
        .writer_rst_n(writer_rst_n), .writer_vs(writer_vs), .writer_de(writer_de),
        .line_event(line_event), .write_request(ddr_wreq),
        .write_ready(ddr_wrdy), .write_done(ddr_wdone),
        .write_issue(write_issue), .write_bank(write_bank),
        .output_sof(output_sof), .display_selected(selected_d[1]), .read_request(rd_cmd_en),
        .read_ready(rd_cmd_ready), .read_done(rd_cmd_done),
        .read_issue(read_issue), .read_bank(read_bank), .read_enabled(read_enabled),
        .has_frame(has_frame), .read_completed_gray(read_completed_gray),
        .published_count(published_count), .rejected_count(rejected_count),
        .read_fault_count(read_fault_count), .display_id(display_id), .display_time(display_time)
    );
    assign latest_frame_id=display_id;assign net_grant=0;assign net_held=0;assign net_bank=0;assign net_id=0;assign net_time=0;
    end endgenerate

    wr_buf #(
        .ADDR_WIDTH       (  CTRL_ADDR_WIDTH  ),//parameter                     ADDR_WIDTH      = 6'd27,
        .ADDR_OFFSET      (  32'd0            ),//parameter                     ADDR_OFFSET     = 32'h0000_0000,
        .H_NUM            (  H_NUM            ),//parameter                     H_NUM           = 12'd1920,
        .V_NUM            (  V_NUM            ),//parameter                     V_NUM           = 12'd1080,
        .DQ_WIDTH         (  MEM_DQ_WIDTH     ),//parameter                     DQ_WIDTH        = 7'd32,
        .LEN_WIDTH        (  LEN_WIDTH        ),//parameter                     LEN_WIDTH       = 6'd16,
        .PIX_WIDTH        (  PIX_WIDTH        ),//parameter                     PIX_WIDTH       = 6'd24,
        .LINE_ADDR_WIDTH  (  LINE_ADDR_WIDTH  ),//parameter                     LINE_ADDR_WIDTH = 4'd19,
        .FRAME_CNT_WIDTH  (  FRAME_CNT_WIDTH  ) //parameter                     FRAME_CNT_WIDTH = 4'd8
    ) wr_buf (                                       
        .ddr_clk          (  ddr_clk          ),//input                         ddr_clk,
        .ddr_rstn         (  writer_rst_n     ),
                                              
        .wr_clk           (  vin_clk          ),//input                         wr_clk,
        .wr_fsync         (  writer_vs        ),
        .wr_en            (  writer_de        ),
        .wr_data          (  wr_data          ),//input  [PIX_WIDTH- 1'b1 : 0]  wr_data,
        
        .rd_bac           (  ddr_wr_bac       ),//input                         rd_bac,                                      
        .ddr_wreq         (  ddr_wreq         ),//output                        ddr_wreq,
        .ddr_waddr        (  ddr_waddr        ),//output [ADDR_WIDTH- 1'b1 : 0] ddr_waddr,
        .ddr_wr_len       (  ddr_wr_len       ),//output [LEN_WIDTH- 1'b1 : 0]  ddr_wr_len,
        .ddr_wrdy         (  ddr_wrdy         ),//input                         ddr_wrdy,
        .ddr_wdone        (  ddr_wdone        ),//input                         ddr_wdone,
        .ddr_wdata        (  ddr_wdata        ),//output [8*DQ_WIDTH- 1'b1 : 0] ddr_wdata,
        .ddr_wdata_req    (  ddr_wdata_req    ),//input                         ddr_wdata_req,
                                              
        .frame_wcnt       (                   ),//output [FRAME_CNT_WIDTH-1 :0] frame_wcnt,
        .frame_wirq       (                   ),
        .line_request_event ( line_event     )
    );
    
    reg frame_ready_v;
    always @(posedge vout_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin frame_ready_v <= 0; init_done <= 0; end
        else begin frame_ready_v <= has_frame; init_done <= frame_ready_v; end
    end

    reg [1:0] enabled_v;
    reg [11:0] lines_v1, lines_v2, output_rows;
    reg output_de_d, output_bad;
    reg [31:0] output_underflow_count /* synthesis syn_keep=1 */;
    wire [11:0] available_rows;
    genvar bit_index;
    generate for (bit_index=0; bit_index<12; bit_index=bit_index+1) begin : gray_decode
        assign available_rows[bit_index] = ^(lines_v2 >> bit_index);
    end endgenerate
    always @(posedge vout_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin
            enabled_v <= 0; lines_v1 <= 0; lines_v2 <= 0;
            output_rows <= 0; output_de_d <= 0; output_bad <= 1; output_underflow_count <= 0;
        end else begin
            enabled_v <= {enabled_v[0], read_enabled};
            lines_v1 <= read_completed_gray; lines_v2 <= lines_v1;
            output_de_d <= rd_en;
            if (rd_fsync) begin output_rows <= 0; output_bad <= 0; end
            else if (rd_en && !output_de_d) begin
                output_rows <= output_rows + 1'b1;
                if (!enabled_v[1] || available_rows <= output_rows) begin
                    output_bad <= 1;
                    if(!output_bad) output_underflow_count <= output_underflow_count + 1'b1;
                end
            end
        end
    end
    assign vout_data = enabled_v[1] && !output_bad ? raw_vout_data : {PIX_WIDTH{1'b0}};
    
    generate if(M2_READER) begin: m2_reader
        m2_rd_buf #(.H_NUM(H_NUM),.V_NUM(V_NUM),.ADDR_WIDTH(CTRL_ADDR_WIDTH)) reader(
            .ddr_clk(ddr_clk),.ddr_rstn(ddr_rstn),.vout_clk(vout_clk),
            .rd_fsync(rd_fsync),.rd_en(rd_en),.quarter(display_quarter),
            .selected(selected_d[1]),.enabled(read_enabled),
            .vout_de(vout_de),.vout_data(raw_vout_data),
            .ddr_rreq(rd_cmd_en),.ddr_raddr(rd_cmd_addr),.ddr_rd_len(rd_cmd_len),
            .ddr_rrdy(rd_cmd_ready),.ddr_rdone(rd_cmd_done),
            .ddr_rdata(read_rdata),.ddr_rdata_en(read_en),.frame_start_event(output_sof));
    end else begin: legacy_reader
    rd_buf #(
        .DISPLAY_HALF     ( DISPLAY_HALF ),
        .ADDR_WIDTH       (  CTRL_ADDR_WIDTH  ),//parameter                     ADDR_WIDTH      = 6'd27,
        .ADDR_OFFSET      (  32'h0000_0000    ),//parameter                     ADDR_OFFSET     = 32'h0000_0000,
        .H_NUM            (  H_NUM            ),//parameter                     H_NUM           = 12'd1920,
        .V_NUM            ( DISPLAY_HALF ? V_NUM/2 : V_NUM ),//parameter                     V_NUM           = 12'd1080,
        .DQ_WIDTH         (  MEM_DQ_WIDTH     ),//parameter                     DQ_WIDTH        = 7'd32,
        .LEN_WIDTH        (  LEN_WIDTH        ),//parameter                     LEN_WIDTH       = 6'd16,
        .PIX_WIDTH        (  PIX_WIDTH        ),//parameter                     PIX_WIDTH       = 6'd24,
        .LINE_ADDR_WIDTH  (  LINE_ADDR_WIDTH  ),//parameter                     LINE_ADDR_WIDTH = 4'd19,
        .FRAME_CNT_WIDTH  (  FRAME_CNT_WIDTH  ) //parameter                     FRAME_CNT_WIDTH = 4'd8
    ) rd_buf (
        .ddr_clk         (  ddr_clk           ),//input                         ddr_clk,
        .ddr_rstn        (  ddr_rstn          ),//input                         ddr_rstn,

        .vout_clk        (  vout_clk          ),//input                         vout_clk,
        .rd_fsync        (  rd_fsync          ),//input                         rd_fsync,
        .rd_en           (  rd_en             ),//input                         rd_en,
        .vout_de         (  vout_de           ),//output                        vout_de,
        .vout_data       (  raw_vout_data     ),
        .frame_start_event ( output_sof      ),
        
        .init_done       (  init_done         ),//input                         init_done,
      
        .ddr_rreq        (  rd_cmd_en         ),//output                        ddr_rreq,
        .ddr_raddr       (  rd_cmd_addr       ),//output [ADDR_WIDTH- 1'b1 : 0] ddr_raddr,
        .ddr_rd_len      (  rd_cmd_len        ),//output [LEN_WIDTH- 1'b1 : 0]  ddr_rd_len,
        .ddr_rrdy        (  rd_cmd_ready      ),//input                         ddr_rrdy,
        .ddr_rdone       (  rd_cmd_done       ),//input                         ddr_rdone,
                                              
        .ddr_rdata       (  read_rdata        ),//input [8*DQ_WIDTH- 1'b1 : 0]  ddr_rdata,
        .ddr_rdata_en    (  read_en           ) //input                         ddr_rdata_en,
    );
    
    end endgenerate

    wr_rd_ctrl_top#(
        .CTRL_ADDR_WIDTH  (  CTRL_ADDR_WIDTH  ),//parameter                    CTRL_ADDR_WIDTH      = 28,
        .MEM_DQ_WIDTH     (  MEM_DQ_WIDTH     ) //parameter                    MEM_DQ_WIDTH         = 16
    )wr_rd_ctrl_top (                         
        .clk              (  ddr_clk          ),//input                        clk            ,            
        .rstn             (  ddr_rstn         ),//input                        rstn           ,            
                                              
        .wr_cmd_en        (  write_issue      ),
        .wr_cmd_addr      (  owned_waddr      ),
        .wr_cmd_len       (  ddr_wr_len       ),//input  [31:0]               wr_cmd_len  ,
        .wr_cmd_ready     (  ddr_wrdy         ),//output                       wr_cmd_ready,
        .wr_cmd_done      (  ddr_wdone        ),//output                       wr_cmd_done,
        .wr_bac           (  ddr_wr_bac       ),//output                       wr_bac,                                     
        .wr_ctrl_data     (  ddr_wdata        ),//input  [MEM_DQ_WIDTH*8-1:0]  wr_ctrl_data,
        .wr_data_re       (  ddr_wdata_req    ),//output                       wr_data_re  ,
                                              
        .rd_cmd_en        (  read_issue       ),
        .rd_cmd_addr      (  owned_raddr      ),
        .rd_cmd_len       (  rd_cmd_len       ),//input  [31:0]               rd_cmd_len  ,
        .rd_cmd_ready     (  rd_cmd_ready     ),//output                       rd_cmd_ready, 
        .rd_cmd_done      (  rd_cmd_done      ),//output                       rd_cmd_done,
                                              
        .read_ready       (  read_ready       ),//input                        read_ready  ,    
        .read_rdata       (  read_rdata       ),//output [MEM_DQ_WIDTH*8-1:0]  read_rdata  ,    
        .read_en          (  read_en          ),//output                       read_en     ,                                          
        // write channel                        
        .axi_awaddr       (  axi_awaddr       ),//output [CTRL_ADDR_WIDTH-1:0] axi_awaddr     ,  
        .axi_awid         (  axi_awid         ),//output [3:0]                 axi_awid       ,
        .axi_awlen        (  axi_awlen        ),//output [3:0]                 axi_awlen      ,
        .axi_awsize       (  axi_awsize       ),//output [2:0]                 axi_awsize     ,
        .axi_awburst      (  axi_awburst      ),//output [1:0]                 axi_awburst    , //only support 2'b01: INCR
        .axi_awready      (  axi_awready      ),//input                        axi_awready    ,
        .axi_awvalid      (  axi_awvalid      ),//output                       axi_awvalid    ,
                                              
        .axi_wdata        (  axi_wdata        ),//output [MEM_DQ_WIDTH*8-1:0]  axi_wdata      ,
        .axi_wstrb        (  axi_wstrb        ),//output [MEM_DQ_WIDTH -1 :0]  axi_wstrb      ,
        .axi_wlast        (  axi_wlast        ),//output                       axi_wlast      ,
        .axi_wvalid       (  axi_wvalid       ),//output                       axi_wvalid     ,
        .axi_wready       (  axi_wready       ),//input                        axi_wready     ,
        .axi_bid          (  4'd0             ),//input  [3 : 0]               axi_bid        , // Master Interface Write Response.
        .axi_bresp        (  2'd0             ),//input  [1 : 0]               axi_bresp      , // Write response. This signal indicates the status of the write transaction.
        .axi_bvalid       (  1'b0             ),//input                        axi_bvalid     , // Write response valid. This signal indicates that the channel is signaling a valid write response.
        .axi_bready       (                   ),//output                       axi_bready     ,
                                              
        // read channel                          
        .axi_araddr       (  axi_araddr       ),//output [CTRL_ADDR_WIDTH-1:0] axi_araddr     ,    
        .axi_arid         (  axi_arid         ),//output [3:0]                 axi_arid       ,
        .axi_arlen        (  axi_arlen        ),//output [3:0]                 axi_arlen      ,
        .axi_arsize       (  axi_arsize       ),//output [2:0]                 axi_arsize     ,
        .axi_arburst      (  axi_arburst      ),//output [1:0]                 axi_arburst    ,
        .axi_arvalid      (  axi_arvalid      ),//output                       axi_arvalid    , 
        .axi_arready      (  axi_arready      ),//input                        axi_arready    , //only support 2'b01: INCR
                                              
        .axi_rready       (  axi_rready       ),//output                       axi_rready     ,
        .axi_rdata        (  axi_rdata        ),//input  [MEM_DQ_WIDTH*8-1:0]  axi_rdata      ,
        .axi_rvalid       (  axi_rvalid       ),//input                        axi_rvalid     ,
        .axi_rlast        (  axi_rlast        ),//input                        axi_rlast      ,
        .axi_rid          (  axi_rid          ),//input  [3:0]                 axi_rid        ,
        .axi_rresp        (  2'd0             ) //input  [1:0]                 axi_rresp      
    );


endmodule
