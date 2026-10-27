`timescale 1ns/1ps
module m1_keys #(parameter DEBOUNCE_CYCLES=1000000)(
    input clk, rst_n, input [5:0] key_n,
    output reg [3:0] intent_led, output reg view_request,
    output reg [5:0] pressed,
    output reg hint_event,
    output reg [3:0] hint_code
);
    reg [5:0] sync1, sync2, stable;
    reg [19:0] count[0:5];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sync1<=6'b111111; sync2<=6'b111111; stable<=6'b111111;
            pressed<=0; intent_led<=4'b1000; view_request<=0;
            hint_event<=0; hint_code<=0;
            for(i=0;i<6;i=i+1) count[i]<=0;
        end else begin
            sync1<=key_n; sync2<=sync1; pressed<=0; hint_event<=0;
            for(i=0;i<6;i=i+1) begin
                if(sync2[i]==stable[i]) count[i]<=0;
                else if(count[i]==DEBOUNCE_CYCLES-1) begin
                    count[i]<=0; stable[i]<=sync2[i];
                    if(!sync2[i]) pressed[i]<=1;
                end else count[i]<=count[i]+1'b1;
            end
            // STOP also dominates while held, including staggered presses.
            if(pressed[3] || !stable[3]) intent_led<=4'b1000;
            else if(pressed[0]) intent_led<=4'b0001;
            else if(pressed[1]) intent_led<=4'b0010;
            else if(pressed[2]) intent_led<=4'b0100;
            if(pressed[4]) view_request<=~view_request;
            // One visible message per debounced event. Bit 3 indicates an
            // intent denied by held/simultaneously pressed STOP. The low bits
            // preserve the actual requested key number.
            if(|pressed) begin
                hint_event<=1;
                if(pressed[3]) hint_code<=4;
                else if(pressed[0]) hint_code<={(!stable[3]),3'd1};
                else if(pressed[1]) hint_code<={(!stable[3]),3'd2};
                else if(pressed[2]) hint_code<={(!stable[3]),3'd3};
                else if(pressed[4]) hint_code<=5;
                else hint_code<=6;
            end
        end
    end
endmodule
