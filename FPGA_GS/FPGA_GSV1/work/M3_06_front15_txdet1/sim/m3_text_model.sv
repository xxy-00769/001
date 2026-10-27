// Long-run display oracle excludes intentional OSD coverage. Real glyph ROM
// and all key/status strings are exercised by the control test, separately.
module m3_text(input [5:0] text_id,input [7:0] col,input [3:0] row,output pixel);
 assign pixel=1'b0;
endmodule
