`timescale 1ns/1ps
module control_tb;
reg clk=0, rstn=0;
always #5 clk=~clk;
reg rd_cmd_en=0, read_en=0, rd_done_p=0;
wire rd_cmd_done, rd_cmd_ready, rd_en;
wire [27:0] rd_addr;
wire [3:0] rd_id, rd_len;
reg [31:0] rd_cmd_len=80;
integer premature=0, done_pulses=0, cycles=0, n;
reg last_read=0;
wr_cmd_trans #(.MEM_DQ_WIDTH(32)) dut(
    .clk(clk),.rstn(rstn),.wr_cmd_en(1'b0),.wr_cmd_addr(28'd0),.wr_cmd_len(32'd80),
    .wr_cmd_ready(),.wr_cmd_done(),.wr_bac(1'b0),.wr_ctrl_data(256'd0),.wr_data_re(),
    .wr_en(),.wr_addr(),.wr_id(),.wr_len(),.wr_data_en(),.wr_data(),
    .wr_ready(1'b0),.wr_done(1'b0),
    .rd_cmd_en(rd_cmd_en),.rd_cmd_addr(28'h400000),.rd_cmd_len(rd_cmd_len),
    .rd_cmd_ready(rd_cmd_ready),.rd_cmd_done(rd_cmd_done),.read_en(read_en),
    .rd_en(rd_en),.rd_addr(rd_addr),.rd_id(rd_id),.rd_len(rd_len),.rd_done_p(rd_done_p)
);
always @(posedge clk) begin
    last_read=read_en;
    #1;
    cycles=cycles+1;
    if(rd_cmd_done) begin
        done_pulses=done_pulses+1;
        if(!last_read) premature=premature+1;
    end
end
initial begin
    repeat(8) @(negedge clk); rstn=1;
    @(negedge clk); rd_cmd_en=1;
    @(negedge clk); rd_cmd_en=0;
    repeat(8) @(negedge clk);
    for(n=0;n<80;n=n+1) begin
        // Deliberately hold the penultimate count, then deliver the final beat.
        if(n==79) repeat(17) @(negedge clk);
        read_en=1; @(negedge clk); read_en=0;
        repeat(2) @(negedge clk);
    end
    repeat(5) @(negedge clk);
    $display("CONTROL_RESULT premature=%0d completion_cycles=%0d accepted_returns=80",premature,done_pulses);
    if(premature==0 && done_pulses==1) $display("PASS: final-return completion pulse");
    else $display("REJECT: premature/repeated line completion");
    $finish;
end
endmodule
