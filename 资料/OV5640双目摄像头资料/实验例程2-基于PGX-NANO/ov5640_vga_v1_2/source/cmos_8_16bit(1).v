`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: Will
// 
// Create Date: 2023-03-17  
// Design Name:  
// Module Name: 
// Project Name: 
// Target Devices: Pango
// Tool Versions: 
// Description: 
//      
// Dependencies: 
// 
// Revision:
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
//将两个8bit数据拼成一个16bit RGB565数据；
`timescale 1ns/1ns

module cmos_8_16bit(
	input 				   pclk 		/*synthesis PAP_MARK_DEBUG="1"*/,   
	input 				   rst_n		,
	input				   de_i	        /*synthesis PAP_MARK_DEBUG="1"*/,
	input	[7:0]	       pdata_i	    /*synthesis PAP_MARK_DEBUG="1"*/,
    input                  vs_i         ,

    output                 pixel_clk    /*synthesis PAP_MARK_DEBUG="1"*/,
 	output	reg			   de_o         /*synthesis PAP_MARK_DEBUG="1"*/,
	output  reg [15:0]	   pdata_o        /*synthesis PAP_MARK_DEBUG="1"*/
); 
//test
reg [31:0]vs_i_h_cnt/*synthesis PAP_MARK_DEBUG="1"*/;
reg [31:0]vs_i_l_cnt/*synthesis PAP_MARK_DEBUG="1"*/;
reg [31:0]de_i_h_cnt/*synthesis PAP_MARK_DEBUG="1"*/;
reg [31:0]de_i_l_cnt/*synthesis PAP_MARK_DEBUG="1"*/;

reg [31:0]h_total/*synthesis PAP_MARK_DEBUG="1"*/;
reg [31:0]v_total/*synthesis PAP_MARK_DEBUG="1"*/;
reg vs_i_1d;
always@(posedge pclk)
begin
    vs_i_1d <= vs_i;
end
always@(posedge pclk)
begin
    if(!rst_n)
        h_total <= 32'd0;
    else if(vs_i && !vs_i_1d)
        h_total <= 32'd0;
    else if(h_total <32'd3200-1'b1)
        h_total <= h_total + 1'd1;
    else
        h_total <= 32'd0;
end
always@(posedge pclk)
begin
    if(!rst_n)
        v_total <= 32'd0;
    else if(vs_i && !vs_i_1d)
        v_total <= 32'd0;
    else if(h_total ==32'd3200-1'b1)
        v_total <= v_total + 1'd1;
    else
        v_total <= v_total;
end


always@(posedge pclk)
begin
    if(!rst_n)
        vs_i_h_cnt<=32'd0;
    else if(vs_i)
        vs_i_h_cnt<=vs_i_h_cnt + 1'd1;
    else
        vs_i_h_cnt<=32'd0;
end
always@(posedge pclk)
begin
    if(!rst_n)
        vs_i_l_cnt<=32'd0;
    else if(!vs_i)
        vs_i_l_cnt<=vs_i_l_cnt + 1'd1;
    else
        vs_i_l_cnt<=32'd0;
end
always@(posedge pclk)
begin
    if(!rst_n)
        de_i_h_cnt<=32'd0;
    else if(de_i)
        de_i_h_cnt<=de_i_h_cnt + 1'd1;
    else
        de_i_h_cnt<=32'd0;
end
always@(posedge pclk)
begin
    if(!rst_n)
        de_i_l_cnt<=32'd0;
    else if(!de_i)
        de_i_l_cnt<=de_i_l_cnt + 1'd1;
    else
        de_i_l_cnt<=32'd0;
end

reg			de_out1          ;
reg [15:0]	pdata_out1       ;
reg			de_out2          ;
reg [15:0]	pdata_out2       ;    
reg [1:0]   cnt             ;
wire        pclk_IOCLKBUF   ;
reg         vs_i_reg        ;
reg         enble           ;
reg [7:0] pdata_i_reg;
reg de_i_r,de_i_r1;
reg			de_out3          ;
reg [15:0]	pdata_out3       ;  
always @(posedge pclk)begin
       vs_i_reg <= vs_i ;
end
    always@(posedge pclk)
        begin
            if(!rst_n)
                enble <= 1'b0;
            else if(!vs_i_reg&&vs_i)
                enble <= 1'b1;
            else
                enble <= enble;
        end
/*
GTP_IOCLKBUF #(
    .GATE_EN("FALSE")//
) u_GTP_IOCLKBUF (
    .CLKOUT(pclk_IOCLKBUF),// OUTPUT  
    .CLKIN(pclk), // INPUT  
    .DI(enble)     // INPUT  
);
*/
/*GTP_IOCLKDIV #(
    .GRS_EN("TRUE"),
    .DIV_FACTOR("2")
) u_GTP_IOCLKDIV (
    .CLKDIVOUT(pixel_clk),// OUTPUT  
    .CLKIN(pclk_IOCLKBUF),    // INPUT  
    .RST_N(enble)     // INPUT  
);*/

//pix_div u_pix_div (
//  .clkout0(pixel_clk),            // output
//  .lock(    ),                  // output
//  .clkin1(pclk)              // input
////  .clkout0_syn(~enble)     // input
//);

    always@(posedge pclk)
        begin
            if(!rst_n)
                cnt <= 2'b0;
            else if(de_i == 1'b1)
                cnt <= cnt + 1'b1;
            else
                cnt <= 2'b0;
        end
    

    always@(posedge pclk)
        begin
            if(!rst_n)
                pdata_i_reg <= 8'b0;
            else if(de_i == 1'b1)
                pdata_i_reg <= pdata_i;
        end
    
    always@(posedge pclk)
        begin
            if(!rst_n)
                pdata_o <= 16'b0;
            else if(de_i == 1'b1 && cnt[0])
                pdata_o <= {pdata_i_reg,pdata_i};
        end
//reg [11:0]test_data;  
//    always@(posedge pclk)
//        begin
//            if(!rst_n || (vs_i && !vs_i_1d))
//                test_data <= 12'b0;
//            else if(de_i == 1'b1 && cnt[0])
//                test_data <= test_data+1'b1;
//            else
//                test_data <= test_data;
//        end
//assign pdata_o={test_data[11:8],1'b0,test_data[7:4],2'b0,test_data[3:0],1'b0};

   always@(posedge pclk)begin
        de_i_r <= de_i;
        de_i_r1 <= de_i_r;
   end
    always@(posedge pclk)
        begin
            if(!rst_n)
                de_o <= 1'b0;
            else if(de_i == 1'b1 && cnt[0])
                de_o <= 1'b1;
            else
                de_o <= 1'b0;
        end


 
//    always@(posedge pixel_clk)begin
//        de_out2<=de_out1;
//        de_out3<=de_out2;
//        de_o   <=de_out3;
//    end
//    always@(posedge pixel_clk)begin
//        pdata_out2<=pdata_out1;
//        pdata_out3<=pdata_out2;
//        pdata_o   <=pdata_out3;
//    end
endmodule