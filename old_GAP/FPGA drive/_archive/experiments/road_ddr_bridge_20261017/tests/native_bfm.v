`timescale 1ns/1ps
// Behavioral native-UI model, NOT the encrypted vendor controller or DDR PHY.
module native_bfm #(
    parameter WORDS=2048,
    parameter [27:0] BASE=0
) (
    input clk, rst_n,
    input awvalid,
    output reg awready=0,
    input [27:0] awaddr,
    input [3:0] awid, awlen,
    input [255:0] wdata,
    input [31:0] wstrb,
    output reg wready=0, wlast=0,
    output reg [3:0] wid=0,
    input arvalid,
    output reg arready=0,
    input [27:0] araddr,
    input [3:0] arid, arlen,
    output reg [255:0] rdata=0,
    output reg [3:0] rid=0,
    output reg rvalid=0, rlast=0,
    input block_commands, block_data, drop_write, fast_data,
    input corrupt_id, corrupt_last,
    input [7:0] commit_delay
);
reg [127:0] memory [0:WORDS-1];
reg [127:0] video_memory [0:255];
reg wp=0, rp=0, commit_pending=0;
reg [27:0] wa, ra, ca;
reg [3:0] wi, ri;
reg [4:0] wn, rn;
reg [255:0] cd;
reg [31:0] cs;
integer delay_left=0, read_delay=0, beats=0, reads=0, commits=0;
reg [31:0] random_state=32'h4caab123;
integer k, index;
reg [255:0] sampled;
function [255:0] load;
input [27:0] address;
integer n;
begin
    n=(address-BASE)>>2;
    if(address>=BASE && n+1<WORDS) load={memory[n+1],memory[n]};
    else if(address<1024) load={video_memory[(address>>2)+1],video_memory[address>>2]};
    else begin $fatal(1,"BFM read outside arena: %h",address); load=0; end
end
endfunction
task store;
input [27:0] address;
input [255:0] data;
input [31:0] keep;
integer n,b;
begin
    n=(address-BASE)>>2;
    if(address>=BASE && n+1<WORDS) begin
        for(b=0;b<32;b=b+1)
            if(keep[b]) memory[n+b/16][(b%16)*8+:8]=data[b*8+:8];
    end else if(address<1024) begin
        for(b=0;b<32;b=b+1)
            if(keep[b]) video_memory[(address>>2)+b/16][(b%16)*8+:8]=data[b*8+:8];
    end else $fatal(1,"BFM write outside arena: %h",address);
end
endtask
initial begin
    for(k=0;k<WORDS;k=k+1) memory[k]={4{32'hc5a50000+k}};
    for(k=0;k<256;k=k+1) video_memory[k]={4{32'h12340000+k}};
end
always @(negedge clk) begin
    awready=rst_n && !wp && !commit_pending && !block_commands && random_state[0];
    arready=rst_n && !rp && !block_commands && random_state[1];
    wready=rst_n && wp && !commit_pending && !block_data && random_state[2];
    wlast=wready && (wn==1);
    wid=wi ^ (corrupt_id ? 4'h1 : 4'h0);
    rvalid=rst_n && rp && read_delay==0 && !block_data && random_state[3];
    rlast=rvalid && (rn==1);
    rid=ri ^ (corrupt_id ? 4'h1 : 4'h0);
    if(fast_data && awvalid && awready && !wp && !block_data) begin
        wready=1; wlast=awlen==0; wid=awid;
    end
    if(fast_data && arvalid && arready && !rp && !block_data) begin
        rvalid=1; rlast=arlen==0; rid=arid; rdata=load(araddr);
    end else if(rvalid) rdata=load(ra);
    if(corrupt_last) begin wlast=!wlast; rlast=!rlast; end
end
always @(posedge clk) begin
    random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
    if(!rst_n) begin wp=0; rp=0; commit_pending=0; read_delay=0; end
    else begin
        if(commit_pending) begin
            if(delay_left==0) begin
                if(!drop_write) begin store(ca,cd,cs); commits=commits+1; end
                commit_pending=0;
            end else delay_left=delay_left-1;
        end
        if(read_delay>0) read_delay=read_delay-1;
        if(awvalid && awready) begin
            if(awaddr[2:0]!=0) $fatal(1,"Native write misalignment");
            wp=1; wa=awaddr; wi=awid; wn={1'b0,awlen}+1;
        end
        if(wready) begin
            if(!wp || commit_pending) $fatal(1,"Invalid native write beat");
            ca=wa; cd=wdata; cs=wstrb; delay_left=commit_delay; commit_pending=1;
            wn=wn-1; wa=wa+8; beats=beats+1;
            if(wn==0) wp=0;
        end
        if(arvalid && arready) begin
            if(araddr[2:0]!=0) $fatal(1,"Native read misalignment");
            rp=1; ra=araddr; ri=arid; rn={1'b0,arlen}+1;
            read_delay=random_state[8:5];
        end
        if(rvalid) begin
            if(!rp) $fatal(1,"Invalid native read beat");
            rn=rn-1; ra=ra+8; reads=reads+1;
            read_delay=random_state[6:4];
            if(rn==0) rp=0;
        end
    end
end
endmodule
