`timescale 1ns/1ps
module sensor_colorbar_config_tb;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    wire done, sclk, config_clock;
    wire [8:0] index;
    tri1 sda;
    reg_config dut(.clk_25M(clk),.camera_rstn(rst_n),.initial_en(1'b1),
                   .reg_conf_done(done),.i2c_sclk(sclk),.i2c_sdat(sda),
                   .clock_20k(config_clock),.reg_index(index));
    wire ack_slot=dut.u1.cyc_count==12 || dut.u1.cyc_count==21 ||
                  dut.u1.cyc_count==30 || dut.u1.cyc_count==39;
    assign sda=ack_slot ? 1'b0 : 1'bz;
    reg [23:0] expected [0:356];
    reg [31:0] packet=0;
    integer bit_count=0, transactions=0;
    integer pass_index;

    // Accelerate only the clock divider; exercise the real config and I2C FSMs.
    initial begin
        force dut.clock_20k=clk;
        $readmemh("original_registers.hex",expected);
        repeat(4) @(negedge clk);
        rst_n=1;
        for(pass_index=0;pass_index<2;pass_index=pass_index+1) begin
            wait(done===1'b1);
            if(transactions!=358 || index!=358)
                $fatal(1,"Wrong transaction count %0d / index %0d",transactions,index);
            repeat(20) @(negedge clk);
            if(transactions!=358) $fatal(1,"Unexpected writes after completion");
            if(pass_index==0) begin
                rst_n=0;
                repeat(4) @(negedge clk);
                transactions=0; bit_count=0; packet=0;
                rst_n=1;
            end
        end
        $display("PASS: two resets; 357 original writes preserved; final 0x503D=0x80; 716 serialized transactions verified");
        $finish;
    end
    always @(posedge sclk) begin
        if(rst_n && dut.u1.cyc_count>=4 && dut.u1.cyc_count<=38 && !ack_slot) begin
            packet={packet[30:0],sda};
            bit_count=bit_count+1;
        end
    end
    always @(posedge dut.tr_end) begin
        if(rst_n) begin
            if(bit_count!=32) $fatal(1,"Wrong serial bit count %0d",bit_count);
            if(transactions<357) begin
                if(packet!=={8'h78,expected[transactions]})
                    $fatal(1,"Original write changed: index %0d actual %h expected %h",transactions,packet,{8'h78,expected[transactions]});
            end else if(transactions==357) begin
                if(packet!==32'h78503d80) $fatal(1,"Missing sensor test-pattern enable: %h",packet);
            end else $fatal(1,"Too many transactions");
            transactions=transactions+1;
            bit_count=0; packet=0;
        end
    end
    initial begin #1000000; $fatal(1,"Configuration timeout"); end
endmodule
