`timescale 1ns/1ps
// HMIC_S native port: WREADY requests data, WLAST comes FROM the controller.
// One outstanding burst in each direction; round robin between source ports.
// A grant is registered BEFORE exposing valid and held through the last beat.
module dual_ddr_arbiter(input clk, rst_n,
    input [55:0] s_awaddr, input [7:0] s_awlen, input [1:0] s_awvalid,
    output [1:0] s_awready, input [511:0] s_wdata, input [63:0] s_wstrb,
    output [1:0] s_wready, s_wlast,
    input [55:0] s_araddr, input [7:0] s_arlen, input [1:0] s_arvalid,
    output [1:0] s_arready, output [1:0] s_rvalid, s_rlast,
    output [27:0] awaddr, output [3:0] awlen, output awvalid,
    input awready, output [255:0] wdata, output [31:0] wstrb,
    input wready, wlast,
    output [27:0] araddr, output [3:0] arlen, output arvalid,
    input arready, rvalid, rlast);
    reg wgrant, rgrant, wnext, rnext;
    reg [1:0] ws, rs;
    localparam IDLE=0, ADDRESS=1, DATA=2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin ws<=IDLE; rs<=IDLE; wgrant<=0; rgrant<=0; wnext<=0; rnext<=0; end
        else begin
            case(ws)
                IDLE: if(|s_awvalid) begin
                    wgrant<=s_awvalid[wnext] ? wnext : ~wnext; ws<=ADDRESS;
                end
                ADDRESS: if(awvalid && awready) begin
                    if(wready && wlast) begin ws<=IDLE; wnext<=~wgrant; end
                    else ws<=DATA;
                end
                DATA: if(wlast && wready) begin ws<=IDLE; wnext<=~wgrant; end
            endcase
            case(rs)
                IDLE: if(|s_arvalid) begin
                    rgrant<=s_arvalid[rnext] ? rnext : ~rnext; rs<=ADDRESS;
                end
                ADDRESS: if(arvalid && arready) begin
                    if(rvalid && rlast) begin rs<=IDLE; rnext<=~rgrant; end
                    else rs<=DATA;
                end
                DATA: if(rvalid && rlast) begin rs<=IDLE; rnext<=~rgrant; end
            endcase
        end
    end
    assign awaddr=wgrant ? s_awaddr[55:28] : s_awaddr[27:0];
    assign awlen=wgrant ? s_awlen[7:4] : s_awlen[3:0];
    assign awvalid=ws==ADDRESS && s_awvalid[wgrant];
    assign wdata=wgrant ? s_wdata[511:256] : s_wdata[255:0];
    assign wstrb=wgrant ? s_wstrb[63:32] : s_wstrb[31:0];
    assign araddr=rgrant ? s_araddr[55:28] : s_araddr[27:0];
    assign arlen=rgrant ? s_arlen[7:4] : s_arlen[3:0];
    assign arvalid=rs==ADDRESS && s_arvalid[rgrant];
    genvar i;
    generate for(i=0;i<2;i=i+1) begin: port_response
        assign s_awready[i]=ws==ADDRESS && wgrant==i && awready;
        assign s_wready[i]=(ws==DATA || (ws==ADDRESS && awvalid && awready)) && wgrant==i && wready;
        assign s_wlast[i]=s_wready[i] && wlast;
        assign s_arready[i]=rs==ADDRESS && rgrant==i && arready;
        assign s_rvalid[i]=(rs==DATA || (rs==ADDRESS && arvalid && arready)) && rgrant==i && rvalid;
        assign s_rlast[i]=s_rvalid[i] && rlast;
    end endgenerate
endmodule
