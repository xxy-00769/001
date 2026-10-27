module display_initial (
    input            clk                 ,
    input            rst_n               ,
    input            delay_end_0         ,
    input            delay_end_1         ,
    input            sda_end             ,
    output  reg      delay_start_0       ,
    output  reg      delay_start_1       ,
    output  reg      sda_start           ,
    output  reg [8:0]data_out            ,
    output  reg      reset               ,
    output  reg      initial_end 
);

reg [6:0]cnt_index /* synthesis PAP_MARK_DEBUG="true" */;
reg flag /* synthesis PAP_MARK_DEBUG="true" */;      
reg [11:0]index /* synthesis PAP_MARK_DEBUG="true" */;

/////////////////////////////////////////////////////////

reg [8:0] state ;

parameter IDLE                  =       9'b000_000_001 ;
parameter state_reset           =       9'b000_000_010 ;//send delay_start_0
parameter state_reset_delay     =       9'b000_000_100 ;//wait delay 255ms
parameter state_command         =       9'b000_001_000 ;//send delay_start_1
parameter state_command_delay   =       9'b000_010_000 ;//wait delay 120ms
parameter state_index_begin     =       9'b000_100_000 ;//send sda_start and data_out
parameter state_index_wait      =       9'b001_000_000 ;//wait for the data to finish sending
parameter state_index_arbi      =       9'b010_000_000 ;//check whather the index has been send 
parameter state_end             =       9'b100_000_000 ;//send initial end 



///////////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n) begin 
        state <= IDLE ;
        cnt_index <= 7'b0 ;
        flag <= 1'b0 ;
    end 
    else begin
        case (state)
            IDLE :                  begin
                    state <= state_reset    ; 
            end
            state_reset :           begin
                    state <= state_reset_delay ; 
            end
            state_reset_delay :     begin
                if ((delay_end_0)   &&  (~flag))begin
                    state <= state_reset ;
                    flag <= ~flag ;
                end 
                else if ((delay_end_0)  &&  (flag))begin
                    state <= state_command ;
                    flag <= ~flag ;
                end 
                else begin
                    state <= state_reset_delay ;
                    flag <= flag ;
                end 
            end
            state_command :         begin
                    state <= state_index_begin ;
            end
            state_command_delay :   begin
                if  ((delay_end_1)  &&  (~flag))begin
                    state <= state_command ;
                    flag <= ~flag ;
                end 
                else if ((delay_end_1)  &&  (flag))begin
                    state <= state_index_begin ;
                    flag <= ~flag ;
                end 
                else begin
                    state <= state_command_delay ;
                    flag <= flag ;
                end 
            end
            state_index_begin :     begin
                    state <= state_index_wait ;
            end
            state_index_wait :      begin
                if (sda_end)
                    state <= state_index_arbi ;
                else 
                    state <= state_index_wait ;
            end
            state_index_arbi :      begin
                if (cnt_index >= 7'd24) begin
                    state <= state_end ;
                    cnt_index <= 7'd0 ;
                end 
                else if (cnt_index <= 7'd1) begin 
                    state <= state_command_delay ; 
                    cnt_index <= cnt_index + 7'd1   ;
                end
                else begin 
                    state <= state_index_begin ; 
                    cnt_index <= cnt_index + 7'd1   ;
                end
            end
            state_end :             begin
                    state <= state_end ; 
            end
            default: begin state <= IDLE ;
                           cnt_index <= 7'b0 ;
                           flag <= flag ;
            end 
        endcase
    end
end

/////////////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n)
        delay_start_0 <= 1'b0 ;
    else if (state == state_reset)
        delay_start_0 <= 1'b1 ;
    else 
        delay_start_0 <= 1'b0 ;
end

always @(posedge clk ) begin
    if (~rst_n)
        delay_start_1 <= 1'b0 ;
    else if ((state == state_index_arbi)&&(cnt_index <= 7'd1))
        delay_start_1 <= 1'b1 ;
    else 
        delay_start_1 <= 1'b0 ;
end

//////////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n)
        reset <= 1'b0 ;
    else if (state == state_reset)
        reset <= flag ;
    else 
        reset <= reset ;
end

//////////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n)
        sda_start <= 1'b0 ;
    else if (state == state_index_begin)
        sda_start <= 1'b1 ;
    else 
        sda_start <= 1'b0 ;
end

always @(posedge clk ) begin
    if (~rst_n)
        data_out <= 9'd0 ;
    else if (state == state_index_begin)
        data_out <= index[8:0];
    else 
        data_out <= data_out ;
end

///////////////////////////////////////////////////////

always @(posedge clk ) begin
    if (~rst_n)
        initial_end <= 1'b0 ;
    else if (state == state_end)
        initial_end <= 1'b1 ;
    else 
        initial_end <= 1'b0 ;
end

///////////////////////////////////////////////////////

always @(*) begin
    case (cnt_index)
        0    :index <= 12'h0_AE ;
        1    :index <= 12'h0_D5 ;
        2    :index <= 12'h0_80 ;
        3    :index <= 12'h0_A8 ;
        4    :index <= 12'h0_3F ;
        5    :index <= 12'h0_D3 ;
        6    :index <= 12'h0_00 ;
        7    :index <= 12'h0_40 ;
        8    :index <= 12'h0_8D ;
        9    :index <= 12'h0_14 ;
        10   :index <= 12'h0_20 ;
        11   :index <= 12'h0_02 ;
        12   :index <= 12'h0_A1 ;
        13   :index <= 12'h0_C8 ;
        14   :index <= 12'h0_DA ;
        15   :index <= 12'h0_12 ;
        16   :index <= 12'h0_81 ;
        17   :index <= 12'h0_66 ;
        18   :index <= 12'h0_D9 ;
        19   :index <= 12'h0_F1 ;
        20   :index <= 12'h0_DB ;
        21   :index <= 12'h0_30 ;
        22   :index <= 12'h0_A4 ;
        23   :index <= 12'h0_A6 ;
        24   :index <= 12'h0_AF ;
        default: index <= 12'h0_af ;
    endcase
end

    
endmodule