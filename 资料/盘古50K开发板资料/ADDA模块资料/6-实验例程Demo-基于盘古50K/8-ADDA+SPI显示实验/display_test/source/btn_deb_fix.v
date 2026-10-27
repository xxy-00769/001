`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Myminieye
// Engineer: Mill
// 
// Create Date: 2020-06-19 20:31  
// Design Name:  
// Module Name:  btn_deb_fix ;
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
//      
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`define UD #1
module btn_deb_fix#(
    parameter        BTN_WIDTH = 4'd8,
    parameter        BTN_DELAY = 20'h7_ffff
)
(
    input                      clk,  //
    input      [BTN_WIDTH-1:0] btn_in,
    
    output reg [BTN_WIDTH-1:0] btn_deb_fix
);

reg [BTN_WIDTH-1:0] btn_flag ;
reg [BTN_WIDTH-1:0] btn_deb_fix_reg ;

    //16'h3ad43;
    reg [19:0]          cnt[BTN_WIDTH-1:0];
    reg [BTN_WIDTH-1:0] flag;
   
    reg [BTN_WIDTH-1:0] btn_in_reg;

    always @(posedge clk)
    begin
    	btn_in_reg <= `UD btn_in;
    end 

    genvar i;
    generate
        for(i=0;i<BTN_WIDTH;i=i+1)
        begin
            always @(posedge clk)
            begin
            	if (btn_in_reg[i] ^ btn_in[i]) //ȡ�������ؿ�ʼ���������ʶ
            		flag[i] <= `UD 1'b1;
            	else if (cnt[i]==BTN_DELAY)    //����10ms-20ms�����
            		flag[i] <= `UD 1'b0;
                else
                    flag[i] <= `UD flag[i];
            end 
            
            always @(posedge clk)
            begin
            	if(cnt[i]==BTN_DELAY)       //����10ms-20msʱ����
            		cnt[i] <= `UD 20'd0;
            	else if(flag[i])            //����������Чʱ����
            		cnt[i] <= `UD cnt[i] + 1'b1;
            	else                        //�Ƕ������䱣��0
            		cnt[i] <= `UD 20'd0;
            end 

            always @(posedge clk)
            begin
            	if(flag[i])                 //�������䣬�����������
            		btn_deb_fix[i] <= `UD btn_deb_fix[i];
            	else                        //�Ƕ������䣬����״̬���ݵ��������
            		btn_deb_fix[i] <= `UD btn_in[i];
            end 
         
            always @(posedge clk ) begin
                btn_deb_fix_reg[i] <= btn_deb_fix[i] ;
            end

            always @(posedge clk ) begin
                if ((btn_deb_fix_reg[i])&&(~btn_deb_fix[i]))
                    btn_flag[i] <= 1'b1 ;
                else 
                    btn_flag[i] <= 1'b0 ;
            end


        end 
    endgenerate

  

endmodule
