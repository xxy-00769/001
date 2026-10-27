`timescale 1ns/1ps
module adas_packet_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,sample_valid=0,ready=0;
    reg [255:0] sample=0;
    wire sample_ready,valid;
    wire [7:0] data;
    wire [15:0] drops;
    adas_packet dut(.clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample(sample),
                    .sample_ready(sample_ready),.dropped_samples(drops),.data(data),.valid(valid),.ready(ready));
    reg [7:0] expected[0:113];
    integer count=0,cycle=0,f,i,output_file;
    reg stalled=0;
    reg [7:0] held;
    always @(posedge clk) begin
        if(rst_n) begin
            if(stalled && (!valid || data!==held)) $fatal(1,"Backpressure changed a held byte");
            if(valid && ready) begin
                if(count>=114 || data!==expected[count]) $fatal(1,"Packet byte %0d got %h expected %h",count,data,expected[count]);
                $fwrite(output_file,"%c",data);
                count=count+1;
            end
            stalled=valid && !ready; held=data;
        end else stalled=0;
    end
    always @(negedge clk) begin
        cycle=cycle+1;
        ready=(cycle%7)!=0 && (cycle%7)!=1 && (cycle%7)!=2;
    end
    initial begin
        $readmemh("output/adas/packets.hex",expected);
        output_file=$fopen("output/adas/rtl_packets.bin","wb");
        repeat(4) @(negedge clk);
        rst_n=1;
        for(f=0;f<3;f=f+1) begin
            wait(sample_ready);
            @(negedge clk);
            for(i=0;i<32;i=i+1) sample[i*8+:8]=expected[f*38+4+i];
            sample_valid=1;
            @(negedge clk); sample_valid=0; sample=~sample;
            repeat(5) @(negedge clk);
            if(f==0) begin sample_valid=1; @(negedge clk); sample_valid=0; end
            wait(!valid);
        end
        repeat(4) @(negedge clk);
        if(count!=114 || drops!=1) $fatal(1,"Unexpected packet/drop count %0d/%0d",count,drops);
        // Reset in the middle of another packet must abort it and return idle.
        @(negedge clk); sample_valid=1;
        @(negedge clk); sample_valid=0; rst_n=0;
        repeat(4) @(negedge clk);
        if(valid!==0 || sample_ready!==1 || drops!==0) $fatal(1,"Reset failed");
        $fclose(output_file);
        $display("PASS: 114 packet bytes, independent CRC, stalls, snapshot capture, overflow and reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"Timeout"); end
endmodule
