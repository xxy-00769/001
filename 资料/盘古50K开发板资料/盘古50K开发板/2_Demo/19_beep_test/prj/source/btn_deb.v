`timescale 1ns / 1ps
`define UD #1
module btn_deb#(
    parameter                  BTN_WIDTH = 4'd1,
    parameter                  BTN_DELAY = 20'hF423F
)
(
    input                      clk/* synthesis PAP_MARK_DEBUG="true" */,  
    input      [BTN_WIDTH-1:0] btn_in/* synthesis PAP_MARK_DEBUG="true" */,
    
    output reg [BTN_WIDTH-1:0] btn_deb/* synthesis PAP_MARK_DEBUG="true" */
);

    reg [19:0]          cnt[BTN_WIDTH-1:0];
    reg [BTN_WIDTH-1:0] flag/* synthesis PAP_MARK_DEBUG="true" */;
   
    reg [BTN_WIDTH-1:0] btn_in_reg/* synthesis PAP_MARK_DEBUG="true" */;
    always @(posedge clk)
    begin
      btn_in_reg <= `UD btn_in;
    end 

    genvar i;
    generate
    begin
        for(i=0;i<BTN_WIDTH;i=i+1)
        begin
            always @(posedge clk)
            begin
              if (btn_in_reg[i] ^ btn_in[i]) //The edge jitter of the key is used as the identifier
                flag[i] <= `UD 1'b1;
              else if (cnt[i]== BTN_DELAY)    //Last for 20ms and then return to zero
                flag[i] <= `UD 1'b0;
                else
                    flag[i] <= `UD flag[i];
            end 
            
            always @(posedge clk)
            begin
              if(cnt[i]== BTN_DELAY)       //Return to zero at 20ms
                cnt[i] <= `UD 20'd0;
              else if(flag[i])            //Count when the jitter interval is valid
                cnt[i] <= `UD cnt[i] + 1'b1;
              else                        //The non-jitter interval remains 0
                cnt[i] <= `UD 20'd0;
            end 

            always @(posedge clk)
            begin
              if(flag[i])                 //Jitter interval, anti-jitter output maintained
                btn_deb[i] <= `UD btn_deb[i];
              else                        //In the non-jitter interval, the key state is transferred to the anti-jitter output
                btn_deb[i] <= `UD btn_in[i];
            end 
        end
      end 
    endgenerate
endmodule