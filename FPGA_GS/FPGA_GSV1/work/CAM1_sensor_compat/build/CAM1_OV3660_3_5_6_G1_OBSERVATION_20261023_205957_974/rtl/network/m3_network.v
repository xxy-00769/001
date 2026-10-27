`timescale 1ns/1ps
module m3_network #(parameter HD_DISPLAY=0,ENABLE_VIDEO=1,ENABLE_CONTROL=1,ENABLE_UPLOAD=1,PHY_INTERNAL_DELAY=0,E1_PHY=0,
 parameter LOCAL_MAC=48'h020047535631, LOCAL_IP=32'hc0a83202, HOST_IP=32'hc0a83201, PORT=50000)(input clk,rst_n,sys_clk,phy_reset_n,
 input rgmii_rxc,rgmii_rx_ctl,input [3:0] rgmii_rxd,
 output rgmii_txc,rgmii_tx_ctl,output [3:0] rgmii_txd,output phy_rstn,output phy_mdc,inout phy_mdio,output diagnostic_tx,
 input pc,fs,selected,quarter,request,output de,output [15:0] pixel,output healthy,
 input key_event,input [3:0] key_code,input [31:0] latest_front_id,
 output acquire,release_frame,input grant,held,input [1:0] bank,input [31:0] identity,stamp,
 output [2:0] feedback,
 output [27:0] awaddr,output [3:0] awlen,output awvalid,input awready,
 output [255:0] wdata,output [31:0] wstrb,input wready,wlast,
 output [27:0] araddr,upload_araddr,output [3:0] arlen,upload_arlen,
 output arvalid,upload_arvalid,input arready,upload_arready,
 input [255:0] rdata,input rvalid,rlast,upload_rvalid,upload_rlast,
 input [383:0] camera_diagnostics);
 wire phase,phase_d,pll_lock,nc;
 wire phy_ready;wire [127:0] phy_diagnostics;
 generate if(!PHY_INTERNAL_DELAY) begin: original_phy
 m3_eth_pll pll(.clkin1(rgmii_rxc),.clkout0(phase),.clkout1(phase_d),.pll_lock(pll_lock));
 assign phy_diagnostics=0;assign diagnostic_tx=1'b1;
 assign phy_ready=pll_lock && phy_rstn;assign phy_mdc=0;assign phy_mdio=1'bz;
 end else if(E1_PHY) begin: e1_phy
 // Own RXC, same PLL parameters and IO structure as accepted E1.
 m3_eth_pll pll(.clkin1(rgmii_rxc),.clkout0(phase),.clkout1(phase_d),.pll_lock(pll_lock));
 wire manager_ready;
 m36_phy2 #(.STRAP_ONLY(0),.TX_DELAY_ENABLE(1),.RX_DELAY_ENABLE(1)) manager(.clk(sys_clk),.rst_n(phy_reset_n),.phy_rstn(phy_rstn),.rx_clock(nc),
 .mdc(phy_mdc),.mdio(phy_mdio),.ready(manager_ready),.configured(),.address(),.status(),.diagnostics(phy_diagnostics));
 assign phy_ready=manager_ready && pll_lock;
 // Diagnostic output is connected below, at the registered GMII boundary.
 end else begin: managed_phy
 assign phase=rgmii_rxc;assign phase_d=nc;assign pll_lock=1'b1;
 m36_phy2 manager(.clk(sys_clk),.rst_n(phy_reset_n),.phy_rstn(phy_rstn),.rx_clock(nc),
 .mdc(phy_mdc),.mdio(phy_mdio),.ready(phy_ready),.configured(),.address(),.status(),.diagnostics(phy_diagnostics));
 end endgenerate
 reg [22:0] reset_count=0;
 always @(posedge sys_clk) if(!phy_reset_n) reset_count<=0;else if(!phy_rstn) reset_count<=reset_count+1'b1;
 assign phy_rstn=E1_PHY ? reset_count>=1000000:reset_count[22];
 reg [2:0] nr;always @(posedge nc or negedge phy_ready)
 if(!phy_ready) nr<=0;else nr<={nr[1:0],1'b1};
 reg [2:0] nr90;
 always @(posedge phase_d or negedge phy_ready)
 if(!phy_ready) nr90<=0;else nr90<={nr90[1:0],1'b1};
 wire rxv,rxe,txv;wire [7:0] rxd,txd;
 generate if(!PHY_INTERNAL_DELAY) begin: port1_io
 m3_rgmii_interface phy(.rst(!nr[2]),.rst90(!nr90[2]),.rgmii_rxc_phase_d(phase_d),.rgmii_clk(nc),.rgmii_clk_90p(phase_d),
 .mac_tx_data_valid(txv),.mac_tx_data(txd),.mac_rx_error(rxe),.mac_rx_data_valid(rxv),.mac_rx_data(rxd),
 .rgmii_rxc(phase),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
 .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
 end else if(E1_PHY) begin: e1_io
 // MAC already registers txd/txv. E1 adds this GMII boundary register.
 reg [7:0] tx_data;reg tx_valid;
 always @(posedge nc) if(!nr[2]) begin tx_data<=0;tx_valid<=0;end
 else begin tx_data<=txd;tx_valid<=txv;end
 m365_tx_observer observer(.sc(sys_clk),.nc(nc),.rst_n(phy_reset_n),
 .phy(phy_diagnostics),.pll_lock(pll_lock),.phy_ready(phy_ready),
 .txv(tx_valid),.txd(tx_data),.camera_diagnostics(camera_diagnostics),.uart_tx(diagnostic_tx));
 // Deterministic RGMII-ID: same global launch clock; PHY supplies TX delay.
 m364_e1_rgmii phy(.rst(!nr[2]),.rgmii_rxc_phase_d(nc),.rgmii_clk(nc),.rgmii_clk_90p(phase_d),
 .mac_tx_data_valid(tx_valid),.mac_tx_data(tx_data),.mac_rx_error(rxe),.mac_rx_data_valid(rxv),.mac_rx_data(rxd),
 .rgmii_rxc(phase),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
 .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
 end else begin: port2_io
 m36_rgmii_interface phy(.rst(!nr[2]),.rst90(!nr90[2]),.rgmii_rxc_phase_d(phase_d),.rgmii_clk(nc),.rgmii_clk_90p(phase_d),
 .mac_tx_data_valid(txv),.mac_tx_data(txd),.mac_rx_error(rxe),.mac_rx_data_valid(rxv),.mac_rx_data(rxd),
 .rgmii_rxc(phase),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
 .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
 end endgenerate
 wire queue_mac_ready,queue_rx_ready;
 m3_queue_reset queue_epoch(.nc(nc),.dc(clk),.rst_n(rst_n),.phy_ready(nr[2]),
 .mac_ready(queue_mac_ready),.rx_ready(queue_rx_ready));
 wire [31:0] diag_crc,diag_over,diag_packets,diag_bad,diag_session,diag_accept,diag_upload,diag_abort;
 wire [63:0] mac_stats;wire [31:0] displayed_frames;
 wire [3:0] pending,ack,diag_publication;wire [63:0] lengths;wire [12:0] ra;wire [7:0] rd;
 wire tw,treq,tack;wire [10:0] ta;wire [7:0] td;wire [15:0] tl;
 m3_mac mac(.nc(nc),.nrst(queue_mac_ready),.rxd(rxd),.rxv(rxv),.rxe(rxe),.txd(txd),.txv(txv),
 .dc(clk),.drst(PHY_INTERNAL_DELAY ? queue_rx_ready:rst_n),.rx_pending(pending),.rx_ack(ack),.rx_lengths(lengths),.rx_addr(ra),.rx_data(rd),
 .tx_we(tw),.tx_addr(ta),.tx_data(td),.tx_req(treq),.tx_length(tl),.tx_ack(tack),.crc_errors(diag_crc),.rx_overruns(diag_over),.rx_stats(mac_stats),.diagnostic_publication(diag_publication));
 wire begin_frame,begin_ack,publish,ready;wire [1:0] write_bank;
 wire [31:0] right_id;
 generate if(ENABLE_VIDEO) begin: video
 m3_right_store #(.HD_DISPLAY(HD_DISPLAY)) right_store(.clk(clk),.rst_n(rst_n),.pc(pc),.fs(fs),.selected(selected),.quarter(quarter),.request(request),
 .begin_frame(begin_frame),.begin_ack(begin_ack),.write_bank(write_bank),.publish(publish),.frame_id(right_id),.ready(ready),.displayed_frames(displayed_frames),
 .de(de),.pixel(pixel),.araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),
 .rdata(rdata),.rvalid(rvalid),.rlast(rlast));
 end else begin
 assign begin_ack=0;assign write_bank=0;assign ready=0;assign displayed_frames=0;
 assign de=0;assign pixel=0;assign araddr=0;assign arlen=0;assign arvalid=0;
 end endgenerate
 wire online,tick;wire [7:0] fps;wire frag,frag_taken;wire [31:0] fid,ft,off;wire [15:0] fi;
 wire [8:0] fwa;wire [31:0] fwd;
 wire ke;wire [3:0] kc;
 generate if(ENABLE_CONTROL) begin: control
 m3_key_mailbox keys(.sc(sys_clk),.dc(clk),.rst_n(phy_reset_n),.event_in(key_event),.code_in(key_code),.event_out(ke),.code_out(kc));
 end else begin assign ke=0;assign kc=0;end endgenerate
 m3_net_core #(.LOCAL_MAC(LOCAL_MAC),.LOCAL_IP(LOCAL_IP),.HOST_IP(HOST_IP),.PORT(PORT),.ENABLE_VIDEO(ENABLE_VIDEO),.ENABLE_CONTROL(ENABLE_CONTROL),.ENABLE_UPLOAD(ENABLE_UPLOAD),.REQUIRE_LINK(PHY_INTERNAL_DELAY)) core(.clk(clk),.rst_n(rst_n),.rx_reset_n(queue_rx_ready),.rx_pending(pending),.rx_ack(ack),.rx_lengths(lengths),.rx_addr(ra),.rx_data(rd),
 .tx_we(tw),.tx_addr(ta),.tx_data(td),.tx_req(treq),.tx_length(tl),.tx_ack(tack),
 .right_begin(begin_frame),.right_begin_ack(begin_ack),.right_bank(write_bank),.right_publish(publish),.right_id(right_id),.right_healthy(healthy),
 .awaddr(awaddr),.awlen(awlen),.awvalid(awvalid),.awready(awready),.wdata(wdata),.wstrb(wstrb),.wready(wready),.wlast(wlast),
 .key_event(ke),.key_code(kc),.latest_front_id(latest_front_id),.feedback(feedback),.online(online),.tick_ms(tick),.upload_fps(fps),
 .fragment_ready(frag),.fragment_taken(frag_taken),.front_id(fid),.front_time(ft),.front_offset(off),.front_index(fi),.front_word_addr(fwa),.front_word_data(fwd),
 .mac_crc_errors(mac_stats[63:32]),.mac_overruns(mac_stats[31:0]),.displayed_frames(displayed_frames),
 .session(diag_session),.rx_packets(diag_packets),.bad_packets(diag_bad),.diagnostic_accept(diag_accept),.right_frames(),.right_drops(),.control_events());
 generate if(ENABLE_UPLOAD) begin: upload
 m3_upload uploader(.clk(clk),.rst_n(rst_n),.online(online),.tick_ms(tick),.fps(fps),
 .acquire(acquire),.release_frame(release_frame),.grant(grant),.held(held),.bank(bank),.identity(identity),.stamp(stamp),
 .fragment_ready(frag),.fragment_taken(frag_taken),.frame_id(fid),.frame_time(ft),.offset(off),.index(fi),.word_addr(fwa),.word_data(fwd),
 .araddr(upload_araddr),.arlen(upload_arlen),.arvalid(upload_arvalid),.arready(upload_arready),
 .rdata(rdata),.rvalid(upload_rvalid),.rlast(upload_rlast),.frames(diag_upload),.aborts(diag_abort));
 end else begin
 assign diag_upload=0;assign diag_abort=0;
 assign acquire=0;assign release_frame=0;assign frag=0;assign fid=0;assign ft=0;assign off=0;assign fi=0;assign fwd=0;
 assign upload_araddr=0;assign upload_arlen=0;assign upload_arvalid=0;
 end endgenerate
 generate if(PHY_INTERNAL_DELAY && !E1_PHY) begin: passive_diagnostics
 m361_diag diag(.sc(sys_clk),.nc(nc),.dc(clk),.rst_n(phy_reset_n),.phy(phy_diagnostics),
 .phy_rstn(phy_rstn),.phy_ready(phy_ready),.mac_ready(queue_mac_ready),.core_ready(queue_rx_ready),
 .raw_ctl(rgmii_rx_ctl),.rxv(rxv),.txv(txv),.txd(txd),.published(diag_publication),
 .crc_errors(diag_crc),.overruns(diag_over),.packets(diag_packets),.bad(diag_bad),
 .accepted(diag_accept),.session(diag_session),.uploads(diag_upload),.aborts(diag_abort),
 .online(online),.tx_req(treq),.tx_ack(tack),.uart_tx(diagnostic_tx));
 end endgenerate

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

// Async assert / local synchronous release. Both producer and consumer begin
// at slot zero after PHY lock loss or DDR reset; control state stays intact.
module m3_queue_reset(input nc,dc,rst_n,phy_ready,output mac_ready,rx_ready);
 wire reset_n=rst_n && phy_ready;reg [2:0] n,c;
 always @(posedge nc or negedge reset_n) if(!reset_n) n<=0;else n<={n[1:0],1'b1};
 always @(posedge dc or negedge reset_n) if(!reset_n) c<=0;else c<={c[1:0],1'b1};
 assign mac_ready=n[2];assign rx_ready=c[2];
endmodule
