`timescale 1ns/1ps
module conv_tb;
`include "output/cases.vh"
reg clk=0;
always #5 clk=~clk;
reg rst_n=0, cfg_valid=0, cfg_depthwise=0;
reg [6:0] cfg_ci=0, cfg_co=0;
reg [1:0] cfg_kernel=0, cfg_stride=0;
reg [3:0] cfg_dilation=0;
reg [4:0] cfg_iw=0, cfg_ih=0;
reg [2:0] cfg_ow=0, cfg_oh=0;
reg load_valid=0, start_valid=0, out_ready=0;
reg [1:0] load_kind=0;
reg [15:0] load_addr=0;
reg [7:0] load_data=0;
wire cfg_ready, load_ready, start_ready, busy, fault, done, out_valid;
wire [15:0] out_index;
wire [7:0] out_data;
wire signed [31:0] out_acc;
reg [7:0] inputs [0:INPUT_BYTES-1], weights [0:WEIGHT_BYTES-1], coeffs [0:COEFF_BYTES-1];
reg [39:0] expected [0:OUTPUT_VALUES-1];
integer d[0:17];
integer fd, output_fd, stats_fd, c, k, parsed, total=0, jobs=0, stalls_total=0;
conv_tile dut(.*);

task reset_dut;
begin
    @(negedge clk); rst_n=0; cfg_valid=0; load_valid=0; start_valid=0; out_ready=0;
    repeat(3) @(negedge clk);
    rst_n=1;
    @(negedge clk);
    if(!cfg_ready || busy || out_valid || start_ready || load_ready || fault || done) $fatal(1,"Bad reset state");
end
endtask

task set_descriptor;
begin
    cfg_depthwise=d[0]; cfg_ci=d[1]; cfg_co=d[2]; cfg_kernel=d[3]; cfg_stride=d[4];
    cfg_dilation=d[5]; cfg_iw=d[6]; cfg_ih=d[7]; cfg_ow=d[8]; cfg_oh=d[9];
end
endtask

task configure;
begin
    @(negedge clk);
    if(!cfg_ready) $fatal(1,"Cannot configure");
    set_descriptor(); cfg_valid=1;
    @(negedge clk); cfg_valid=0;
    if(fault || !busy || cfg_ready || start_ready || !load_ready) $fatal(1,"Configuration rejected");
end
endtask

task load_bank(input integer bank);
integer a;
begin
    load_kind=bank;
    for(a=0;a<d[14+bank];a=a+1) begin
        @(negedge clk);
        if(!load_ready) $fatal(1,"Load blocked case=%0d bank=%0d addr=%0d",c,bank,a);
        load_valid=1; load_addr=a;
        case(bank)
            0: load_data=inputs[d[10]+a];
            1: load_data=weights[d[11]+a];
            2: load_data=coeffs[d[12]+a];
        endcase
        if(a%17==8) begin @(negedge clk); load_valid=0; end
    end
    @(negedge clk); load_valid=0;
    if(load_ready) $fatal(1,"Full bank still accepts writes");
    load_valid=1; load_addr=0; load_data=8'h55;
    repeat(2) @(negedge clk);
    load_valid=0;
end
endtask

task load_all;
begin
    // Exercise bank independence: coefficients before pixels and weights.
    load_bank(2); load_bank(0); load_bank(1);
    if(!start_ready || fault) $fatal(1,"Complete tile not ready");
end
endtask

task launch;
begin
    @(negedge clk); start_valid=1;
    @(negedge clk); start_valid=0;
    if(start_ready || load_ready || cfg_ready || !busy || fault) $fatal(1,"Bad launch state");
end
endtask

task run_case(input integer number);
integer n, cycles, stalls;
reg held;
reg [55:0] held_value;
begin
    configure(); load_all(); launch();
    n=0; cycles=0; stalls=0; held=0;
    // Unaccepted descriptor/load/start changes must not alter the running tile.
    cfg_valid=1; cfg_ci=0; load_valid=1; load_kind=3; load_addr=0; load_data=255; start_valid=1;
    out_ready=1;
    while(n<d[17]) begin
        @(posedge clk);
        if(fault || load_ready || cfg_ready || start_ready) $fatal(1,"Busy tile accepted mutation");
        if(held && (!out_valid || {out_index,out_acc,out_data} !== held_value)) $fatal(1,"Stalled output changed");
        if(out_valid && out_ready) begin
            if(out_index !== n[15:0] || {out_acc,out_data} !== expected[d[13]+n])
                $fatal(1,"Mismatch case=%0d n=%0d got=%08x%02x expected=%010x",number,n,out_acc,out_data,expected[d[13]+n]);
            $fdisplay(output_fd,"%0d %0d %08x %02x",number,n,out_acc,out_data);
            n=n+1; total=total+1;
        end
        held=out_valid && !out_ready; held_value={out_index,out_acc,out_data};
        if(held) stalls=stalls+1;
        @(negedge clk);
        cycles=cycles+1; out_ready=(cycles%19>3 && cycles%41>4);
        if(cycles>2000000) $fatal(1,"Tile timeout");
    end
    cfg_valid=0; load_valid=0; start_valid=0; out_ready=0;
    if(!done || busy || out_valid || !cfg_ready) $fatal(1,"Bad completion");
    if(cycles!=d[2]*28 + d[17]*(5*(d[0] ? d[3]*d[3] : d[1]*d[3]*d[3])+4)+stalls)
        $fatal(1,"Unexpected core latency case=%0d cycles=%0d",number,cycles);
    $fdisplay(stats_fd,"%0d %0d %0d %0d",number,cycles,n,stalls);
    jobs=jobs+1; stalls_total=stalls_total+stalls;
end
endtask

initial begin
    $readmemh("output/inputs.hex",inputs); $readmemh("output/weights.hex",weights);
    $readmemh("output/coefficients.hex",coeffs); $readmemh("output/expected.hex",expected);
    fd=$fopen("output/descriptors.txt","r"); output_fd=$fopen("output/rtl_outputs.txt","w");
    stats_fd=$fopen("output/rtl_cycles.txt","w");
    if(!fd || !output_fd || !stats_fd) $fatal(1,"Cannot open vector files");
    parsed=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
        d[0],d[1],d[2],d[3],d[4],d[5],d[6],d[7],d[8],d[9],d[10],d[11],d[12],d[13],d[14],d[15],d[16],d[17]);
    if(parsed!=18) $fatal(1,"Bad first descriptor");
    // Illegal geometry/capacity is sticky until reset, without exposing memory.
    for(k=0;k<7;k=k+1) begin
        reset_dut(); set_descriptor();
        case(k)
            0: cfg_ci=0;
            1: cfg_co=81;
            2: cfg_iw=1;
            3: begin cfg_depthwise=1; cfg_co=1; end
            4: begin cfg_ci=80; cfg_co=80; cfg_kernel=3; cfg_dilation=1; cfg_stride=1; cfg_iw=6; cfg_ih=6; end
            5: begin cfg_depthwise=1; cfg_ci=80; cfg_co=80; cfg_kernel=3; cfg_stride=2; cfg_dilation=8; cfg_iw=23; cfg_ih=23; end
            6: cfg_ow=0;
        endcase
        cfg_valid=1;
        @(negedge clk); cfg_valid=0;
        if(!fault || cfg_ready || load_ready || start_ready || out_valid) $fatal(1,"Bad descriptor not rejected %0d",k);
    end
    reset_dut(); configure();
    load_kind=0; load_addr=1; load_valid=1;
    @(negedge clk); load_valid=0;
    if(!fault || load_ready || start_ready) $fatal(1,"Out-of-order load not rejected");
    reset_dut(); configure();
    load_kind=3; load_addr=0; load_valid=1;
    @(negedge clk); load_valid=0;
    if(!fault) $fatal(1,"Reserved bank not rejected");
    reset_dut(); configure(); load_kind=0;
    load_valid=1; load_addr=0; load_data=0;
    @(negedge clk); load_valid=0; start_valid=1;
    repeat(10) @(negedge clk);
    if(start_ready || out_valid || dut.state!=dut.LOAD || fault) $fatal(1,"Incomplete tile started");
    reset_dut(); configure(); load_all(); launch();
    repeat(37) @(negedge clk);
    reset_dut(); configure(); load_all(); launch();
    while(!out_valid) @(negedge clk);
    repeat(17) begin
        @(negedge clk);
        if(!out_valid || done || cfg_ready) $fatal(1,"Premature done while output blocked");
    end
    reset_dut();
    configure(); load_all();
    @(negedge clk); load_kind=3; load_valid=1; start_valid=1;
    @(negedge clk); load_valid=0; start_valid=0;
    if(!fault || out_valid || dut.state!=dut.LOAD) $fatal(1,"Invalid write raced tile start");
    reset_dut();
    for(c=0;c<CASES;c=c+1) begin
        if(c!=0) begin
            parsed=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                d[0],d[1],d[2],d[3],d[4],d[5],d[6],d[7],d[8],d[9],d[10],d[11],d[12],d[13],d[14],d[15],d[16],d[17]);
            if(parsed!=18) $fatal(1,"Bad descriptor %0d",c);
        end
        load_kind=0;
        run_case(c);
        if(c%250==0) $display("Progress %0d/%0d",c,CASES);
    end
    if(total!=OUTPUT_VALUES || jobs!=CASES || stalls_total==0) $fatal(1,"Incomplete coverage");
    $fclose(fd); $fclose(output_fd); $fclose(stats_fd);
    $display("PASS: conv %0d jobs %0d exact outputs %0d held cycles",jobs,total,stalls_total);
    $finish;
end
initial begin #(64'd10000000000); $fatal(1,"Global watchdog"); end
endmodule
