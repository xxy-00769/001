`timescale 1ns/1ps
module s5_udp_rx_tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst_n = 0, link_up = 0;
    reg gmii_rx_dv = 0, gmii_rx_er = 0;
    reg [7:0] gmii_rxd = 0;
    wire packet_valid;
    reg manual_ready = 0, app_mode = 0;
    wire app_rx_ready;
    wire packet_ready = app_mode ? app_rx_ready : manual_ready;
    wire [255:0] packet_payload;
    wire [47:0] packet_peer_mac;
    wire [31:0] accepted_frames, rejected_frames, busy_drops;
    reg [7:0] bytes [0:511];
    integer cases = 0, i;
    reg [31:0] accepted_before, rejected_before, busy_before;
    reg [255:0] old_payload;
    wire app_tx_valid, app_led;
    reg app_tx_ready = 0;
    wire [255:0] app_tx_payload;
    wire [31:0] app_accepted;
    reg [255:0] app_replies [0:1];

    mes50hp_udp_rx dut (
        .clk(clk), .rst_n(rst_n), .link_up(link_up),
        .gmii_rx_dv(gmii_rx_dv), .gmii_rx_er(gmii_rx_er), .gmii_rxd(gmii_rxd),
        .packet_valid(packet_valid), .packet_ready(packet_ready),
        .packet_payload(packet_payload), .packet_peer_mac(packet_peer_mac),
        .accepted_frames(accepted_frames), .rejected_frames(rejected_frames),
        .busy_drops(busy_drops)
    );
    mes50hp_diag app (
        .clk(clk), .rst_n(rst_n), .link_up(link_up), .tick_ms(1'b0),
        .rx_valid(packet_valid && app_mode), .rx_ready(app_rx_ready),
        .rx_payload(packet_payload), .tx_valid(app_tx_valid),
        .tx_ready(app_tx_ready), .tx_payload(app_tx_payload),
        .led_requested(app_led), .session_active(),
        .accepted_count(app_accepted), .rejected_count()
    );
    task cycle;
        begin @(posedge clk); #1; @(negedge clk); end
    endtask
    task require;
        input condition;
        input [767:0] description;
        begin
            if (condition !== 1'b1) $fatal(1, "%0s", description);
        end
    endtask
    task drive;
        input [1023:0] filename;
        input integer size, error_at;
        integer n;
        begin
            $readmemh(filename, bytes, 0, size-1);
            for (n=0; n<size; n=n+1) begin
                gmii_rx_dv = 1;
                gmii_rxd = bytes[n];
                gmii_rx_er = n == error_at;
                cycle;
            end
            gmii_rx_dv = 0;
            gmii_rx_er = 0;
            cycle;
        end
    endtask
    task run_case;
        input [1023:0] filename;
        input integer size, valid_expected, error_at;
        input [255:0] expected_payload;
        integer n;
        begin
            require(!packet_valid, "previous packet not consumed");
            accepted_before = accepted_frames;
            rejected_before = rejected_frames;
            busy_before = busy_drops;
            $readmemh(filename, bytes, 0, size-1);
            for (n=0; n<size; n=n+1) begin
                gmii_rx_dv = 1;
                gmii_rxd = bytes[n];
                gmii_rx_er = n == error_at;
                cycle;
                require(!packet_valid, "payload published before the complete Ethernet frame");
            end
            gmii_rx_dv = 0;
            gmii_rx_er = 0;
            cycle;
            repeat (40) cycle;
            if (valid_expected) begin
                require(packet_valid, "valid UDP command missing");
                require(packet_payload === expected_payload, "payload byte order/content wrong");
                require(packet_peer_mac == 48'h02aabbccddee, "source MAC snapshot wrong");
                require(accepted_frames == accepted_before + 1, "accepted counter wrong");
                require(rejected_frames == rejected_before, "valid frame rejected");
                old_payload = packet_payload;
                repeat (5) begin
                    cycle;
                    require(packet_valid && packet_payload === old_payload, "stalled packet changed");
                end
                manual_ready = 1;
                cycle;
                manual_ready = 0;
                require(!packet_valid, "packet emitted more than once");
            end else begin
                require(!packet_valid, "invalid frame committed to application");
                require(accepted_frames == accepted_before, "invalid frame incremented accepted");
                require(rejected_frames == rejected_before + 1, "reject counter wrong");
            end
            require(busy_drops == busy_before, "unexpected busy drop in isolated case");
            cases = cases + 1;
        end
    endtask
    initial begin
        cycle;
        rst_n = 1;
        link_up = 1;
        cycle;
        `include "cases.svh"

        // A new frame starts inside the post-frame checksum validation period.
        accepted_before = accepted_frames;
        busy_before = busy_drops;
        drive("vectors/case_00.hex", 86, -1);
        repeat (12) cycle;
        drive("vectors/case_00.hex", 86, -1);
        repeat (40) cycle;
        require(packet_valid && accepted_frames == accepted_before+1, "busy RX corrupted first frame");
        require(busy_drops == busy_before+1, "busy incoming frame not counted exactly once");
        manual_ready = 1;
        cycle;
        manual_ready = 0;
        cases = cases + 1;

        // A full output slot is not overwritten by another valid frame.
        drive("vectors/case_00.hex", 86, -1);
        repeat (40) cycle;
        require(packet_valid, "backpressure setup missing packet");
        old_payload = packet_payload;
        accepted_before = accepted_frames;
        busy_before = busy_drops;
        drive("vectors/case_03.hex", 86, -1);
        repeat (40) cycle;
        require(packet_valid && packet_payload === old_payload, "backpressure overwrote payload");
        require(accepted_frames == accepted_before && busy_drops == busy_before+1, "full-slot drop wrong");
        manual_ready = 1;
        cycle;
        manual_ready = 0;
        cases = cases + 1;

        // Reset inside a frame: the remaining tail cannot become a packet.
        $readmemh("vectors/case_00.hex", bytes, 0, 85);
        for (i=0; i<30; i=i+1) begin
            gmii_rx_dv = 1;
            gmii_rxd = bytes[i];
            cycle;
        end
        rst_n = 0;
        cycle;
        rst_n = 1;
        for (i=30; i<86; i=i+1) begin
            gmii_rxd = bytes[i];
            cycle;
        end
        gmii_rx_dv = 0;
        cycle;
        repeat (40) cycle;
        require(!packet_valid && accepted_frames == 0, "reset tail committed");
        run_case("vectors/case_00.hex",86,1,-1,
            256'h4d35443101010000123456780000000100000000000000000000000080fe8ea1);
        cases = cases + 1;

        // Link loss flushes a pending packet and permits a new good frame.
        drive("vectors/case_00.hex", 86, -1);
        repeat (40) cycle;
        require(packet_valid, "link loss setup missing packet");
        link_up = 0;
        cycle;
        require(!packet_valid, "link loss did not flush pending packet");
        link_up = 1;
        cycle;
        run_case("vectors/case_00.hex",86,1,-1,
            256'h4d35443101010000123456780000000100000000000000000000000080fe8ea1);
        cases = cases + 1;

        // Exercise the real receiver -> application handshake, not a mock UDP
        // valid strobe. Bad network packets carry otherwise valid LED commands.
        $readmemh("vectors/app_replies.hex", app_replies);
        app_mode = 1;
        cycle;
        drive("vectors/case_00.hex",86,-1);
        repeat (40) cycle;
        require(app_tx_valid && app_tx_payload === app_replies[0], "network HELLO did not reach app");
        app_tx_ready = 1;
        cycle;
        app_tx_ready = 0;
        drive("vectors/bad_fcs_led.hex",86,-1);
        repeat (40) cycle;
        require(!app_tx_valid && !app_led && app_accepted == 1, "bad FCS LED command executed");
        drive("vectors/good_led.hex",86,-1);
        repeat (40) cycle;
        require(app_tx_valid && app_tx_payload === app_replies[1] && app_led &&
                app_accepted == 2, "good network LED command failed");
        app_tx_ready = 1;
        cycle;
        app_tx_ready = 0;
        drive("vectors/bad_udp_led.hex",86,-1);
        repeat (40) cycle;
        require(!app_tx_valid && app_led && app_accepted == 2, "bad UDP checksum changed LED");
        cases = cases + 4;
        $display("S5_RX_RESULT cases=%0d errors=0", cases);
        $finish;
    end
    initial begin
        #200000;
        $fatal(1, "watchdog expired");
    end
endmodule
