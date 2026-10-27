`timescale 1ns/1ps
// Application layer only. The adapter must supply complete, validated UDP
// datagrams from the configured peer, in network byte order, in this domain.
module mes50hp_diag #(
    parameter SESSION_MS = 5000,
    parameter MAX_LEASE_MS = 5000
) (
    input wire clk,
    input wire rst_n,
    input wire tick_ms,
    input wire link_up,
    input wire rx_valid,
    output wire rx_ready,
    input wire [255:0] rx_payload,
    output reg tx_valid,
    input wire tx_ready,
    output reg [255:0] tx_payload,
    output wire led_requested,
    output wire session_active,
    output reg [31:0] accepted_count,
    output reg [31:0] rejected_count
);
    localparam HELLO = 8'h01, PING = 8'h02, LED = 8'h03;
    localparam STATUS = 8'h80, ACK = 8'h81;
    localparam OK = 32'd0, DUPLICATE = 32'd1, BAD_SESSION = 32'd2;
    localparam STALE = 32'd3, BUSY = 32'd4;
    reg [31:0] active_session, last_seq, idle_ms, lease_left;
    reg led_value;
    wire [7:0] kind = rx_payload[215:208];
    wire [31:0] session = rx_payload[191:160];
    wire [31:0] seq = rx_payload[159:128];
    wire [31:0] value = rx_payload[127:96];
    wire [31:0] lease = rx_payload[95:64];
    wire [31:0] detail = rx_payload[63:32];
    wire expiring = tick_ms && active_session != 0 && idle_ms >= SESSION_MS-1;
    assign rx_ready = link_up && rst_n && !expiring && (!tx_valid || tx_ready);
    assign session_active = active_session != 0 && link_up && rst_n;
    assign led_requested = session_active && lease_left != 0 && led_value;

    function [31:0] crc28;
        input [223:0] bytes;
        reg [31:0] crc;
        reg [7:0] octet;
        integer i, j;
        begin
            crc = 32'hffffffff;
            for (i = 0; i < 28; i = i + 1) begin
                octet = bytes[223-i*8 -: 8];
                crc = crc ^ octet;
                for (j = 0; j < 8; j = j + 1)
                    crc = crc[0] ? ((crc >> 1) ^ 32'hedb88320) : (crc >> 1);
            end
            crc28 = ~crc;
        end
    endfunction

    function [255:0] reply;
        input [7:0] reply_kind;
        input [31:0] reply_session, reply_seq, reply_value, reply_lease, reply_detail;
        reg [223:0] head;
        begin
            head = {32'h4d354431, 8'd1, reply_kind, 16'd0,
                    reply_session, reply_seq, reply_value, reply_lease, reply_detail};
            reply = {head, crc28(head)};
        end
    endfunction

    wire legal_command =
        rx_payload[255:224] == 32'h4d354431 &&
        rx_payload[223:216] == 8'd1 &&
        rx_payload[207:192] == 16'd0 &&
        session != 0 && detail == 0 &&
        crc28(rx_payload[255:32]) == rx_payload[31:0] &&
        (((kind == HELLO || kind == PING) && value == 0 && lease == 0) ||
         (kind == LED && value <= 1 && lease >= 1 && lease <= MAX_LEASE_MS));
    always @(posedge clk) begin
        if (!rst_n) begin
            active_session <= 0;
            last_seq <= 0;
            idle_ms <= 0;
            lease_left <= 0;
            led_value <= 0;
            tx_valid <= 0;
            tx_payload <= 0;
            accepted_count <= 0;
            rejected_count <= 0;
        end else if (!link_up) begin
            active_session <= 0;
            last_seq <= 0;
            idle_ms <= 0;
            lease_left <= 0;
            led_value <= 0;
            tx_valid <= 0;
            tx_payload <= 0;
        end else begin
            if (tx_valid && tx_ready)
                tx_valid <= 0;
            if (tick_ms) begin
                if (lease_left != 0)
                    lease_left <= lease_left - 1'b1;
                if (active_session != 0)
                    idle_ms <= idle_ms + 1'b1;
            end
            // Expiration wins over input: the host must establish a new session.
            if (expiring) begin
                active_session <= 0;
                last_seq <= 0;
                idle_ms <= 0;
                lease_left <= 0;
                led_value <= 0;
            end else if (rx_valid && rx_ready) begin
                if (!legal_command) begin
                    rejected_count <= rejected_count + 1'b1;
                end else begin
                    tx_valid <= 1;
                    if (active_session == 0 && kind == HELLO) begin
                        active_session <= session;
                        last_seq <= seq;
                        idle_ms <= 0;
                        lease_left <= 0;
                        led_value <= 0;
                        accepted_count <= accepted_count + 1'b1;
                        tx_payload <= reply(ACK, session, seq, 0, 0, OK);
                    end else if (session != active_session || active_session == 0) begin
                        rejected_count <= rejected_count + 1'b1;
                        tx_payload <= reply(ACK, session, seq, 0, 0,
                                            kind == HELLO && active_session != 0 ? BUSY : BAD_SESSION);
                    end else if (seq <= last_seq) begin
                        rejected_count <= rejected_count + 1'b1;
                        tx_payload <= reply(ACK, session, seq, {31'd0,led_requested},
                                            lease_left, seq == last_seq ? DUPLICATE : STALE);
                    end else begin
                        last_seq <= seq;
                        idle_ms <= 0;
                        accepted_count <= accepted_count + 1'b1;
                        if (kind == LED) begin
                            led_value <= value[0];
                            lease_left <= lease;
                            tx_payload <= reply(ACK, session, seq, value, lease, OK);
                        end else if (kind == HELLO) begin
                            tx_payload <= reply(ACK, session, seq, {31'd0,led_requested},
                                                lease_left, OK);
                        end else begin
                            tx_payload <= reply(STATUS, session, seq, {31'd0,led_requested},
                                                lease_left, accepted_count + 1'b1);
                        end
                    end
                end
            end
        end
    end
endmodule
