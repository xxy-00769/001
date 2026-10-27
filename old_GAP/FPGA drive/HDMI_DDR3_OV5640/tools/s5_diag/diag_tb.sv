`timescale 1ns/1ps
module s5_diag_tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst_n = 0, tick_ms = 0, link_up = 0;
    reg rx_valid = 0, tx_ready = 0;
    reg [255:0] rx_payload = 0;
    wire rx_ready, tx_valid, led_requested, session_active;
    wire [255:0] tx_payload;
    wire [31:0] accepted_count, rejected_count;
    reg [255:0] commands [0:18];
    reg [255:0] replies [0:15];
    reg [255:0] held;
    integer cases = 0, i;

    mes50hp_diag #(.SESSION_MS(50)) dut (
        .clk(clk), .rst_n(rst_n), .tick_ms(tick_ms), .link_up(link_up),
        .rx_valid(rx_valid), .rx_ready(rx_ready), .rx_payload(rx_payload),
        .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_payload(tx_payload),
        .led_requested(led_requested), .session_active(session_active),
        .accepted_count(accepted_count), .rejected_count(rejected_count)
    );

    task cycle;
        begin @(posedge clk); #1; @(negedge clk); end
    endtask
    task require;
        input condition;
        input [511:0] message;
        begin
            if (condition !== 1'b1) $fatal(1, "%0s", message);
        end
    endtask
    task send_raw;
        input [255:0] payload;
        begin
            require(rx_ready, "unexpected receive backpressure");
            rx_payload = payload;
            rx_valid = 1;
            cycle;
            rx_valid = 0;
        end
    endtask
    task receive_reply;
        input integer number;
        begin
            require(tx_valid, "reply missing");
            if (tx_payload !== replies[number])
                $fatal(1, "reply %0d got=%064h expected=%064h", number, tx_payload, replies[number]);
            tx_ready = 1;
            cycle;
            tx_ready = 0;
            require(!tx_valid, "reply not consumed exactly once");
        end
    endtask
    task transact;
        input integer command_number, reply_number;
        begin
            send_raw(commands[command_number]);
            receive_reply(reply_number);
            cases = cases + 1;
        end
    endtask
    task ms;
        input integer amount;
        integer t;
        begin
            for (t=0; t<amount; t=t+1) begin
                tick_ms = 1;
                cycle;
                tick_ms = 0;
                cycle;
            end
        end
    endtask
    task reject_raw;
        input [255:0] payload;
        reg [31:0] before_rejected;
        begin
            before_rejected = rejected_count;
            send_raw(payload);
            cycle;
            require(!tx_valid, "malformed packet emitted a reply");
            require(rejected_count == before_rejected + 1, "bad packet not counted");
            cases = cases + 1;
        end
    endtask
    task reset_core;
        begin
            rst_n = 0;
            cycle;
            require(!tx_valid && !led_requested && !session_active, "reset did not clear state");
            rst_n = 1;
            cycle;
        end
    endtask

    initial begin
        $readmemh("vectors/commands.hex", commands);
        $readmemh("vectors/replies.hex", replies);
        cycle;
        link_up = 1;
        reset_core;
        transact(0,0);
        transact(1,1);
        transact(2,2);
        require(led_requested, "LED command not applied");
        ms(10);
        transact(3,3);
        require(dut.lease_left == 10 && led_requested, "duplicate renewed or changed LED");
        transact(4,4);
        ms(10);
        require(!led_requested, "lease did not expire");
        transact(5,5);
        transact(6,6);
        transact(7,7);
        reject_raw(commands[8]);
        reject_raw(commands[9]);
        reject_raw(commands[10]);
        for (i=0; i<256; i=i+1)
            reject_raw(commands[11] ^ (256'd1 << i));
        require(accepted_count == 4, "invalid packet affected accepted count");
        transact(11,8);
        require(led_requested, "maximum legal lease rejected");

        // Output must remain stable while the transport applies backpressure.
        send_raw(commands[12]);
        require(tx_payload === replies[7], "second-session BUSY reply wrong");
        held = tx_payload;
        rx_valid = 1;
        rx_payload = commands[5];
        repeat (12) begin
            cycle;
            require(!rx_ready && tx_valid && tx_payload === held, "backpressure lost reply");
        end
        rx_valid = 0;
        receive_reply(7);
        cases = cases + 1;
        require(accepted_count == 5, "backpressured command was accepted");

        // Exactly the 50th tick expires the active session and its LED lease.
        ms(49);
        require(session_active && led_requested, "session expired early");
        ms(1);
        require(!session_active && !led_requested, "session/LED did not expire");
        transact(12,9);
        transact(13,10);
        require(accepted_count == 7, "session restart count wrong");
        cases = cases + 1;

        // Link loss cancels queued output and output commands; then reconnect.
        send_raw(commands[13]);
        link_up = 0;
        cycle;
        require(!tx_valid && !session_active && !led_requested && !rx_ready, "link loss unsafe");
        link_up = 1;
        reset_core;
        transact(14,11);
        transact(15,12);
        send_raw(commands[16]);
        held = tx_payload;
        require(held === replies[13], "PING before reset wrong");
        reset_core;
        require(accepted_count == 0 && rejected_count == 0, "reset did not clear counters");
        transact(14,11);
        transact(15,12);
        transact(16,13);
        transact(17,14);
        transact(18,15);
        require(accepted_count == 4, "sequence wrap was incorrectly accepted");
        cases = cases + 1;

        // An accepted output and a new input may share the same clock.
        send_raw(commands[18]);
        require(tx_payload === replies[15], "queued stale reply wrong");
        tx_ready = 1;
        #1;
        require(rx_ready, "ready not asserted for simultaneous dequeue/enqueue");
        rx_valid = 1;
        rx_payload = commands[18];
        cycle;
        rx_valid = 0;
        tx_ready = 0;
        receive_reply(15);
        cases = cases + 1;
        $display("S5_RESULT cases=%0d errors=0", cases);
        $finish;
    end
    initial begin
        #200000;
        $fatal(1, "simulation watchdog timeout");
    end
endmodule
