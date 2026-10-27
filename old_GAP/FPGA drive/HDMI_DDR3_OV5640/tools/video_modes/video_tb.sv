`timescale 1ns/1ps
module video_modes_frame_tb;
    localparam W=1280, H=720, FRAMES=8;
    reg clk=0, rst_n=0, vs=0, de=0;
    always #5 clk=~clk;
    reg [15:0] rgb=0;
    reg [2:0] mode_request=0;
    reg [31:0] frame_id_in=0, frame_time_in=0;
    wire [15:0] rgb_out, clean_rgb_out;
    wire vs_out, de_out, clean_vs_out, clean_de_out;
    wire [31:0] display_frame_id, display_frame_time;
    img_proc #(.RUNTIME_MODE(1),.FRAME_TAGS(1),.ZEBRA_ENABLE(1),.ADAS_ENABLE(1)) dut (
        .clk(clk),.rst_n(rst_n),.vs_in(vs),.de_in(de),.rgb_in(rgb),
        .mode_request(mode_request),.frame_id_in(frame_id_in),.frame_time_in(frame_time_in),
        .rgb_out(rgb_out),.vs_out(vs_out),.de_out(de_out),
        .clean_rgb_out(clean_rgb_out),.clean_vs_out(clean_vs_out),.clean_de_out(clean_de_out),
        .display_frame_id(display_frame_id),.display_frame_time(display_frame_time)
    );
    function integer frame_mode(input integer f);
        frame_mode = f<6 ? f : (f==6 ? 0 : 5);
    endfunction
    function [15:0] sample(input integer y, input integer x);
        reg [7:0] shade;
        begin
            shade=32+((x/32+y/32)%4)*8;
            sample={shade[7:3],shade[7:2],shade[7:3]};
            if(x>=290 && x<298) sample=16'hffff;
            if(x>=930 && x<942) sample=16'hffe0;
            // Single-pixel noise must disappear under the median.
            if(x%83==0 && y%47==0) sample=16'hffff;
            if(y==0) sample=16'ha000^x;
            if(y==H-1) sample=16'h5000^x;
            if(x==0) sample=16'hc000^y;
            if(x==W-1) sample=16'h3000^y;
        end
    endfunction
    function integer lum(input [15:0] p);
        integer r,g,b;
        begin
            r=((p>>11)&31)*8+((p>>13)&7);
            g=((p>>5)&63)*4+((p>>9)&3);
            b=(p&31)*8+((p>>2)&7);
            lum=(77*r+150*g+29*b)/256;
        end
    endfunction
    function [15:0] grey(input integer v);
        grey=((v>>3)<<11)|((v>>2)<<5)|(v>>3);
    endfunction
    function [15:0] processed(input integer mode,input integer y,input integer x);
        integer v[0:8];
        integer dy,dx,yy,xx,i,j,t,gx,gy,m;
        begin
            for(dy=-1;dy<=1;dy=dy+1) for(dx=-1;dx<=1;dx=dx+1) begin
                yy=y+dy; xx=x+dx;
                if(yy<0) yy=0; if(yy>=H) yy=H-1;
                if(xx<0) xx=0; if(xx>=W) xx=W-1;
                v[(dy+1)*3+dx+1]=lum(sample(yy,xx));
            end
            case(mode)
                1: processed=grey(v[4]);
                2: begin
                    for(i=1;i<9;i=i+1) begin
                        t=v[i]; j=i-1;
                        while(j>=0 && v[j]>t) begin v[j+1]=v[j]; j=j-1; end
                        v[j+1]=t;
                    end
                    processed=grey(v[4]);
                end
                3: begin
                    gx=v[2]+2*v[5]+v[8]-v[0]-2*v[3]-v[6];
                    gy=v[6]+2*v[7]+v[8]-v[0]-2*v[1]-v[2];
                    if(gx<0) gx=-gx; if(gy<0) gy=-gy;
                    m=gx+gy; if(m>255) m=255;
                    processed=grey(m);
                end
                default: processed=sample(y,x);
            endcase
        end
    endfunction
    integer frame=-1, clean_frame=-1, col=0, row=0, clean_count=0;
    integer pixels=0, clean_pixels=0, frames=0, changes=0, painted=0, hud=0, errors=0;
    integer totals[0:5], f,y,x,mode,fd;
    reg [15:0] expected;
    task finish_frame;
        begin
            if(row!=H || col!=0) $fatal(1,"Incomplete raster f=%0d rows=%0d col=%0d",frame,row,col);
            mode=frame_mode(frame);
            if(mode==4 && (painted==0 || hud!=0)) $fatal(1,"Candidate paint absent or HUD leaked");
            if(mode==5 && (painted==0 || hud==0)) $fatal(1,"Legacy diagnostic not visible");
            $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d",frame,mode,W*H,painted,hud,errors);
            $display("MODE_FRAME frame=%0d mode=%0d pixels=%0d painted=%0d hud=%0d errors=%0d",
                frame,mode,W*H,painted,hud,errors);
            frames=frames+1;
        end
    endtask
    always @(posedge clk) begin
        #1;
        if(rst_n) begin
            if(clean_vs_out) begin
                if(clean_frame>=0 && clean_count!=W*H) $fatal(1,"Clean frame incomplete");
                clean_frame=clean_frame+1; clean_count=0;
            end
            if(clean_de_out) begin
                if(clean_rgb_out !== sample(clean_count/W,clean_count%W))
                    $fatal(1,"Clean stream altered by a mode");
                clean_count=clean_count+1; clean_pixels=clean_pixels+1;
            end
            if(vs_out) begin
                if(de_out) $fatal(1,"Header overlaps pixels");
                if(frame>=0) finish_frame();
                frame=frame+1; col=0; row=0; painted=0; hud=0;
                if(display_frame_id !== frame+100 || display_frame_time !== frame*1000+123)
                    $fatal(1,"Display tag not aligned to delayed header");
            end
            if(de_out) begin
                if(frame<0 || row>=H || col>=W) $fatal(1,"Pixel outside frame");
                mode=frame_mode(frame);
                expected=processed(mode,row,col);
                if(mode<4) begin
                    if(rgb_out !== expected) begin
                        if(errors<8) $display("MISMATCH f=%0d y=%0d x=%0d got=%h want=%h",
                            frame,row,col,rgb_out,expected);
                        errors=errors+1;
                    end
                end else begin
                    if(row<H*9/16 && rgb_out!==sample(row,col)) hud=hud+1;
                    if(row>=H*9/16 && rgb_out!==sample(row,col)) begin
                        if(mode==4 && rgb_out!==16'h07e0 && rgb_out!==16'h07ff)
                            $fatal(1,"Candidate mode contains unexpected drawing");
                        painted=painted+1;
                    end
                end
                totals[mode]=totals[mode]+1;
                pixels=pixels+1; col=col+1;
            end else if(col!=0) begin
                if(col!=W) $fatal(1,"Line width wrong");
                row=row+1; col=0;
            end
        end
    end
    task idle(input integer n);
        begin de=0; rgb=0; repeat(n) @(negedge clk); end
    endtask
    initial begin
        fd=$fopen("mode_frames.csv","w");
        $fdisplay(fd,"frame,mode,pixels,painted,hud,errors");
        for(f=0;f<6;f=f+1) totals[f]=0;
        idle(12); rst_n=1;
        for(f=0;f<FRAMES;f=f+1) begin
            mode_request=frame_mode(f); frame_id_in=f+100; frame_time_in=f*1000+123;
            vs=1; idle(8); vs=0; idle(128);
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W;x=x+1) begin
                    de=1; rgb=sample(y,x); @(negedge clk);
                    if(y==3 && x==500) mode_request=(frame_mode(f)+3)%6;
                end
                idle(37+(y%3)*7);
            end
            idle(2500);
        end
        finish_frame();
        if(frames!=FRAMES || pixels!=FRAMES*W*H || clean_pixels!=pixels || errors!=0)
            $fatal(1,"Video modes acceptance failed: frames=%0d errors=%0d",frames,errors);
        for(f=0;f<6;f=f+1) if(totals[f]<W*H) $fatal(1,"Mode not covered");
        rst_n=0; idle(4);
        if({vs_out,de_out,rgb_out,display_frame_id,display_frame_time}!==82'd0)
            $fatal(1,"Selected output not cleared by reset");
        $display("VIDEO_MODES_RESULT frames=%0d pixels=%0d clean_pixels=%0d errors=%0d",
            frames,pixels,clean_pixels,errors);
        $fclose(fd); $finish;
    end
    initial begin #150000000; $fatal(1,"Video modes timeout"); end
endmodule
