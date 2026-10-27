`timescale 1ns/1ps

module s3a_wr_completion_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg rd_cmd_en = 0;
    reg [31:0] rd_cmd_len = 80;
    reg read_en = 0;
    reg rd_done_p = 0;
    wire rd_cmd_done;
    wire rd_cmd_ready;

    integer checks = 0;
    integer commands = 0;
    integer completions = 0;
    integer returns = 0;
    integer cases = 0;
    integer active_returns = 0;
    integer active_length = 0;
    integer expected_done = 0;
    integer log_file;
    reg previous_command = 0;
    reg active = 0;
    reg [15:0] random_state = 16'h5a17;

    wr_cmd_trans #(.MEM_DQ_WIDTH(32)) dut (
        .clk(clk), .rstn(rstn),
        .wr_cmd_en(1'b0), .wr_cmd_addr(28'd0), .wr_cmd_len(32'd80),
        .wr_cmd_ready(), .wr_cmd_done(), .wr_bac(1'b0),
        .wr_ctrl_data(256'd0), .wr_data_re(), .wr_en(), .wr_addr(),
        .wr_id(), .wr_len(), .wr_data_en(), .wr_data(),
        .wr_ready(1'b0), .wr_done(1'b0),
        .rd_cmd_en(rd_cmd_en), .rd_cmd_addr(28'h400000),
        .rd_cmd_len(rd_cmd_len), .rd_cmd_ready(rd_cmd_ready),
        .rd_cmd_done(rd_cmd_done), .read_en(read_en),
        .rd_en(), .rd_addr(), .rd_id(), .rd_len(),
        .rd_done_p(rd_done_p)
    );

    // Compare after NBA updates against accepted returns, not DUT internals.
    always @(posedge clk) begin
        expected_done = 0;
        if (!rstn) begin
            active = 0;
            active_returns = 0;
            active_length = 0;
        end else if (rd_cmd_en && !previous_command) begin
            if (active)
                $fatal(1, "Command overlapped an unfinished command");
            active = 1;
            active_returns = 0;
            active_length = rd_cmd_len;
            commands = commands + 1;
        end else if (read_en) begin
            if (!active)
                $fatal(1, "Return without an active command");
            returns = returns + 1;
            active_returns = active_returns + 1;
            if (active_returns == active_length) begin
                expected_done = 1;
                active = 0;
            end
        end
        previous_command = rd_cmd_en;
        #2;
        checks = checks + 1;
        if (rd_cmd_done !== (expected_done != 0))
            $fatal(1, "Completion mismatch at cycle %0d: expected=%0d actual=%b",
                   checks, expected_done, rd_cmd_done);
        if (rd_cmd_done)
            completions = completions + 1;
    end

    task idle_cycles(input integer count);
        begin
            read_en = 0;
            rd_done_p = 0;
            repeat (count) @(negedge clk);
        end
    endtask

    task reset_dut;
        begin
            rstn = 0;
            rd_cmd_en = 0;
            idle_cycles(4);
            rstn = 1;
            idle_cycles(4);
            if (rd_cmd_ready !== 1'b1)
                $fatal(1, "Read command not ready after reset");
        end
    endtask

    task start_command(input integer length);
        begin
            if (rd_cmd_ready !== 1'b1)
                $fatal(1, "Read command not ready before command");
            rd_cmd_len = length;
            rd_cmd_en = 1;
            @(negedge clk);
            rd_cmd_en = 0;
            idle_cycles(6);
        end
    endtask

    task send_beat(input integer index, input integer length);
        begin
            read_en = 1;
            rd_done_p = ((index + 1) % 16 == 0) || (index + 1 == length);
            @(negedge clk);
            read_en = 0;
            rd_done_p = 0;
        end
    endtask

    task run_command(input integer length, input integer pattern);
        integer beat;
        integer gap;
        integer before_returns;
        integer before_completions;
        begin
            before_returns = returns;
            before_completions = completions;
            start_command(length);
            for (beat = 0; beat < length; beat = beat + 1) begin
                gap = 0;
                case (pattern)
                    1: gap = 2;
                    2: if (beat == length - 1) gap = 17;
                    3: begin
                        random_state = {random_state[14:0],
                            random_state[15] ^ random_state[13] ^
                            random_state[12] ^ random_state[10]};
                        gap = random_state % 8;
                    end
                    4: if (beat == length - 1) gap = 200;
                endcase
                idle_cycles(gap);
                send_beat(beat, length);
            end
            idle_cycles(12);
            if (returns - before_returns != length ||
                completions - before_completions != 1 ||
                rd_cmd_ready !== 1'b1)
                $fatal(1, "Command result mismatch");
            cases = cases + 1;
            $fdisplay(log_file, "%0d,command,%0d,%0d,%0d,%0d",
                      cases, length, pattern, returns - before_returns,
                      completions - before_completions);
        end
    endtask

    task abort_command(input integer prefix);
        integer beat;
        integer before_completions;
        begin
            before_completions = completions;
            start_command(80);
            for (beat = 0; beat < prefix; beat = beat + 1) begin
                send_beat(beat, 80);
                idle_cycles(2);
            end
            idle_cycles(20);
            reset_dut;
            idle_cycles(12);
            if (completions != before_completions)
                $fatal(1, "Aborted command generated completion");
            cases = cases + 1;
            $fdisplay(log_file, "%0d,reset_abort,80,-1,%0d,0", cases, prefix);
            run_command(80, 3);
        end
    endtask

    initial begin
        log_file = $fopen("cases.csv", "w");
        if (!log_file)
            $fatal(1, "Cannot create case log");
        $fdisplay(log_file, "case,type,length,pattern,returns,completions");
        @(negedge clk);
        reset_dut;
        run_command(80, 0);
        run_command(80, 1);
        run_command(80, 2);
        run_command(80, 3);
        run_command(80, 4);
        run_command(16, 0);
        run_command(32, 3);
        run_command(128, 3);
        run_command(80, 0);
        run_command(80, 0);
        abort_command(0);
        abort_command(37);
        abort_command(79);
        $fclose(log_file);
        $display("S3A_RESULT cases=%0d commands=%0d returns=%0d completions=%0d checks=%0d errors=0",
                 cases, commands, returns, completions, checks);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Regression timed out");
    end
endmodule
