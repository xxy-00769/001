`timescale 1ns/1ps
module m3_network(input clk,rst_n,sys_clk,phy_reset_n,
 input rgmii_rxc,rgmii_rx_ctl,input [3:0] rgmii_rxd,
 output rgmii_txc,rgmii_tx_ctl,output [3:0] rgmii_txd,output phy_rstn,
 input pc,fs,selected,quarter,request,output de,output [15:0] pixel,output healthy,
 input key_event,input [3:0] key_code,input [31:0] latest_front_id,
 output acquire,release_frame,input grant,held,input [1:0] bank,input [31:0] identity,stamp,
 output [2:0] feedback,
 output [27:0] awaddr,output [3:0] awlen,output awvalid,input awready,
 output [255:0] wdata,output [31:0] wstrb,input wready,wlast,
 output [27:0] araddr,upload_araddr,output [3:0] arlen,upload_arlen,
 output arvalid,upload_arvalid,input arready,upload_arready,
 input [255:0] rdata,input rvalid,rlast,upload_rvalid,upload_rlast);
 wire phase,phase_d,pll_lock,nc;
 m3_eth_pll pll(.clkin1(rgmii_rxc),.clkout0(phase),.clkout1(phase_d),.pll_lock(pll_lock));
 reg [22:0] reset_count=0;
 always @(posedge sys_clk) if(!phy_reset_n) reset_count<=0;else if(!reset_count[22]) reset_count<=reset_count+1'b1;
 assign phy_rstn=reset_count[22];
 reg [2:0] nr;always @(posedge nc or negedge phy_reset_n)
 if(!phy_reset_n) nr<=0;else nr<={nr[1:0],pll_lock && phy_rstn};
 wire rxv,rxe,txv;wire [7:0] rxd,txd;
 m3_rgmii_interface phy(.rst(!nr[2]),.rgmii_rxc_phase_d(phase_d),.rgmii_clk(nc),.rgmii_clk_90p(phase_d),
 .mac_tx_data_valid(txv),.mac_tx_data(txd),.mac_rx_error(rxe),.mac_rx_data_valid(rxv),.mac_rx_data(rxd),
 .rgmii_rxc(phase),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
 .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
 wire [3:0] pending,ack;wire [63:0] lengths;wire [12:0] ra;wire [7:0] rd;
 wire tw,treq,tack;wire [10:0] ta;wire [7:0] td;wire [15:0] tl;
 m3_mac mac(.nc(nc),.nrst(nr[2]),.rxd(rxd),.rxv(rxv),.rxe(rxe),.txd(txd),.txv(txv),
 .dc(clk),.drst(rst_n),.rx_pending(pending),.rx_ack(ack),.rx_lengths(lengths),.rx_addr(ra),.rx_data(rd),
 .tx_we(tw),.tx_addr(ta),.tx_data(td),.tx_req(treq),.tx_length(tl),.tx_ack(tack),.crc_errors(),.rx_overruns());
 wire begin_frame,begin_ack,write_bank,publish,ready;
 wire [31:0] right_id;
 m3_right_store right_store(.clk(clk),.rst_n(rst_n),.pc(pc),.fs(fs),.selected(selected),.quarter(quarter),.request(request),
 .begin_frame(begin_frame),.begin_ack(begin_ack),.write_bank(write_bank),.publish(publish),.frame_id(right_id),.ready(ready),
 .de(de),.pixel(pixel),.araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),
 .rdata(rdata),.rvalid(rvalid),.rlast(rlast));
 wire online,tick;wire [7:0] fps;wire frag,frag_taken;wire [31:0] fid,ft,off;wire [15:0] fi;
 wire [8:0] fwa;wire [31:0] fwd;
 wire ke;wire [3:0] kc;
 m3_key_mailbox keys(.sc(sys_clk),.dc(clk),.rst_n(phy_reset_n),.event_in(key_event),.code_in(key_code),.event_out(ke),.code_out(kc));
 m3_net_core core(.clk(clk),.rst_n(rst_n),.rx_pending(pending),.rx_ack(ack),.rx_lengths(lengths),.rx_addr(ra),.rx_data(rd),
 .tx_we(tw),.tx_addr(ta),.tx_data(td),.tx_req(treq),.tx_length(tl),.tx_ack(tack),
 .right_begin(begin_frame),.right_begin_ack(begin_ack),.right_bank(write_bank),.right_publish(publish),.right_id(right_id),.right_healthy(healthy),
 .awaddr(awaddr),.awlen(awlen),.awvalid(awvalid),.awready(awready),.wdata(wdata),.wstrb(wstrb),.wready(wready),.wlast(wlast),
 .key_event(ke),.key_code(kc),.latest_front_id(latest_front_id),.feedback(feedback),.online(online),.tick_ms(tick),.upload_fps(fps),
 .fragment_ready(frag),.fragment_taken(frag_taken),.front_id(fid),.front_time(ft),.front_offset(off),.front_index(fi),.front_word_addr(fwa),.front_word_data(fwd),
 .session(),.rx_packets(),.bad_packets(),.right_frames(),.right_drops(),.control_events());
 m3_upload uploader(.clk(clk),.rst_n(rst_n),.online(online),.tick_ms(tick),.fps(fps),
 .acquire(acquire),.release_frame(release_frame),.grant(grant),.held(held),.bank(bank),.identity(identity),.stamp(stamp),
 .fragment_ready(frag),.fragment_taken(frag_taken),.frame_id(fid),.frame_time(ft),.offset(off),.index(fi),.word_addr(fwa),.word_data(fwd),
 .araddr(upload_araddr),.arlen(upload_arlen),.arvalid(upload_arvalid),.arready(upload_arready),
 .rdata(rdata),.rvalid(upload_rvalid),.rlast(upload_rlast),.frames(),.aborts());
endmodule

module m3_key_mailbox(input sc,dc,rst_n,event_in,input [3:0] code_in,output reg event_out,output reg [3:0] code_out);
 reg req,ack;reg [3:0] payload;reg [1:0] a,r;
 always @(posedge sc or negedge rst_n) if(!rst_n) begin req<=0;payload<=0;a<=0;end
 else begin a<={a[0],ack};if(event_in && req==a[1]) begin req<=~req;payload<=code_in;end end
 always @(posedge dc or negedge rst_n) if(!rst_n) begin r<=0;ack<=0;event_out<=0;code_out<=0;end
 else begin r<={r[0],req};event_out<=0;if(r[1]!=ack) begin code_out<=payload;event_out<=1;ack<=r[1];end end
endmodule

module m3_status_mailbox(input sc,dc,rst_n,input [2:0] value,output reg [2:0] out_value);
 reg req,ack;reg [2:0] payload;reg [1:0] a,r;
 always @(posedge sc or negedge rst_n) if(!rst_n) begin req<=0;payload<=0;a<=0;end
 else begin a<={a[0],ack};if(value!=payload && req==a[1]) begin payload<=value;req<=~req;end end
 always @(posedge dc or negedge rst_n) if(!rst_n) begin r<=0;ack<=0;out_value<=0;end
 else begin r<={r[0],req};if(r[1]!=ack) begin out_value<=payload;ack<=r[1];end end
endmodule
