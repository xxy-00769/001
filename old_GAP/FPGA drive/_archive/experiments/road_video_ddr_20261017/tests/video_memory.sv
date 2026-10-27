`timescale 1ns/1ps
// Native-channel BFM, not a DDR PHY. Frame RAMs in the DUT use vendor primitives.
module video_memory (
    input clk, rst_n, gapped,
    input axi_awvalid, axi_arvalid,
    output axi_awready, axi_arready,
    input [27:0] axi_awaddr, axi_araddr,
    input [3:0] axi_awuser_id, axi_awlen, axi_aruser_id, axi_arlen,
    input [255:0] axi_wdata,
    input [31:0] axi_wstrb,
    output axi_wready, axi_wusero_last,
    output [3:0] axi_wusero_id,
    output [255:0] axi_rdata,
    output [3:0] axi_rid,
    output axi_rvalid, axi_rlast
);
reg [255:0] video_mem [0:115199];
reg [255:0] acc_mem [0:127];
reg wp=0, rp=0;
reg [27:0] wa, ra;
reg [3:0] wi, ri;
integer wn=0, rn=0, wd=0, rd=0, ticks=0;
integer video_writes=0, video_reads=0, acc_commands=0, commands=0;
integer k, lane, idx;
reg [31:0] random_state=32'h48321abc;
function integer address_index(input [27:0] address);
integer offset;
begin
    offset=address & 28'h03fffff;
    if(address<28'h0800000 && offset<460800 && address[2:0]==0)
        address_index=(address[22] ? 57600 : 0)+(offset>>3);
    else address_index=-1;
end
endfunction
function [255:0] load(input [27:0] address);
integer index;
begin
    if(address>=28'h0800000 && address<28'h0800400)
        load=acc_mem[(address-28'h0800000)>>3];
    else begin
        index=address_index(address);
        // Combinational settling after a final beat is not a bus transaction.
        load=index<0 ? 256'bx : video_mem[index];
    end
end
endfunction
assign axi_awready=rst_n && !wp && random_state[0];
assign axi_arready=rst_n && !rp && random_state[1];
assign axi_wready=rst_n && wp && wd==0 && (!gapped || random_state[2]);
assign axi_wusero_last=axi_wready && wn==1;
assign axi_wusero_id=wi;
assign axi_rvalid=rst_n && rp && rd==0 && random_state[3];
assign axi_rlast=axi_rvalid && rn==1;
assign axi_rid=ri;
assign axi_rdata=(axi_rvalid===1'b1) ? load(ra) : 256'd0;
initial begin
    for(k=0;k<115200;k=k+1) video_mem[k]='x;
    for(k=0;k<128;k=k+1) acc_mem[k]={8{32'hc5a53219}};
end
always @(posedge clk) begin
    random_state<={random_state[30:0],
        random_state[31]^random_state[21]^random_state[1]^random_state[0]};
    ticks=ticks+1;
    if(!rst_n) begin wp<=0; rp<=0; wd<=0; rd<=0; wa<=0; ra<=0; end
    else begin
        if(wd>0) wd<=wd-1;
        if(rd>0) rd<=rd-1;
        if(axi_awvalid && axi_awready) begin
            wp<=1; wa<=axi_awaddr; wi<=axi_awuser_id; wn<=axi_awlen+1;
            wd<=7+random_state[6:4]; commands=commands+1;
            if(axi_awaddr>=28'h0800000) acc_commands=acc_commands+1;
        end
        if(axi_arvalid && axi_arready) begin
            rp<=1; ra<=axi_araddr; ri<=axi_aruser_id; rn<=axi_arlen+1;
            rd<=9+random_state[7:4]; commands=commands+1;
            if(axi_araddr>=28'h0800000) acc_commands=acc_commands+1;
        end
        if(axi_wready) begin
            if(wa>=28'h0800000 && wa<28'h0800400) begin
                idx=(wa-28'h0800000)>>3;
                for(lane=0;lane<32;lane=lane+1)
                    if(axi_wstrb[lane]) acc_mem[idx][lane*8+:8]=axi_wdata[lane*8+:8];
            end else begin
                idx=address_index(wa);
                if(idx<0) $fatal(1,"Accepted video write escaped allocation: %h",wa);
                if(axi_wstrb!==32'hffffffff) $fatal(1,"Partial video write");
                video_mem[idx]=axi_wdata;
                video_writes=video_writes+1;
            end
            wa<=wa+8; wn<=wn-1;
            if(wn==1) wp<=0;
        end
        if(axi_rvalid) begin
            if(ra<28'h0800000) begin
                if(address_index(ra)<0)
                    $fatal(1,"Accepted video read escaped allocation: %h",ra);
                video_reads=video_reads+1;
            end
            ra<=ra+8; rn<=rn-1;
            rd<=random_state[5:4];
            if(rn==1) rp<=0;
        end
    end
end
endmodule
