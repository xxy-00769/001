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
//camera�мĴ��������ó���
 module reg_config(     
		  input clk_25M,
		  input camera_rstn,
		  input initial_en,
		  output reg_conf_done,
		  output i2c_sclk,
		  inout i2c_sdat,
		  output reg clock_20k,
		  output reg [8:0]reg_index
	  );

     reg [15:0]clock_20k_cnt;
     reg [1:0]config_step;	  
     reg [31:0]i2c_data;
     reg [23:0]reg_data;
     reg start;
	 reg reg_conf_done_reg;
	  
     i2c_com u1(.clock_i2c(clock_20k),
               .camera_rstn(camera_rstn),
               .ack(ack),
               .i2c_data(i2c_data),
               .start(start),
               .tr_end(tr_end),
               .i2c_sclk(i2c_sclk),
               .i2c_sdat(i2c_sdat));

assign reg_conf_done=reg_conf_done_reg;
//����i2c����ʱ��-20khz    
always@(posedge clk_25M)   
begin
   if(!camera_rstn) begin
        clock_20k<=0;
        clock_20k_cnt<=0;
   end
   else if(clock_20k_cnt<1249)
      clock_20k_cnt<=clock_20k_cnt+1'b1;
   else begin
         clock_20k<=!clock_20k;
         clock_20k_cnt<=0;
   end
end

////iic�Ĵ������ù��̿���    
always@(posedge clock_20k)    
begin
   if(!camera_rstn) begin
       config_step<=0;
       start<=0;
       reg_index<=0;
		 reg_conf_done_reg<=0;
   end
   else begin
      if(reg_conf_done_reg==1'b0) begin          //���camera��ʼ��δ���
			  if(reg_index<357) begin               //���üĴ���
					 case(config_step)
					 0:begin
						i2c_data<={8'h78,reg_data};       //OV5640 IIC Device address is 0x78   
						start<=1;                         //i2cд��ʼ
						config_step<=1;                  
					 end
					 1:begin
						if(tr_end) begin                  //i2cд����               					
							 start<=0;
							 config_step<=2;
						end
					 end
					 2:begin
						  reg_index<=reg_index+1'b1;       //������һ���Ĵ���
						  config_step<=0;
					 end
					 endcase
				end
			 else 
				reg_conf_done_reg<=1'b1;                //OV5640�Ĵ�����ʼ�����
      end
   end
 end

		parameter total_h_pixel = 12'd1600   ;
		parameter total_v_pixel = 12'd1000  ;
		parameter cmos_h_pixel	= 12'd640   ;
		parameter cmos_v_pixel	= 12'd480	   ;


////iic��Ҫ���õļĴ���ֵ  			
always@(reg_index)   
 begin
    case(reg_index)
	 0    :reg_data   <={16'h300a,8'h0 } ;//      
	 1    :reg_data   <={16'h300b,8'h0 } ;//      
	 2    :reg_data   <={16'h3008,8'h82} ;//  
	 102  :reg_data   <={16'h3008,8'h02} ;//      
	 103  :reg_data   <={16'h3103,8'h02} ;//      
	 104  :reg_data   <=24'h3017ff ;//      
	 105  :reg_data   <=24'h3018ff ;//      
	// 106  :reg_data   <=24'h30341A ;//      
	 107  :reg_data  <={16'h3037,8'h13} ;//{16'h3037,8'h13}      
	 108  :reg_data  <={16'h3108,8'h01} ;//{16'h3108,8'h01}      
	 109  :reg_data  <={16'h3630,8'h36} ;//{16'h3630,8'h36}      
	 110  :reg_data  <={16'h3631,8'h0e} ;//{16'h3631,8'h0e}       
	 111  :reg_data  <={16'h3632,8'he2} ;//{16'h3632,8'he2}       
	 112  :reg_data  <={16'h3633,8'h12} ;//{16'h3633,8'h12}       
	 113  :reg_data  <={16'h3621,8'he0} ;//{16'h3621,8'he0}       
	 114  :reg_data  <={16'h3704,8'ha0} ;//{16'h3704,8'ha0}       
	 115  :reg_data  <={16'h3703,8'h5a} ;//{16'h3703,8'h5a}       
	 116  :reg_data  <={16'h3715,8'h78} ;//{16'h3715,8'h78}       
	 117  :reg_data  <={16'h3717,8'h01} ;// {16'h3717,8'h01}      
	 118  :reg_data  <={16'h370b,8'h60} ;// {16'h370b,8'h60}      
	 119  :reg_data  <={16'h3705,8'h1a} ;// {16'h3705,8'h1a}      
	 120  :reg_data  <={16'h3905,8'h02} ;// {16'h3905,8'h02}      
	 121  :reg_data  <={16'h3906,8'h10} ;// {16'h3906,8'h10}      
	 122  :reg_data  <={16'h3901,8'h0a} ;// {16'h3901,8'h0a}      
	 123  :reg_data  <={16'h3731,8'h12} ;// {16'h3731,8'h12}      
	 124  :reg_data  <={16'h3600,8'h08} ;// {16'h3600,8'h08}      
	 125  :reg_data  <={16'h3601,8'h33} ;// {16'h3601,8'h33}      
	 126  :reg_data  <={16'h302d,8'h60} ;// {16'h302d,8'h60}      
	 127  :reg_data  <={16'h3620,8'h52} ;// {16'h3620,8'h52}      
	 128  :reg_data  <={16'h371b,8'h20} ;// {16'h371b,8'h20}      
	 129  :reg_data  <={16'h471c,8'h50} ;// {16'h471c,8'h50}      
	 130  :reg_data  <={16'h3a13,8'h43} ;// {16'h3a13,8'h43}      
	 131  :reg_data  <={16'h3a18,8'h00} ;// {16'h3a18,8'h00}      
	 132  :reg_data  <={16'h3a19,8'hf8} ;// {16'h3a19,8'hf8}      
	 133  :reg_data  <={16'h3635,8'h13} ;// {16'h3635,8'h13}      
	 134  :reg_data  <={16'h3636,8'h03} ;// {16'h3636,8'h03}      
	 135  :reg_data  <={16'h3634,8'h40} ;// {16'h3634,8'h40}      
	 136  :reg_data  <={16'h3622,8'h01} ;///{16'h3622,8'h01}      
	 137  :reg_data  <={16'h3c01,8'h34} ;// {16'h3c01,8'h34}      
	 138  :reg_data  <={16'h3c04,8'h28} ;// {16'h3c04,8'h28}      
	 139  :reg_data  <={16'h3c05,8'h98} ;// {16'h3c05,8'h98}      
	 140  :reg_data  <={16'h3c06,8'h00} ;// {16'h3c06,8'h00}      
     141  :reg_data  <={16'h3c07,8'h08} ;//{16'h3c07,8'h08}       
	 142  :reg_data  <={16'h3c08,8'h00} ;//{16'h3c08,8'h00}       
	 143  :reg_data  <={16'h3c09,8'h1c} ;//{16'h3c09,8'h1c}       
	 144  :reg_data  <={16'h3c0a,8'h9c} ;//{16'h3c0a,8'h9c}       
	 145  :reg_data  <={16'h3c0b,8'h40} ;//{16'h3c0b,8'h40}       
	 146  :reg_data  <={16'h3810,8'h00} ;//{16'h3810,8'h00}       
	 147  :reg_data  <={16'h3811,8'h10} ;//{16'h3811,8'h10}       
	 148  :reg_data  <={16'h3812,8'h00} ;//{16'h3812,8'h00}       
	 149  :reg_data  <={16'h3708,8'h64} ;//{16'h3708,8'h64}       
	 150  :reg_data  <={16'h4001,8'h02} ;//{16'h4001,8'h02}       
	 151  :reg_data  <={16'h4005,8'h1a} ;//{16'h4005,8'h1a}       
	 152  :reg_data  <={16'h3000,8'h00} ;//{16'h3000,8'h00}       
	 153  :reg_data  <={16'h3004,8'hff} ;//{16'h3004,8'hff}       
	 154  :reg_data  <={16'h4300,8'h61} ;//{16'h4300,8'h61}       
	 155  :reg_data  <= {16'h501f,8'h01} ;//   {16'h501f,8'h01}     
	 156  :reg_data  <= {16'h440e,8'h00} ;//   {16'h440e,8'h00}     
	 157  :reg_data  <= {16'h5000,8'ha7} ;//   {16'h5000,8'ha7}     
	 158  :reg_data  <= {16'h3a0f,8'h30} ;//   {16'h3a0f,8'h30}     
	 159  :reg_data  <= {16'h3a10,8'h28} ;//   {16'h3a10,8'h28}   
	 160  :reg_data  <= {16'h3a1b,8'h30} ;//   {16'h3a1b,8'h30}     
	 161  :reg_data  <= {16'h3a1e,8'h26} ;//   {16'h3a1e,8'h26}     
	 162  :reg_data  <= {16'h3a11,8'h60} ;//   {16'h3a11,8'h60}     
	 163  :reg_data  <= {16'h3a1f,8'h14} ;//   {16'h3a1f,8'h14}     
	 164  :reg_data  <={16'h5800,8'h23} ;// {16'h5800,8'h23};       
	 165  :reg_data  <={16'h5801,8'h14} ;// {16'h5801,8'h14};      
	 166  :reg_data  <={16'h5802,8'h0f} ;// {16'h5802,8'h0f};      
	 167  :reg_data  <={16'h5803,8'h0f} ;// {16'h5803,8'h0f};      
	 168  :reg_data  <={16'h5804,8'h12} ;// {16'h5804,8'h12};      
	 169  :reg_data  <={16'h5805,8'h26} ;// {16'h5805,8'h26};      
	 170  :reg_data  <={16'h5806,8'h0c} ;// {16'h5806,8'h0c};      
	 171  :reg_data  <={16'h5807,8'h08} ;// {16'h5807,8'h08};      
	 172  :reg_data  <={16'h5808,8'h05} ;// {16'h5808,8'h05};      
	 173  :reg_data  <={16'h5809,8'h05} ;// {16'h5809,8'h05};      
	 174  :reg_data  <={16'h580a,8'h08} ;// {16'h580a,8'h08};      
	 175  :reg_data  <={16'h580b,8'h0d} ;// {16'h580b,8'h0d};      
	 176  :reg_data  <={16'h580c,8'h08} ;// {16'h580c,8'h08};      
	 177  :reg_data  <={16'h580d,8'h03} ;// {16'h580d,8'h03};      
	 178  :reg_data  <={16'h580e,8'h00} ;// {16'h580e,8'h00};      
	 179  :reg_data  <={16'h580f,8'h00} ;// {16'h580f,8'h00};      
	 180  :reg_data  <={16'h5810,8'h03} ;// {16'h5810,8'h03};      
	 181  :reg_data  <={16'h5811,8'h09} ;// {16'h5811,8'h09};      
	 182  :reg_data  <={16'h5812,8'h07} ;// {16'h5812,8'h07};      
	 183  :reg_data  <={16'h5813,8'h03} ;// {16'h5813,8'h03};      
	 184  :reg_data  <={16'h5814,8'h00} ;// {16'h5814,8'h00};      
	 185  :reg_data  <={16'h5815,8'h01} ;// {16'h5815,8'h01};      
	 186  :reg_data  <={16'h5816,8'h03} ;// {16'h5816,8'h03};      
	 187  :reg_data  <={16'h5817,8'h08} ;// {16'h5817,8'h08};      
	 188  :reg_data  <={16'h5818,8'h0d} ;// {16'h5818,8'h0d};      
	 189  :reg_data  <={16'h5819,8'h08} ;// {16'h5819,8'h08};      
	 190  :reg_data  <={16'h581a,8'h05} ;// {16'h581a,8'h05};      
	 191  :reg_data  <={16'h581b,8'h06} ;// {16'h581b,8'h06};      
	 192  :reg_data  <={16'h581c,8'h08} ;// {16'h581c,8'h08};      
	 193  :reg_data  <={16'h581d,8'h0e} ;// {16'h581d,8'h0e};      
	 194  :reg_data  <={16'h581e,8'h29} ;// {16'h581e,8'h29};      
	 195  :reg_data  <={16'h581f,8'h17} ;// {16'h581f,8'h17};      
	 196  :reg_data  <={16'h5820,8'h11} ;// {16'h5820,8'h11};      
	 197  :reg_data  <={16'h5821,8'h11} ;// {16'h5821,8'h11};      
	 198  :reg_data  <={16'h5822,8'h15} ;// {16'h5822,8'h15};      
	 199  :reg_data  <={16'h5823,8'h28} ;// {16'h5823,8'h28};      
	 200  :reg_data  <={16'h5824,8'h46} ;// {16'h5824,8'h46};      
	 201  :reg_data  <={16'h5825,8'h26} ;// {16'h5825,8'h26};      
	 202  :reg_data  <={16'h5826,8'h08} ;// {16'h5826,8'h08};      
	 203  :reg_data  <={16'h5827,8'h26} ;// {16'h5827,8'h26};      
	 204  :reg_data  <={16'h5828,8'h64} ;// {16'h5828,8'h64};      
	 205  :reg_data  <={16'h5829,8'h26} ;// {16'h5829,8'h26};      
	 206  :reg_data  <={16'h582a,8'h24} ;// {16'h582a,8'h24};      
	 207  :reg_data  <={16'h582b,8'h22} ;// {16'h582b,8'h22};      
	 208  :reg_data  <={16'h582c,8'h24} ;// {16'h582c,8'h24};      
	 209  :reg_data  <={16'h582d,8'h24} ;// {16'h582d,8'h24};      
	 210  :reg_data  <={16'h582e,8'h06} ;// {16'h582e,8'h06};      
	 211  :reg_data  <={16'h582f,8'h22} ;// {16'h582f,8'h22};      
	 212  :reg_data  <={16'h5830,8'h40} ;// {16'h5830,8'h40};      
	 213  :reg_data  <={16'h5831,8'h42} ;// {16'h5831,8'h42};      
	 214  :reg_data  <={16'h5832,8'h24} ;// {16'h5832,8'h24};      
	 215  :reg_data  <={16'h5833,8'h26} ;// {16'h5833,8'h26};      
	 216  :reg_data  <={16'h5834,8'h24} ;// {16'h5834,8'h24};      
	 217  :reg_data  <={16'h5835,8'h22} ;// {16'h5835,8'h22};      
	 218  :reg_data  <={16'h5836,8'h22} ;// {16'h5836,8'h22};      
	 219  :reg_data  <={16'h5837,8'h26} ;// {16'h5837,8'h26};      
	 220  :reg_data  <={16'h5838,8'h44} ;// {16'h5838,8'h44};      
	 221  :reg_data  <={16'h5839,8'h24} ;// {16'h5839,8'h24};      
	 222  :reg_data  <={16'h583a,8'h26} ;// {16'h583a,8'h26};      
	 223  :reg_data  <={16'h583b,8'h28} ;// {16'h583b,8'h28};      
	 224  :reg_data  <={16'h583c,8'h42} ;// {16'h583c,8'h42};      
	 225  :reg_data  <={16'h583d,8'hce} ;// {16'h583d,8'hce};      
	 226  :reg_data <={16'h5180,8'hff} ;//{16'h5180,8'hff}        
	 227  :reg_data <={16'h5181,8'hf2} ;//{16'h5181,8'hf2}        
	 228  :reg_data <={16'h5182,8'h00} ;//{16'h5182,8'h00}        
	 229  :reg_data <={16'h5183,8'h14} ;//{16'h5183,8'h14}        
	 230  :reg_data <={16'h5184,8'h25} ;//{16'h5184,8'h25}        
	 231  :reg_data <={16'h5185,8'h24} ;//{16'h5185,8'h24}        
	 232  :reg_data <={16'h5186,8'h09} ;//{16'h5186,8'h09}        
	 233  :reg_data <={16'h5187,8'h09} ;//{16'h5187,8'h09}        
	 234  :reg_data <={16'h5188,8'h09} ;//{16'h5188,8'h09}        
	 235  :reg_data <={16'h5189,8'h75} ;//{16'h5189,8'h75}        
	 236  :reg_data <={16'h518a,8'h54} ;//{16'h518a,8'h54}        
	 237  :reg_data <={16'h518b,8'he0} ;//{16'h518b,8'he0}        
	 238  :reg_data <={16'h518c,8'hb2} ;//{16'h518c,8'hb2}        
	 239  :reg_data <={16'h518d,8'h42} ;//{16'h518d,8'h42}        
	 240  :reg_data <={16'h518e,8'h3d} ;//{16'h518e,8'h3d}        
	 241  :reg_data <={16'h518f,8'h56} ;//{16'h518f,8'h56}        
	 242  :reg_data <={16'h5190,8'h46} ;//{16'h5190,8'h46}        
	 243  :reg_data <={16'h5191,8'hf8} ;//{16'h5191,8'hf8}        
	 244  :reg_data <={16'h5192,8'h04} ;//{16'h5192,8'h04}        
	 245  :reg_data <={16'h5193,8'h70} ;//{16'h5193,8'h70}        
	 246  :reg_data <={16'h5194,8'hf0} ;//{16'h5194,8'hf0}        
	 247  :reg_data <={16'h5195,8'hf0} ;//{16'h5195,8'hf0}        
	 248  :reg_data <={16'h5196,8'h03} ;//{16'h5196,8'h03}        
	 249  :reg_data <={16'h5197,8'h01} ;//{16'h5197,8'h01}        
	 250  :reg_data <={16'h5198,8'h04} ;//{16'h5198,8'h04}        
	 251  :reg_data <={16'h5199,8'h12} ;//{16'h5199,8'h12}        
	 252  :reg_data <={16'h519a,8'h04} ;//{16'h519a,8'h04}        
	 253  :reg_data <={16'h519b,8'h00} ;//{16'h519b,8'h00}        
	 254  :reg_data <={16'h519c,8'h06} ;//{16'h519c,8'h06}        
	 255  :reg_data <={16'h519d,8'h82} ;//{16'h519d,8'h82}        
	 256  :reg_data <={16'h519e,8'h38} ;//{16'h519e,8'h38}        
	 257  :reg_data <={16'h5480,8'h01};//{16'h5480,8'h01}     
	 258  :reg_data <={16'h5481,8'h08};//{16'h5481,8'h08}
	 259  :reg_data <={16'h5482,8'h14};//{16'h5482,8'h14}       
	 260  :reg_data <={16'h5483,8'h28};//{16'h5483,8'h28}       
	 261  :reg_data <={16'h5484,8'h51};//{16'h5484,8'h51}       
	 262  :reg_data <={16'h5485,8'h65};//{16'h5485,8'h65}       
	 263  :reg_data <={16'h5486,8'h71};//{16'h5486,8'h71}       
	 264  :reg_data <={16'h5487,8'h7d};//{16'h5487,8'h7d}       
	 265  :reg_data <={16'h5488,8'h87};//{16'h5488,8'h87}       
	 266  :reg_data <={16'h5489,8'h91};//{16'h5489,8'h91}       
	 267  :reg_data <={16'h548a,8'h9a};//{16'h548a,8'h9a}       
	 268  :reg_data <={16'h548b,8'haa};//{16'h548b,8'haa}       
	 269  :reg_data <={16'h548c,8'hb8};//{16'h548c,8'hb8}       
	 270  :reg_data <={16'h548d,8'hcd};//{16'h548d,8'hcd}       
	 271  :reg_data <={16'h548e,8'hdd};//{16'h548e,8'hdd}       
	 272  :reg_data <={16'h548f,8'hea};//{16'h548f,8'hea}       
	 273  :reg_data <={16'h5490,8'h1d};//{16'h5490,8'h1d}       
	 274  :reg_data <={16'h5381,8'h1e} ;//{16'h5381,8'h1e}    
	 275  :reg_data <={16'h5382,8'h5b} ;//{16'h5382,8'h5b}
	 276  :reg_data <={16'h5383,8'h08} ;//{16'h5383,8'h08}       
	 277  :reg_data <={16'h5384,8'h0a} ;//{16'h5384,8'h0a}       
	 278  :reg_data <={16'h5385,8'h7e} ;//{16'h5385,8'h7e}       
	 279  :reg_data <={16'h5386,8'h88} ;//{16'h5386,8'h88}       
	 280  :reg_data <={16'h5387,8'h7c} ;//{16'h5387,8'h7c}       
	 281  :reg_data <={16'h5388,8'h6c} ;//{16'h5388,8'h6c}       
	 282  :reg_data <={16'h5389,8'h10} ;//{16'h5389,8'h10}       
	 283  :reg_data <={16'h538a,8'h01} ;//{16'h538a,8'h01}       
	 284  :reg_data <={16'h538b,8'h98} ;//{16'h538b,8'h98}       
	 285  :reg_data <={16'h5580,8'h06};//{16'h5580,8'h06}    
	 286  :reg_data <={16'h5583,8'h40};//{16'h5583,8'h40}
	 287  :reg_data <={16'h5584,8'h10};//{16'h5584,8'h10}       
	 288  :reg_data <={16'h5589,8'h10};//{16'h5589,8'h10}       
	 289  :reg_data <={16'h558a,8'h00};//{16'h558a,8'h00}       
	 290  :reg_data <={16'h558b,8'hf8};//{16'h558b,8'hf8}       
	 291  :reg_data <={16'h501d,8'h40};//{16'h501d,8'h40}       
	 292  :reg_data <={16'h5300,8'h08} ;//{16'h5300,8'h08}   
	 293  :reg_data <={16'h5301,8'h30} ;//{16'h5301,8'h30}
	 294  :reg_data <={16'h5302,8'h10} ;//{16'h5302,8'h10}      
	 295  :reg_data <={16'h5303,8'h00} ;//{16'h5303,8'h00}      
	 296  :reg_data <={16'h5304,8'h08} ;//{16'h5304,8'h08}      
	 297  :reg_data <={16'h5305,8'h30} ;//{16'h5305,8'h30}      
	 298  :reg_data <={16'h5306,8'h08} ;//{16'h5306,8'h08}      
	 299  :reg_data <={16'h5307,8'h16} ;//{16'h5307,8'h16}      
	 300  :reg_data <={16'h5309,8'h08} ;//{16'h5309,8'h08}      
	 301  :reg_data <={16'h530a,8'h30} ;//{16'h530a,8'h30}      
	 302  :reg_data <={16'h530b,8'h04} ;//{16'h530b,8'h04}      
	 303  :reg_data <={16'h530c,8'h06} ;//{16'h530c,8'h06}      
	 304  :reg_data <={16'h5025,8'h00} ;//{16'h5025,8'h00}      
	/* 305  :reg_data <=24'h530c06 ;//      
	 306  :reg_data <=24'h502500 ;//
	 307  :reg_data <=24'h300882 ;//  02    */ 
  //720 30֡/��, night mode 5fps ;//         
  //input clock=24Mhz,PCLK=84Mhz ;//         
	 308  :reg_data <={16'h3035,8'h11};//PLL   11
	 309  :reg_data <={16'h3036,8'h78};//PLL    69
     310  :reg_data <={16'h3c07,8'h08};// 
	 
	 311  :reg_data <={16'h3820,8'h46};// 46       
	 312  :reg_data <={16'h3821,8'h01};// 01       
	 313  :reg_data <={16'h3814,8'h31};// 31       
	 314  :reg_data <={16'h3815,8'h31};// 31       
	 315  :reg_data <={16'h3800,8'h00};// 00       
	 316  :reg_data <={16'h3801,8'h00};// 00       
	 317  :reg_data <={16'h3802,8'h00};// 00       
	 318  :reg_data <={16'h3803,8'h04};// 04       
	 319  :reg_data <={16'h3804,8'h0a};// 0a       
	 320  :reg_data <={16'h3805,8'h3f};// 3f       
	 321  :reg_data <={16'h3806,8'h07};// 07       
	 322  :reg_data <={16'h3807,8'h9b};// 9b
       
	 323  :reg_data <={16'h3808,{4'd0,cmos_h_pixel[11:8]}} ;//        
	 324  :reg_data <={16'h3809,cmos_h_pixel[7:0]} ;//        
	 325  :reg_data <={16'h380a,{5'd0,cmos_v_pixel[10:8]}} ;//        
	 326  :reg_data <={16'h380b,cmos_v_pixel[7:0]} ;//        
	 327  :reg_data <={16'h380c,{3'd0,total_h_pixel[12:8]}} ;//        
	 328  :reg_data <={16'h380d,total_h_pixel[7:0]} ;//        
	 329  :reg_data <={16'h380e,{3'd0,total_v_pixel[12:8]}} ;//        
	 330  :reg_data <={16'h380f,total_v_pixel[7:0]} ;//        
	 331  :reg_data <={16'h3813,8'h06} ;// {16'h3813,8'h06}       
	 332  :reg_data <={16'h3618,8'h00} ;// {16'h3618,8'h00}       
	 333  :reg_data <={16'h3612,8'h29} ;// {16'h3612,8'h29}       
	 334  :reg_data <={16'h3709,8'h52} ;// {16'h3709,8'h52}       
	 335  :reg_data <={16'h370c,8'h03} ;// {16'h370c,8'h03}       
	 336  :reg_data <={16'h3a02,8'h17} ;// {16'h3a02,8'h17}       
	 337  :reg_data <={16'h3a03,8'h10} ;// {16'h3a03,8'h10}                        
	 338  :reg_data <={16'h3a14,8'h17} ;// {16'h3a14,8'h17}       
	 339  :reg_data <={16'h3a15,8'h10} ;// {16'h3a15,8'h10}       
	 340  :reg_data <={16'h4004,8'h02} ;// {16'h4004,8'h02}       
	 341  :reg_data <={16'h4713,8'h03} ;// {16'h4713,8'h03}       
	 342  :reg_data <={16'h4407,8'h04} ;// {16'h4407,8'h04}       
	 343  :reg_data <={16'h460c,8'h22} ;// {16'h460c,8'h22}       
	 344  :reg_data <={16'h4837,8'h22} ;// {16'h4837,8'h22}        
	 345  :reg_data <={16'h3824,8'h02} ;// {16'h3824,8'h02}        
	 346  :reg_data <={16'h5001,8'ha3} ;// {16'h5001,8'ha3}        
	 347  :reg_data <={16'h3b07,8'h0a} ;// {16'h3b07,8'h0a} 
     348  :reg_data <={16'h503d,8'h00}; //80.82.84.86     
	/* 348  :reg_data <=24'h3006c3 ;//         
	 349  :reg_data <=24'h471303 ;//         
	 350  :reg_data <=24'h440704 ;//         
	 351  :reg_data <=24'h460b37 ;//           
     352  :reg_data <=24'h460c20 ;//          
	 353  :reg_data <=24'h483722 ;//         
	 354  :reg_data <=24'h382402 ;//         
	 355  :reg_data <=24'h5001a3 ;//         
	 356  :reg_data <=24'h3b070a ;//         
	 357  :reg_data <=24'h350300 ;//   350300     */ 
	 default:reg_data<=24'hffffff;//        
    endcase      
end	 

endmodule

