module command_data_send (
    input           clk         ,
    input           rst_n       ,
    input           start       ,
    input           rs_ctrl     ,
    input   [7:0]   data_in     ,
    output          send_end    ,
    output          cs          ,
    output          rs          ,
    output          scl         ,
    output          sda         
);

reg [7:0]sda_data /* synthesis PAP_MARK_DEBUG="true" */;
reg rs_reg /* synthesis PAP_MARK_DEBUG="true" */;
reg [3:0]cnt /* synthesis PAP_MARK_DEBUG="true" */;
reg [4:0]state /* synthesis PAP_MARK_DEBUG="true" */;

wire sda_data_in /* synthesis PAP_MARK_DEBUG="true" */;
wire sda_data_out /* synthesis PAP_MARK_DEBUG="true" */;

parameter IDLE      = 5'b00001 ;
parameter CS_LOW    = 5'b00010 ;
parameter SDA_SEND  = 5'b00100 ;
parameter CS_HIGH   = 5'b01000 ;
parameter END_STATE = 5'b10000 ;

///////////////////////////进行锁存/////////////////////////

always @(posedge clk ) begin
    if (~rst_n)
        sda_data <= 8'd0 ;
    else if (start)
        sda_data <= data_in[7:0] ;
    else 
        sda_data <= sda_data ;
end

always @(posedge clk ) begin
    if (~rst_n)
        rs_reg <= 1'b1 ;
    else if (start)
        rs_reg <= rs_ctrl ;
    else 
        rs_reg <= rs_reg ;
end

///////////////////////////状态机////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n) begin
        state <= IDLE ;
        cnt <= 4'd0 ;
    end 
    else begin
        case (state)
            IDLE    :begin
                if (start)
                    state <= CS_LOW     ;
                else 
                    state <= IDLE       ; 
            end
            CS_LOW  :begin
                    state <= SDA_SEND   ; 
            end
            SDA_SEND:begin
                if (cnt >= 4'd7) begin
                    state <= CS_HIGH    ;
                    cnt <= 4'd0 ;
                end 
                else begin
                    state <= SDA_SEND   ;
                    cnt <= cnt + 1'b1   ;
                end
            end
            CS_HIGH :begin
                    state <= END_STATE  ; 
            end
            END_STATE:begin
                    state <= IDLE       ;
            end
            default:begin
                    state <= IDLE       ;
                    cnt   <= 4'd0       ; 
            end
        endcase
    end
end

/////////////////////输出赋值//////////////////////////////

assign rs = rs_reg ;
assign cs = ((state == CS_LOW)||(state == SDA_SEND)||(state == CS_HIGH))? 1'b0 : 1'b1 ;

assign scl = (state == SDA_SEND)? ~clk : 1'b1 ;
assign sda_data_out = (state == SDA_SEND)? sda_data[7-cnt] : 1'b1 ;

assign sda = (state == SDA_SEND)? sda_data_out : 1'b0 ;
assign sda_data_in = sda ;

assign send_end = (state == END_STATE)? 1'b1 : 1'b0 ;



endmodule