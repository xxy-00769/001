module image_send (
    input               clk         ,
    input               rst_n       ,
    input               initial_end ,
    input               sda_end     ,
    output              sda_start   ,
    output      [8:0]   sda_data         
);

reg flag /* synthesis PAP_MARK_DEBUG="true" */; 
reg [10:0]addr /* synthesis PAP_MARK_DEBUG="true" */;
reg [1:0]cnt /* synthesis PAP_MARK_DEBUG="true" */; // 0:column   1:page    2:data 
reg [7:0]cnt_c /* synthesis PAP_MARK_DEBUG="true" */;
reg [7:0]cnt_p /* synthesis PAP_MARK_DEBUG="true" */;
reg [15:0]addr_c[0:1] /* synthesis PAP_MARK_DEBUG="true" */;
reg [15:0]addr_p[0:1] /* synthesis PAP_MARK_DEBUG="true" */;
reg [8:0]data_sig /* synthesis PAP_MARK_DEBUG="true" */;
reg [15:0]data_sig_1 /* synthesis PAP_MARK_DEBUG="true" */;
reg start_reg /* synthesis PAP_MARK_DEBUG="true" */;
reg data_start /* synthesis PAP_MARK_DEBUG="true" */;
wire [15:0]rd_data /* synthesis PAP_MARK_DEBUG="true" */;

wire [7:0]order[0:3]/* synthesis PAP_MARK_DEBUG="true" */;

assign order[0] = 8'h2A ;
assign order[1] = 8'h2B ;
assign order[2] = 8'h2C ;
assign order[3] = 8'h00 ;

reg [11:0]state /* synthesis PAP_MARK_DEBUG="true" */;

parameter  IDLE                 = 12'b000_000_000_001; 
parameter  state_command        = 12'b000_000_000_010; //send instruction
parameter  state_command_wait   = 12'b000_000_000_100; //wait for sending to complete 
parameter  state_addr           = 12'b000_000_001_000; //send addr
parameter  state_data           = 12'b000_000_010_000; //send data
parameter  state_send_h         = 12'b000_000_100_000;
parameter  state_send_hwait     = 12'b000_001_000_000;
parameter  state_send_l         = 12'b000_010_000_000;
parameter  state_send_lwait     = 12'b000_100_000_000;
parameter  state_arb            = 12'b001_000_000_000; 
parameter  state_wait           = 12'b010_000_000_000; 
parameter  state_end            = 12'b100_000_000_000;

//////////////////////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n) begin 
        state <= IDLE ;
        cnt <= 2'b0 ;
        addr <= 11'b0 ;
        flag <= 1'b0 ;
    end 
    else begin
        case (state)
            IDLE                : begin
                if (initial_end)
                    state <= state_command ;
                else 
                    state <= IDLE       ; 
            end
            state_command       : begin
                    state <= state_command_wait ;
            end
            state_command_wait  : begin 
                if ((sda_end)&&(cnt <= 2'b1 ))
                    state <= state_addr ;
                else if ((sda_end)&&(cnt > 2'b1 ))
                    state <= state_data ;
                else 
                    state <= state_command_wait ;
            end 
            state_addr : begin
                    state <= state_send_h ; 
            end
            state_data : begin
                    state <= state_send_h ;
            end
            state_send_h : begin
                    state <= state_send_hwait ; 
            end
            state_send_hwait : begin
                if (sda_end)
                    state <= state_send_l ;
                else 
                    state <= state_send_hwait ;        
            end
            state_send_l : begin
                    state <= state_send_lwait ; 
            end
            state_send_lwait : begin
                if (sda_end)
                    state <= state_arb ;
                else 
                    state <= state_send_lwait ;
            end
            state_arb : begin
                if ((cnt <= 2'b1 )&&(~flag))begin
                    state <= state_addr ;
                    cnt   <= cnt ;
                    addr  <= 11'd0 ;
                    flag  <= ~flag ;
                end 
                else if ((cnt <= 2'b1 )&&(flag))begin
                    state <= state_command ;
                    cnt   <= cnt + 1'b1 ;
                    addr  <= 11'd0 ;
                    flag  <= ~flag ;
                end 
                else if (addr >= 11'd1599)begin
                    state <= state_end ;
                    cnt   <= 2'b0 ;
                    addr  <= 11'd0 ;
                    flag  <= 1'b0 ;
                end
                else begin
                    state <= state_wait ;
                    cnt <= cnt ;
                    addr <= addr + 11'd1 ;
                    flag <= 1'b0 ;
                end
            end
            state_wait : begin
                    state <= state_data ;
            end
            state_end : begin
                    state <= IDLE ; 
            end
            default : begin
                    state <= IDLE ; 
                    cnt <= 2'b0 ;
                    addr <= 11'b0 ;
                    flag <= 1'b0 ;
            end
        endcase
    end
end

////////////////////////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n) begin
        cnt_p <= 8'd0 ;
        cnt_c <= 8'd0 ;
    end
    else if (state == state_end)begin
        if ((cnt_p >= 8'd7)&&(cnt_c >= 8'd5))begin
            cnt_p <= 8'd0 ;
            cnt_c <= 8'd0 ;
        end
        else if (cnt_p >= 8'd7)begin
            cnt_p <= 8'd0 ;
            cnt_c <= cnt_c + 8'd1 ;
        end
        else begin
            cnt_p <= cnt_p + 8'd1 ;
            cnt_c <= cnt_c ;
        end
    end
end

/////////////////////////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n)begin
        addr_c[0]   <= 16'd0 ;
        addr_c[1]   <= 16'd0 ;
        addr_p[0]   <= 16'd0 ;
        addr_p[1]   <= 16'd0 ;
    end 
    else if (state == state_end) begin
        addr_c[0]   <=  8'd40 * cnt_c ;
        addr_c[1]   <= (8'd40 * cnt_c) + 16'd39 ;
        addr_p[0]   <=  8'd40 * cnt_p ;
        addr_p[1]   <= (8'd40 * cnt_p) + 16'd39 ;
    end
    else begin
        addr_c[0]   <= addr_c[0]    ;
        addr_c[1]   <= addr_c[1]    ;
        addr_p[0]   <= addr_p[0]    ;
        addr_p[1]   <= addr_p[1]    ;
    end
end

//////////////////////////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n)
        data_sig_1 <= 16'd0 ;
    else if ((state == state_addr)&&(cnt == 2'b0))
        data_sig_1 <= addr_p[flag] ;
    else if ((state == state_addr)&&(cnt == 2'b1))
        data_sig_1 <= addr_c[flag] ;
    else if (state == state_data)
        data_sig_1 <= rd_data      ;
    else 
        data_sig_1 <= data_sig_1   ;
end

always @(posedge clk ) begin
    if (~rst_n)
        data_sig <= 9'd0 ;
    else if (state == state_command)
        data_sig <= {1'b0 ,order[cnt] };
    else if (state == state_send_h)
        data_sig <= {1'b1 ,data_sig_1[15:8]};
    else if (state == state_send_l)
        data_sig <= {1'b1 ,data_sig_1[7:0]};
    else 
        data_sig <= data_sig ;
end

always @(posedge clk ) begin
    if (~rst_n)
        start_reg <= 1'b0 ;
    else if ((state == state_command)||(state == state_send_h)||(state == state_send_l))
        start_reg <= 1'b1 ;
    else 
        start_reg <= 1'b0 ;
end

assign sda_data = data_sig ;
assign sda_start = start_reg ;

rom_image image_1600x16 (
  .addr         (addr           ),              // input [10:0]
  .clk          (clk            ),              // input
  .rst          (~rst_n         ),              // input
  .rd_data      (rd_data        )               // output [15:0]
);


endmodule