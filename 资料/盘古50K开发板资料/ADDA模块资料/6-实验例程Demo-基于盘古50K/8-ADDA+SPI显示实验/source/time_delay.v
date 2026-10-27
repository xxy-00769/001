module time_delay (
    input       clk ,//5MHz
    input       rst_n ,
    input       delay_start ,
    input [31:0]delay_parameter ,
    output reg  delay_end 
);

reg [31:0]cnt_delay ;
reg delay_flag ;

always @(posedge clk ) begin
    if (~rst_n)
        cnt_delay <= 32'd0 ;
    else if (cnt_delay >= delay_parameter)
        cnt_delay <= 32'd0 ;
    else if (delay_flag)
        cnt_delay <= cnt_delay + 32'b1 ;
    else 
        cnt_delay <= 32'd0 ; 
end

always @(posedge clk ) begin
    if (~rst_n)
        delay_flag <= 1'b0 ;
    else if (cnt_delay >= delay_parameter)
        delay_flag <= 1'b0 ;
    else if (delay_start == 1'b1)
        delay_flag <= 1'b1 ;
    else 
        delay_flag <= delay_flag ;
end

always @(posedge clk ) begin
    if (~rst_n)
        delay_end <= 1'b0 ;
    else if (cnt_delay >= delay_parameter)
        delay_end <= 1'b1 ;
    else 
        delay_end <= 1'b0 ;
end


endmodule