`timescale 1ns/1ps
// HMIC_S native port: WREADY requests data, WLAST comes FROM the controller.
// One outstanding burst in each direction; round robin between source ports.
// A grant is registered BEFORE exposing valid and held through the last beat.
module dual_ddr_arbiter #(parameter PORTS=2)(input clk, rst_n,
    input [PORTS*28-1:0] s_awaddr, input [PORTS*4-1:0] s_awlen, input [PORTS-1:0] s_awvalid,
    output [PORTS-1:0] s_awready, input [PORTS*256-1:0] s_wdata, input [PORTS*32-1:0] s_wstrb,
    output [PORTS-1:0] s_wready, s_wlast,
    input [PORTS*28-1:0] s_araddr, input [PORTS*4-1:0] s_arlen, input [PORTS-1:0] s_arvalid,
    output [PORTS-1:0] s_arready, output [PORTS-1:0] s_rvalid, s_rlast,
    output [27:0] awaddr, output [3:0] awlen, output awvalid,
    input awready, output [255:0] wdata, output [31:0] wstrb,
    input wready, wlast,
    output [27:0] araddr, output [3:0] arlen, output arvalid,
    input arready, rvalid, rlast);
    localparam GW=$clog2(PORTS);
    reg [GW-1:0] wgrant, rgrant, wnext, rnext;
    function [GW-1:0] choose;
      input [PORTS-1:0] valid; input [GW-1:0] first; integer k,j; reg found;
      begin choose=first;found=0;for(k=0;k<PORTS;k=k+1) begin
        j=first+k;if(j>=PORTS) j=j-PORTS;
        if(!found && valid[j]) begin choose=j;found=1;end
      end end
    endfunction
    reg [1:0] ws, rs;
    localparam IDLE=0, ADDRESS=1, DATA=2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin ws<=IDLE; rs<=IDLE; wgrant<=0; rgrant<=0; wnext<=0; rnext<=0; end
        else begin
            case(ws)
                IDLE: if(|s_awvalid) begin
                    wgrant<=choose(s_awvalid,wnext); ws<=ADDRESS;
                end
                ADDRESS: if(awvalid && awready) begin
                    if(wready && wlast) begin ws<=IDLE; wnext<=wgrant==PORTS-1 ? 0 : wgrant+1'b1; end
                    else ws<=DATA;
                end
                DATA: if(wlast && wready) begin ws<=IDLE; wnext<=wgrant==PORTS-1 ? 0 : wgrant+1'b1; end
            endcase
            case(rs)
                IDLE: if(|s_arvalid) begin
                    rgrant<=choose(s_arvalid,rnext); rs<=ADDRESS;
                end
                ADDRESS: if(arvalid && arready) begin
                    if(rvalid && rlast) begin rs<=IDLE; rnext<=rgrant==PORTS-1 ? 0 : rgrant+1'b1; end
                    else rs<=DATA;
                end
                DATA: if(rvalid && rlast) begin rs<=IDLE; rnext<=rgrant==PORTS-1 ? 0 : rgrant+1'b1; end
            endcase
        end
    end
    assign awaddr=s_awaddr[wgrant*28+:28];
    assign awlen=s_awlen[wgrant*4+:4];
    assign awvalid=ws==ADDRESS && s_awvalid[wgrant];
    assign wdata=s_wdata[wgrant*256+:256];
    assign wstrb=s_wstrb[wgrant*32+:32];
    assign araddr=s_araddr[rgrant*28+:28];
    assign arlen=s_arlen[rgrant*4+:4];
    assign arvalid=rs==ADDRESS && s_arvalid[rgrant];
    genvar i;
    generate for(i=0;i<PORTS;i=i+1) begin: port_response
        assign s_awready[i]=ws==ADDRESS && wgrant==i && awready;
        assign s_wready[i]=(ws==DATA || (ws==ADDRESS && awvalid && awready)) && wgrant==i && wready;
        assign s_wlast[i]=s_wready[i] && wlast;
        assign s_arready[i]=rs==ADDRESS && rgrant==i && arready;
        assign s_rvalid[i]=(rs==DATA || (rs==ADDRESS && arvalid && arready)) && rgrant==i && rvalid;
        assign s_rlast[i]=s_rvalid[i] && rlast;
    end endgenerate
endmodule
