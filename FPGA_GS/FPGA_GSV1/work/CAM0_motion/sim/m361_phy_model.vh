 reg slave_drive=0,slave_bit=1;assign mdio=slave_drive ? slave_bit:1'bz;
 integer bitno=0,transactions=0,writes=0;reg [63:0] wireword=0;
 reg [15:0] answer,delay_reg=16'h0123,phy_status=16'hac00;
 reg [15:0] page=0,ext=0;integer pa,ra;reg rdop;
 always @(posedge mdc) begin
  wireword={wireword[62:0],mdio};
  if(bitno==45) begin
   if(wireword[45:14]!==32'hffffffff || wireword[13:12]!==2'b01) $fatal(1,"MDIO framing");
   rdop=wireword[11:10]==2'b10;pa=wireword[9:5];ra=wireword[4:0];
   answer=16'hffff;
   if(pa==7) case(ra)
    2:answer=16'h001c;
    3:answer=16'hc915;
    28:answer=(page==7 && ext==16'ha4) ? delay_reg:16'hffff;
    17:answer=phy_status;
    31:answer=page;
   endcase
   // A responding but incorrect PHY ID must not be configured.
   if(pa==3) answer=16'h1234;
  end
  if(bitno==63) begin
   transactions++;
   if(!rdop && pa==7) begin
    writes++;
    case(ra)
     31:page=wireword[15:0];
     30:ext=wireword[15:0];
     28:begin
      if(page!=7 || ext!=16'ha4 || (wireword[15:0]&16'hc7ff)!=16'h0123) $fatal(1,"MDIO reserved bits/page");
      delay_reg=wireword[15:0];
     end
    endcase
   end
   bitno=0;
  end else bitno++;
 end
 always @(negedge mdc) begin
  slave_drive=rdop && (pa==7 || pa==3) && bitno>=47;
  slave_bit=bitno==47 ? 0:bitno>=48 ? answer[63-bitno]:1;
 end
