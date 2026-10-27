`timescale 1ns / 1ps
`define UD #1

module vga_test(
   input             pix_clk ,
   input             rstn ,
   output     reg    vs_out ,
   output     reg    hs_out ,

    output    reg    de,

   output     reg[3:0]r_out ,
   output     reg[3:0]g_out ,
   output     reg[3:0]b_out 
   );

parameter   X_WIDTH = 4'd12;
parameter   Y_WIDTH = 4'd12;    

reg    de_out ;

    parameter V_TOTAL = 12'd525;
    parameter V_TB = 12'd8;
    parameter V_BB = 12'd8;
    parameter V_FP = 12'd2;
    parameter V_BP = 12'd25;
    parameter V_SYNC = 12'd2;
    parameter V_ACT = 12'd480;
    parameter H_TOTAL = 12'd800;
    parameter H_LB = 12'd8;
    parameter H_RB = 12'd8;
    parameter H_FP = 12'd8;
    parameter H_BP = 12'd40;
    parameter H_SYNC = 12'd96;
    parameter H_ACT = 12'd640;
    parameter HV_OFFSET = 12'd0;

    localparam H_ACT_ARRAY_0 = H_ACT/8;
    localparam H_ACT_ARRAY_1 = 2* (H_ACT/8);
    localparam H_ACT_ARRAY_2 = 3* (H_ACT/8);
    localparam H_ACT_ARRAY_3 = 4* (H_ACT/8);
    localparam H_ACT_ARRAY_4 = 5* (H_ACT/8);
    localparam H_ACT_ARRAY_5 = 6* (H_ACT/8);
    localparam H_ACT_ARRAY_6 = 7* (H_ACT/8);
    localparam H_ACT_ARRAY_7 = 8* (H_ACT/8);
    
    reg [X_WIDTH-1:0]        h_count = 'd0;
    reg [Y_WIDTH-1:0]        v_count = 'd0;

    reg [X_WIDTH-1:0]        x_act = 'd0;
    reg [Y_WIDTH-1:0]        y_act = 'd0;
    
    reg hs ;
    reg vs ;
//    reg de ;



    /* horizontal counter */
    always @(posedge pix_clk)
    begin
        if (!rstn)
            h_count <= `UD 0;
        else
        begin
            if (h_count < H_TOTAL - 1)
                h_count <= `UD h_count + 1;
            else
                h_count <= `UD 0;
        end
    end
    
    /* vertical counter */
    always @(posedge pix_clk)
    begin
        if (!rstn)
            v_count <= `UD 0;
        else
        if (h_count == H_TOTAL - 1)
        begin
            if (v_count == V_TOTAL - 1)
                v_count <= `UD 0;
            else
                v_count <= `UD v_count + 1;
        end
    end
    
    always @(posedge pix_clk)
    begin
        if (!rstn)
            hs <= `UD 1'b0;
        else 
            hs <= `UD ((h_count < H_SYNC));
    end
    
    always @(posedge pix_clk)
    begin
        if (!rstn)
            vs <= `UD 4'b0;
        else 
        begin
            if (v_count == 0)
                vs <= `UD 1'b1;
            else if (v_count == V_SYNC)
                vs <= `UD 1'b0;
            else
                vs <= `UD vs;
        end
    end
    
    always @(posedge pix_clk)
    begin
        if (!rstn)
            de <= `UD 1'b0;
        else
            de <= (((v_count >= V_SYNC + V_BP + V_TB) && (v_count <= V_TOTAL - V_FP - V_BB - 1)) && 
                      ((h_count >= H_SYNC + H_BP + H_LB-1) && (h_count <= H_TOTAL - H_FP - H_RB - 2)));
    end
    
    // active pixels counter output
    always @(posedge pix_clk)
    begin
        if (!rstn)
            x_act <= `UD 'd0;
        else 
        begin
        /* X coords – for a backend pattern generator */
            if(h_count > (H_SYNC + H_BP + H_LB - 1'b1))
                x_act <= `UD (h_count - (H_SYNC + H_BP+ H_LB));
            else
                x_act <= `UD 'd0;
        end
    end
    
    always @(posedge pix_clk)
    begin
        if (!rstn)
            y_act <= `UD 'd0;
        else 
        begin
            /* Y coords – for a backend pattern generator */
            if(v_count > (V_SYNC + V_BP + V_TB - 1'b1))
                y_act <= `UD (v_count - (V_SYNC + V_BP + V_TB));
            else
                y_act <= `UD 'd0;
        end
    end

    always @(posedge pix_clk)
    begin
        vs_out <= `UD vs;
        hs_out <= `UD hs;
        de_out <= `UD de;
    end 

    always @(posedge pix_clk)
    begin
        if(!rstn)
        begin
            r_out <= 4'h0;
            g_out <= 4'h0;
            b_out <= 4'h0;
        end
        else if (de)
        begin
            if(x_act < H_ACT_ARRAY_0)
            begin
                r_out <= 4'hf;
                g_out <= 4'hf;
                b_out <= 4'hf;
            end
            else if(x_act < H_ACT_ARRAY_1)
            begin
                r_out <= 4'hf;
                g_out <= 4'hf;
                b_out <= 4'h0;
            end
            else if(x_act < H_ACT_ARRAY_2)
            begin
                r_out <= 4'h0;
                g_out <= 4'hf;
                b_out <= 4'hf;
            end
            else if(x_act < H_ACT_ARRAY_3)
            begin
                r_out <= 4'h0;
                g_out <= 4'hf;
                b_out <= 4'h0;
            end
            else if(x_act < H_ACT_ARRAY_4)
            begin
                r_out <= 4'hf;
                g_out <= 4'h0;
                b_out <= 4'hf;
            end
            else if(x_act < H_ACT_ARRAY_5)
            begin
                r_out <= 4'hf;
                g_out <= 4'h0;
                b_out <= 4'h0;
            end
            else if(x_act < H_ACT_ARRAY_6)
            begin
                r_out <= 4'h0;
                g_out <= 4'h0;
                b_out <= 4'hf;
            end
            else
            begin
                r_out <= 4'h5;
                g_out <= 4'h5;
                b_out <= 4'h5;
            end
        end
        else
        begin
            r_out <= 4'h0;
            g_out <= 4'h0;
            b_out <= 4'h0;
        end
    end

endmodule