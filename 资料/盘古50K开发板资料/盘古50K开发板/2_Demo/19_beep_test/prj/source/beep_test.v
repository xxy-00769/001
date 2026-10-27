`timescale 1ns / 1ps
`define UD #1
`define LOW
module beep_test(
   input  wire clk ,
   input  wire rst_n ,
   input  [6:0]key ,
   output reg  beep 
   );

//////////////////////////////////////////////////////////////
//音符	低 1Do  低 2Re  低 3Mi  低 4Fa  低 5So  低 6La  低 7Si
//频率(Hz)262     294     330     349     392     440    494
//	
//音符	中 1Do  中 2Re  中 3Mi  中 4Fa  中 5So  中 6La  中 7Si
//频率(Hz)523     587     659     698     784     880    988
//	
//音符	高 1Do  高 2Re  高 3Mi  高 4Fa  高 5So  高 6La  高 7Si
//频率(Hz)1047    1175    1319    1397    1568    1760   1967
/////////////////////////////////////////////////////////////
`ifdef LOW
parameter VOICE_DO=262;
parameter VOICE_RE=294;
parameter VOICE_MI=330;
parameter VOICE_FA=349;
parameter VOICE_SO=392;
parameter VOICE_LA=440;
parameter VOICE_SI=494;
`elsif MID
parameter VOICE_DO=523;
parameter VOICE_RE=587;
parameter VOICE_MI=659;
parameter VOICE_FA=698;
parameter VOICE_SO=784;
parameter VOICE_LA=880;
parameter VOICE_SI=988;
`elsif HIGH
parameter VOICE_DO=1047;
parameter VOICE_RE=1175;
parameter VOICE_MI=1319;
parameter VOICE_FA=1397;
parameter VOICE_SO=1568;
parameter VOICE_LA=1760;
parameter VOICE_SI=1967;
`endif
parameter CLK_FRE = 26'd50_000_000 ;

wire [6:0]key_deb ;
btn_deb#(
   .BTN_WIDTH (4'd7),
   .BTN_DELAY (20'hF423F)
)btn_deb1
(
   .clk               (clk)        ,  
   .btn_in            (key)        ,
   
   .btn_deb           (key_deb)
);

reg [25:0]cnt_voice;
always @(posedge clk ) 
begin
    if(!rst_n)
        cnt_voice <= 26'd0;
    else if(!key_deb[0] && cnt_voice < CLK_FRE/VOICE_DO/2) 
        cnt_voice <= cnt_voice +1'b1;
    else if(!key_deb[1] && cnt_voice < CLK_FRE/VOICE_RE/2) 
        cnt_voice <= cnt_voice +1'b1;
    else if(!key_deb[2] && cnt_voice < CLK_FRE/VOICE_MI/2) 
        cnt_voice <= cnt_voice +1'b1;
    else if(!key_deb[3] && cnt_voice < CLK_FRE/VOICE_FA/2) 
        cnt_voice <= cnt_voice +1'b1;
    else if(!key_deb[4] && cnt_voice < CLK_FRE/VOICE_SO/2) 
        cnt_voice <= cnt_voice +1'b1;
    else if(!key_deb[5] && cnt_voice < CLK_FRE/VOICE_LA/2) 
        cnt_voice <= cnt_voice +1'b1;
    else if(!key_deb[6] && cnt_voice < CLK_FRE/VOICE_SI/2) 
        cnt_voice <= cnt_voice +1'b1;
    else 
        cnt_voice <= 26'd0;
end

always @(posedge clk ) 
begin
    if(!rst_n)
        beep <=1'b0;
    else if(key_deb==7'b111_1111)
        beep <=1'b0;
    else if(cnt_voice==26'd10)
        beep <= ~beep;
    else
        beep <= beep;
end



endmodule