module dac_wave(
   input      clk,
   input      rst_n,
   input [1:0]key_cnt,
//   output     da_clk,
   output reg[7:0]da_data   
   );

//wire rst_n ;

reg   [10:0]rom_addr/* synthesis PAP_MARK_DEBUG="true" */ ;
wire  [7:0]sin_data_out ;
wire  [7:0]sawtooth_data_out ;
wire  [7:0]square_data_out ;
wire  [7:0]triangular_data_out ;


always @(posedge clk)
begin
    case(key_cnt)
        2'd0:    da_data <= sin_data_out  ;
        2'd1:    da_data <= sawtooth_data_out  ;
        2'd2:    da_data <= square_data_out  ;
        2'd3:    da_data <= triangular_data_out  ;
    default :    da_data <= sin_data_out  ;
    endcase

end

always @(negedge clk or negedge rst_n) begin
   if (!rst_n)
      rom_addr <= 11'd0 ;
   else if (rom_addr == 11'd1023)
      rom_addr <= 11'd0 ;
   else 
      rom_addr <= rom_addr + 11'd1     ; 
end

rom_sin_wave rom_sin_wave (
  .addr(rom_addr[9:0]),           // input [9:0]
  .clk(clk),            // input
  .rst(~rst_n),                // input
  .rd_data(sin_data_out)     // output [7:0]
);

rom_sawtooth_wave rom_sawtooth_wave (
  .addr(rom_addr[9:0]),           // input [9:0]
  .clk(clk),            // input
  .rst(~rst_n),                // input
  .rd_data(sawtooth_data_out)     // output [7:0]
);

rom_square_wave rom_square_wave (
  .addr(rom_addr[9:0]),           // input [9:0]
  .clk(clk),            // input
  .rst(~rst_n),                // input
  .rd_data(square_data_out)     // output [7:0]
);

rom_triangular_wave u_rom (
  .addr(rom_addr[9:0]),           // input [9:0]
  .clk(clk),            // input
  .rst(~rst_n),                // input
  .rd_data(triangular_data_out)     // output [7:0]
);



endmodule