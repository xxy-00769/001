`timescale 1ns/1ps
// Bounded diagnostic-only GMII receiver. Includes preamble and FCS at its input.
// No PHY, CDC, ARP or TX implementation is implied by this module.
module mes50hp_udp_rx #(
    parameter [47:0] LOCAL_MAC = 48'h02_50_48_50_00_01,
    parameter [31:0] LOCAL_IP = 32'hc0a8320b,
    parameter [31:0] PEER_IP = 32'hc0a83269,
    parameter [15:0] LOCAL_PORT = 16'd8000,
    parameter [15:0] PEER_PORT = 16'd8000
) (
    input wire clk,
    input wire rst_n,
    input wire link_up,
    input wire gmii_rx_dv,
    input wire gmii_rx_er,
    input wire [7:0] gmii_rxd,
    output reg packet_valid,
    input wire packet_ready,
    output reg [255:0] packet_payload,
    output reg [47:0] packet_peer_mac,
    output reg [31:0] accepted_frames,
    output reg [31:0] rejected_frames,
    output reg [31:0] busy_drops
);
    localparam IDLE=0, PREAMBLE=1, CAPTURE=2, DRAIN=3;
    localparam HEADER=4, IP_SUM=5, UDP_SUM=6, COMMIT=7;
    reg [2:0] state;
    reg dv_d;
    reg [3:0] pre_count;
    reg [7:0] count;
    reg [7:0] frame [0:127];
    reg error_seen;
    reg [31:0] crc;
    reg [4:0] word_index;
    reg [16:0] checksum;
    integer k;
    wire start_frame = gmii_rx_dv && !dv_d;
    localparam [31:0] PSEUDO =
        (LOCAL_IP >> 16) + (LOCAL_IP & 32'hffff) +
        (PEER_IP >> 16) + (PEER_IP & 32'hffff) + 32'd17 + 32'd40;

    function [31:0] crc_byte;
        input [31:0] before_crc;
        input [7:0] octet;
        reg [31:0] c;
        integer bit_index;
        begin
            c = before_crc ^ octet;
            for (bit_index=0; bit_index<8; bit_index=bit_index+1)
                c = c[0] ? ((c >> 1) ^ 32'hedb88320) : (c >> 1);
            crc_byte = c;
        end
    endfunction
    function [16:0] sum_word;
        input [16:0] s;
        input [15:0] word_value;
        begin
            sum_word = {1'b0,s[15:0]} + word_value + s[16];
        end
    endfunction
    wire [15:0] ip_word = {frame[14+word_index*2],frame[15+word_index*2]};
    wire [15:0] udp_word = {frame[34+word_index*2],frame[35+word_index*2]};
    wire [16:0] ip_next = sum_word(checksum, ip_word);
    wire [16:0] udp_next = sum_word(checksum, udp_word);
    wire [15:0] ip_folded = ip_next[15:0] + ip_next[16];
    wire [15:0] udp_folded = udp_next[15:0] + udp_next[16];
    wire format_ok =
        {frame[0],frame[1],frame[2],frame[3],frame[4],frame[5]} == LOCAL_MAC &&
        {frame[6],frame[7],frame[8],frame[9],frame[10],frame[11]} != 0 &&
        !frame[6][0] &&
        {frame[12],frame[13]} == 16'h0800 &&
        frame[14] == 8'h45 &&
        {frame[16],frame[17]} == 16'd60 &&
        (frame[20] & 8'hbf) == 0 && frame[21] == 0 &&
        frame[22] != 0 && frame[23] == 8'd17 &&
        {frame[26],frame[27],frame[28],frame[29]} == PEER_IP &&
        {frame[30],frame[31],frame[32],frame[33]} == LOCAL_IP &&
        {frame[34],frame[35]} == PEER_PORT &&
        {frame[36],frame[37]} == LOCAL_PORT &&
        {frame[38],frame[39]} == 16'd40;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            dv_d <= 0;
            pre_count <= 0;
            count <= 0;
            error_seen <= 0;
            crc <= 32'hffffffff;
            checksum <= 0;
            word_index <= 0;
            packet_valid <= 0;
            packet_payload <= 0;
            packet_peer_mac <= 0;
            accepted_frames <= 0;
            rejected_frames <= 0;
            busy_drops <= 0;
        end else if (!link_up) begin
            state <= IDLE;
            dv_d <= 0;
            pre_count <= 0;
            count <= 0;
            error_seen <= 0;
            crc <= 32'hffffffff;
            checksum <= 0;
            word_index <= 0;
            packet_valid <= 0;
            packet_payload <= 0;
            packet_peer_mac <= 0;
        end else begin
            dv_d <= gmii_rx_dv;
            if (packet_valid && packet_ready)
                packet_valid <= 0;
            // A frame arriving during validation is discarded as a whole.
            // A later IDLE transition must never start capture mid-frame.
            if (start_frame && state != IDLE)
                busy_drops <= busy_drops + 1'b1;
            case (state)
                IDLE: if (start_frame) begin
                    count <= 0;
                    crc <= 32'hffffffff;
                    error_seen <= gmii_rx_er;
                    pre_count <= 1;
                    state <= gmii_rxd == 8'h55 ? PREAMBLE : DRAIN;
                end
                PREAMBLE: begin
                    if (!gmii_rx_dv) begin
                        rejected_frames <= rejected_frames + 1'b1;
                        state <= IDLE;
                    end else begin
                        error_seen <= error_seen | gmii_rx_er;
                        if (pre_count == 7) begin
                            state <= gmii_rxd == 8'hd5 ? CAPTURE : DRAIN;
                        end else if (gmii_rxd != 8'h55) begin
                            state <= DRAIN;
                        end else begin
                            pre_count <= pre_count + 1'b1;
                        end
                    end
                end
                CAPTURE: begin
                    if (gmii_rx_dv) begin
                        error_seen <= error_seen | gmii_rx_er;
                        crc <= crc_byte(crc, gmii_rxd);
                        if (count < 128) begin
                            frame[count[6:0]] <= gmii_rxd;
                            count <= count + 1'b1;
                        end
                    end else if (count == 78 && !error_seen && crc == 32'hdebb20e3) begin
                        state <= HEADER;
                    end else begin
                        rejected_frames <= rejected_frames + 1'b1;
                        state <= IDLE;
                    end
                end
                DRAIN: if (!gmii_rx_dv) begin
                    rejected_frames <= rejected_frames + 1'b1;
                    state <= IDLE;
                end
                HEADER: begin
                    if (format_ok) begin
                        checksum <= 0;
                        word_index <= 0;
                        state <= IP_SUM;
                    end else begin
                        rejected_frames <= rejected_frames + 1'b1;
                        state <= IDLE;
                    end
                end
                IP_SUM: begin
                    checksum <= ip_next;
                    if (word_index == 9) begin
                        word_index <= 0;
                        if (ip_folded != 16'hffff) begin
                            rejected_frames <= rejected_frames + 1'b1;
                            state <= IDLE;
                        end else if ({frame[40],frame[41]} == 0) begin
                            // IPv4 UDP checksum=0 explicitly means absent.
                            state <= COMMIT;
                        end else begin
                            checksum <= (PSEUDO & 32'hffff) + (PSEUDO >> 16);
                            state <= UDP_SUM;
                        end
                    end else begin
                        word_index <= word_index + 1'b1;
                    end
                end
                UDP_SUM: begin
                    checksum <= udp_next;
                    if (word_index == 19) begin
                        if (udp_folded == 16'hffff) begin
                            state <= COMMIT;
                        end else begin
                            rejected_frames <= rejected_frames + 1'b1;
                            state <= IDLE;
                        end
                    end else begin
                        word_index <= word_index + 1'b1;
                    end
                end
                COMMIT: begin
                    if (!packet_valid || packet_ready) begin
                        for (k=0; k<32; k=k+1)
                            packet_payload[255-k*8 -: 8] <= frame[42+k];
                        packet_peer_mac <= {frame[6],frame[7],frame[8],frame[9],frame[10],frame[11]};
                        packet_valid <= 1;
                        accepted_frames <= accepted_frames + 1'b1;
                    end else begin
                        busy_drops <= busy_drops + 1'b1;
                    end
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
