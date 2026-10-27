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
                if (cnt_index >= 7'd68) begin
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
        0    :index <= 12'h0_01 ;
        1    :index <= 12'h0_11 ;
        2    :index <= 12'h0_3A ;
        3    :index <= 12'h1_05 ;
        4    :index <= 12'h0_C5 ;
        5    :index <= 12'h1_1A ;
        6    :index <= 12'h0_36 ;
        7    :index <= 12'h1_20 ;
        8    :index <= 12'h0_B2 ;
        9    :index <= 12'h1_05 ;
        10   :index <= 12'h1_05 ;
        11   :index <= 12'h1_00 ;
        12   :index <= 12'h1_33 ;
        13   :index <= 12'h1_33 ;
        14   :index <= 12'h0_B7 ;
        15   :index <= 12'h1_05 ;
        16   :index <= 12'h0_BB ;
        17   :index <= 12'h1_3F ;
        18   :index <= 12'h0_C0 ;
        19   :index <= 12'h1_2C ;
        20   :index <= 12'h0_C2 ;
        21   :index <= 12'h1_01 ;
        22   :index <= 12'h0_C3 ;
        23   :index <= 12'h1_0F ;
        24   :index <= 12'h0_C4 ;
        25   :index <= 12'h1_20 ;
        26   :index <= 12'h0_C6 ;
        27   :index <= 12'h1_01 ;
        28   :index <= 12'h0_D0 ;
        29   :index <= 12'h1_A4 ;
        30   :index <= 12'h1_A1 ;
        31   :index <= 12'h0_E8 ;
        32   :index <= 12'h1_03 ;
        33   :index <= 12'h0_E9 ;
        34   :index <= 12'h1_09 ;
        35   :index <= 12'h1_09 ;
        36   :index <= 12'h1_08 ;
        37   :index <= 12'h0_E0 ;
        38   :index <= 12'h1_D0 ;
        39   :index <= 12'h1_05 ;
        40   :index <= 12'h1_09 ;
        41   :index <= 12'h1_09 ;
        42   :index <= 12'h1_08 ;
        43   :index <= 12'h1_14 ;
        44   :index <= 12'h1_28 ;
        45   :index <= 12'h1_33 ;
        46   :index <= 12'h1_3F ;
        47   :index <= 12'h1_07 ;
        48   :index <= 12'h1_13 ;
        49   :index <= 12'h1_14 ;
        50   :index <= 12'h1_28 ;
        51   :index <= 12'h1_30 ;
        52   :index <= 12'h0_E1 ;
        53   :index <= 12'h1_D0 ;
        54   :index <= 12'h1_05 ;
        55   :index <= 12'h1_09 ;
        56   :index <= 12'h1_09 ;
        57   :index <= 12'h1_08 ;
        58   :index <= 12'h1_03 ;
        59   :index <= 12'h1_24 ;
        60   :index <= 12'h1_32 ;
        61   :index <= 12'h1_32 ;
        62   :index <= 12'h1_3B ;
        63   :index <= 12'h1_14 ;
        64   :index <= 12'h1_13 ;
        65   :index <= 12'h1_28 ;
        66   :index <= 12'h1_2F ;
        67   :index <= 12'h0_20 ;
        68   :index <= 12'h0_29 ;
        default: index <= 12'h0_3A ;
    endcase
end



    
endmodule