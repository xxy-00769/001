module image_send (
    input               clk         ,
    input               rst_n       ,
    input               initial_end ,
    input               sda_end     ,
    output              sda_start   ,
    output      [8:0]   sda_data    ,

    input       [7:0]   adc_code

);

reg wr_en;
reg [6:0]addr /* synthesis PAP_MARK_DEBUG="true" */;
reg [1:0]cnt /* synthesis PAP_MARK_DEBUG="true" */; // 0:column   1:page    2:data 
reg [7:0]cnt_c /* synthesis PAP_MARK_DEBUG="true" */;
reg [2:0]cnt_p /* synthesis PAP_MARK_DEBUG="true" */;
reg [8:0]data_sig /* synthesis PAP_MARK_DEBUG="true" */;
reg start_reg /* synthesis PAP_MARK_DEBUG="true" */;
reg data_start /* synthesis PAP_MARK_DEBUG="true" */;
wire [63:0]rd_data /* synthesis PAP_MARK_DEBUG="true" */;
wire [7:0]order[0:2]/* synthesis PAP_MARK_DEBUG="true" */;

//assign order[0] = 8'h22 ;
//assign order[1] = 8'hb0 + cnt_p;
//assign order[2] = 8'h07 ;
assign order[0] = 8'hb0 + cnt_p;
assign order[1] = 8'h10 + ((cnt_c + 8'd2)>>4) ;
assign order[2] = 8'h00 + ((cnt_c + 8'd2)&8'h0f);

reg [6:0]state /* synthesis PAP_MARK_DEBUG="true" */;

parameter  idle                 = 7'b0_000_001; 
parameter  state_command        = 7'b0_000_010; //send instruction
parameter  state_command_wait   = 7'b0_000_100; //wait for sending to complete 
parameter  state_send           = 7'b0_001_000; //send addr
parameter  state_send_wait      = 7'b0_010_000;
parameter  state_wait           = 7'b0_100_000; //send data
parameter  state_end            = 7'b1_000_000;

//////////////////////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n)
        state <= idle ;
    else begin
        case (state)
            idle :begin
                if (initial_end )
                    state <=  state_command ;
                else 
                    state <= idle ;
            end
            state_command :begin
                    state <= state_command_wait ; 
            end
            state_command_wait :begin
                if ((cnt >= 2'd3)&&(sda_end))
                    state <= state_send ;
                else if (sda_end)
                    state <= state_command ;
                else 
                    state <= state_command_wait ;
            end
            state_send :begin
                    state <= state_send_wait ;
            end 
            state_send_wait :begin
                if ((cnt_c >= 8'd128)&&(sda_end))
                    state <= state_wait ;
                else if (sda_end)
                    state <= state_send ;
                else 
                    state <= state_send_wait ;
            end
            state_wait :begin
                if (cnt_p >= 3'd7 )
                    state <= state_end ;
                else 
                    state <= state_command ; 
            end
            state_end : begin
                if((wr_en && addr==7'd127))
                    state <= state_command;
                else
                    state <= state_end ; 
            end
            default:state <= idle ;
        endcase
    end
end

////////////////////////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n) begin
        cnt_p <= 3'd0 ;
        cnt_c <= 8'd0 ;
    end
    else if (!wr_en && state == state_send)begin
            cnt_p <= cnt_p ;
            cnt_c <= cnt_c + 8'd1 ;
    end 
    else if (state == state_wait)begin
            cnt_p <= cnt_p + 3'd1 ;
            cnt_c <= 8'd0 ;
    end
    else if (state == state_end)begin
            cnt_p <= 3'd0 ;
            cnt_c <= 8'd0 ;
    end
end

/////////////////////////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n)
        cnt <= 2'd0 ;
    else if (state ==state_command)
        cnt <= cnt + 2'd1 ;
    else if (state == state_send)
        cnt <= 2'd0 ;
end

//////////////////////////////////////////////////////////////////////////
	function [7:0] data_out ;
		input [7:0] data_in ; 
		integer i ; // 不能使用parameter类型，因为该类型在整个程序中不能修改
		begin 
			for (i = 0 ; i < 8 ; i = i + 1) 
				data_out[i] = data_in[7 - i] ;
		end 
	endfunction
always @(posedge clk ) begin
    if (~rst_n)
        data_sig <= 9'd0 ;
    else if (state == state_command)
        data_sig <= {1'b0 ,order[cnt] };
    else if (state == state_send)
    begin
        case(cnt_p)
            3'd0:    data_sig <= {1'b1 ,data_out(rd_data[63:56])};
            3'd1:    data_sig <= {1'b1 ,data_out(rd_data[55:48])};
            3'd2:    data_sig <= {1'b1 ,data_out(rd_data[47:40])};
            3'd3:    data_sig <= {1'b1 ,data_out(rd_data[39:32])};
            3'd4:    data_sig <= {1'b1 ,data_out(rd_data[31:24])};
            3'd5:    data_sig <= {1'b1 ,data_out(rd_data[23:16])};
            3'd6:    data_sig <= {1'b1 ,data_out(rd_data[15:8])};
            3'd7:    data_sig <= {1'b1 ,data_out(rd_data[7:0])};
        default:     data_sig <= 9'd0;
        endcase
    end
    else 
        data_sig <= data_sig ;
end

always @(posedge clk ) begin
    if (~rst_n)
        start_reg <= 1'b0 ;
    else if ((state == state_command)||(state == state_send))
        start_reg <= 1'b1 ;
    else 
        start_reg <= 1'b0 ;
end

assign sda_data = data_sig ;
assign sda_start = start_reg ;


///////////adc data
wire [5:0]bit_num;
wire [7:0]adc_code_1;
assign adc_code_1=adc_code+1'b1;
assign bit_num=adc_code_1[7:2]+1'b1;
reg [63:0]wr_data;

reg wr_flag;
reg [2:0]wr_cnt;
reg [6:0]a_addr;
reg rd_end;
always @(posedge clk ) begin
    wr_data <= 64'd0;
    if (~rst_n)
        wr_data <= 64'd0;
    else
    begin
        wr_data[bit_num] <= 1'b1;
    end
end
reg [31:0]time_cnt;
always @(posedge clk ) begin
    if (~rst_n)
        time_cnt <= 32'd0;
    else if(time_cnt==32'd25_000_000)
        time_cnt <= 32'd0;
    else
        time_cnt <= time_cnt + 1'd1;

end

always @(posedge clk ) begin
    if (~rst_n)
        wr_en<=1'd0;
    else if(time_cnt==32'd5_000_000)
        wr_en<=1'd1;
    else if((wr_en && addr==7'd127))// || (!wr_en && state == state_end)
        wr_en<=~wr_en;
    else
        wr_en<=wr_en;
end

//addr
always @(posedge clk ) begin
    if (~rst_n)
        addr <= 7'd0 ;
    else if(wr_en)
        addr <= addr + 1'd1 ;
    else if (state == state_send)
        addr <= addr + 1'd1 ;
    else if (state == state_end)
        addr <= 1'd0 ;
end



adc_ram the_instance_name (
  .wr_data(wr_data),    // input [63:0]
  .addr(addr),          // input [6:0]
  .wr_en(wr_en),        // input
  .clk(clk),            // input
  .rst(~rst_n),            // input
  .rd_data(rd_data)     // output [63:0]
);


/*
rom_image rom_image_display (
  .addr(addr),          // input [9:0]
  .clk(clk),            // input
  .rst(~rst_n),            // input
  .rd_data(rd_data)     // output [7:0]
);
*/
endmodule