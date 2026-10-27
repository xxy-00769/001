`timescale 1ns/1ps
module stream_tb;
`include "output/cases.vh"
`include "output/vector_cases.vh"
reg clk=0;
always #5 clk=~clk;
reg rst_n=0, cfg_valid=0, cfg_depthwise=0;
reg cfg_reuse=0, cfg_banked_load=0;
reg [31:0] cfg_weights_id=0;
wire cache_valid;
wire [31:0] cached_weights_id;
reg use_wide=0, reuse_weights=0;
reg [6:0] cfg_ci=0, cfg_co=0;
reg [1:0] cfg_kernel=0, cfg_stride=0;
reg [3:0] cfg_dilation=0;
reg [4:0] cfg_iw=0, cfg_ih=0;
reg [2:0] cfg_ow=0, cfg_oh=0;
reg load_valid=0, start_valid=0, out_ready=0;
reg [1:0] load_kind=0;
reg [15:0] load_addr=0;
reg [7:0] load_data=0;
reg vec_valid=0;
wire vec_ready;
reg [1:0] vec_kind=0;
reg [11:0] vec_addr=0;
reg [127:0] vec_data=0;
reg [15:0] vec_keep=0;
wire cfg_ready, load_ready, start_ready, busy, fault, done, out_valid;
wire [15:0] out_index;
wire [7:0] out_data;
wire signed [31:0] out_acc;
reg [7:0] inputs [0:INPUT_BYTES-1], weights [0:WEIGHT_BYTES-1], coeffs [0:COEFF_BYTES-1];
reg [39:0] expected [0:OUTPUT_VALUES-1];
reg [143:0] vectors [0:VECTOR_WORDS-1];
integer d[0:17];
integer vd[0:7];
integer fd, vector_fd, output_fd, stats_fd, transfer_fd, c, k, b, pass, parsed, total=0, jobs=0, stalls_total=0;
integer beats=0, loaded_bytes=0;
reg count_transfers=0;
conv_cached dut(.*);
wire p_cfg_ready, p_load_ready, p_vec_ready, p_start_ready;
wire p_busy, p_fault, p_done, p_cache_valid, p_out_valid;
wire [31:0] p_cached_weights_id;
wire [15:0] p_out_index;
wire [7:0] p_out_data;
wire signed [31:0] p_out_acc;
wire [127:0] config_payload = {55'd0,cfg_oh,cfg_ow,cfg_ih,cfg_iw,cfg_dilation,cfg_stride,
    cfg_kernel,cfg_co,cfg_ci,cfg_depthwise,cfg_weights_id,cfg_banked_load,cfg_reuse};
wire [127:0] probe_payload = cfg_valid && cfg_ready ? config_payload : use_wide ? vec_data : {120'd0,load_data};
conv_stream_probe probe (
    .clk(clk), .rst_n(rst_n), .command({start_valid,vec_valid,load_valid,cfg_valid}), .payload(probe_payload),
    .address(use_wide ? {4'd0,vec_addr} : load_addr), .kind(use_wide ? vec_kind : load_kind), .keep(vec_keep),
    .out_ready(out_ready), .cfg_ready(p_cfg_ready), .load_ready(p_load_ready), .vec_ready(p_vec_ready),
    .start_ready(p_start_ready), .busy(p_busy), .fault(p_fault), .done(p_done), .cache_valid(p_cache_valid),
    .cached_weights_id(p_cached_weights_id), .out_valid(p_out_valid), .out_index(p_out_index),
    .out_data(p_out_data), .out_acc(p_out_acc)
);
always @(posedge clk) if(rst_n) begin
    if({p_cfg_ready,p_load_ready,p_vec_ready,p_start_ready,p_busy,p_fault,p_done,p_cache_valid,p_cached_weights_id,p_out_valid}
       !== {cfg_ready,load_ready,vec_ready,start_ready,busy,fault,done,cache_valid,cached_weights_id,out_valid})
        $fatal(1,"Resource probe control differs from direct core");
    if(out_valid && {p_out_index,p_out_data,p_out_acc} !== {out_index,out_data,out_acc})
        $fatal(1,"Resource probe data differs from direct core");
end
always @(posedge clk) if(count_transfers) begin
    if(load_valid && load_ready && dut.ordered) begin beats=beats+1; loaded_bytes=loaded_bytes+1; end
    if(vec_valid && vec_ready && dut.vec_ordered) begin beats=beats+1; loaded_bytes=loaded_bytes+dut.vec_bytes; end
end

task reset_dut;
begin
    @(negedge clk); rst_n=0; cfg_valid=0; load_valid=0; vec_valid=0; start_valid=0; out_ready=0;
    count_transfers=0; cfg_reuse=0; cfg_banked_load=0;
    repeat(3) @(negedge clk);
    rst_n=1;
    @(negedge clk);
    if(!cfg_ready || busy || out_valid || start_ready || load_ready || vec_ready || fault || done || cache_valid) $fatal(1,"Bad reset state");
end
endtask

task set_descriptor;
begin
    cfg_depthwise=d[0]; cfg_ci=d[1]; cfg_co=d[2]; cfg_kernel=d[3]; cfg_stride=d[4];
    cfg_dilation=d[5]; cfg_iw=d[6]; cfg_ih=d[7]; cfg_ow=d[8]; cfg_oh=d[9];
    cfg_reuse=reuse_weights; cfg_banked_load=use_wide; cfg_weights_id=vd[0];
end
endtask

task settle_configuration;
integer wait_cycles;
begin
    wait_cycles=0;
    while(!fault && dut.state!=dut.LOAD && wait_cycles<8) begin
        if(cfg_ready || load_ready || vec_ready || start_ready || out_valid || !busy)
            $fatal(1,"Configuration phase accepted traffic");
        @(negedge clk);
        wait_cycles=wait_cycles+1;
    end
    if(wait_cycles>4 || (!fault && dut.state!=dut.LOAD)) $fatal(1,"Configuration pipeline timeout");
end
endtask

task configure;
begin
    @(negedge clk);
    if(!cfg_ready) $fatal(1,"Cannot configure");
    set_descriptor(); cfg_valid=1;
    @(negedge clk); cfg_valid=0;
    settle_configuration();
    if(fault || !busy || cfg_ready || start_ready || (!use_wide && !load_ready) || (use_wide && !vec_ready))
        $fatal(1,"Configuration rejected case=%0d mode=%0d reuse=%0d",c,use_wide,reuse_weights);
end
endtask

task send_byte(input integer bank, input integer a);
begin
    @(negedge clk); load_kind=bank; load_addr=a;
    #1;
    if(!load_ready) $fatal(1,"Load blocked case=%0d bank=%0d addr=%0d",c,bank,a);
    load_valid=1;
    case(bank)
        0: load_data=inputs[d[10]+a];
        1: load_data=weights[d[11]+a];
        2: load_data=coeffs[d[12]+a];
    endcase
    if(a%17==8) begin @(negedge clk); load_valid=0; end
end
endtask

task load_bank(input integer bank);
integer a;
begin
    for(a=0;a<d[14+bank];a=a+1) send_byte(bank,a);
    @(negedge clk); load_valid=0;
    if(load_ready) $fatal(1,"Full bank still accepts writes");
    load_valid=1; load_addr=0; load_data=8'h55;
    repeat(2) @(negedge clk);
    load_valid=0;
end
endtask

task load_vectors(input integer bank);
integer a;
begin
    for(a=0;a<vd[5+bank];a=a+1) begin
        @(negedge clk); vec_kind=bank; vec_addr=a;
        {vec_keep,vec_data}=vectors[vd[2+bank]+a];
        #1;
        if(!vec_ready || load_ready) $fatal(1,"Vector blocked or byte mode active");
        vec_valid=1;
        if(a%17==8) begin @(negedge clk); vec_valid=0; end
    end
    @(negedge clk); vec_valid=0;
    if(vec_ready) $fatal(1,"Full vector bank accepts writes");
    vec_valid=1; vec_addr=0; vec_data=0; vec_keep=0;
    repeat(2) @(negedge clk);
    vec_valid=0;
end
endtask

task load_all;
integer a, bank, maximum;
begin
    if(reuse_weights) begin
        if(!cache_valid || cached_weights_id!=vd[0]) $fatal(1,"Cache identity not retained");
        for(bank=1;bank<=2;bank=bank+1) begin
            @(negedge clk); load_kind=bank; vec_kind=bank;
            load_valid=1; load_addr=0; load_data=0;
            vec_valid=1; vec_addr=0; vec_data=0; vec_keep=0;
            #1;
            if(load_ready || vec_ready) $fatal(1,"Retained bank is writable");
            repeat(2) @(negedge clk);
        end
        load_valid=0; vec_valid=0;
    end
    if(use_wide) begin
        // Byte traffic must be ignored for a descriptor selecting banked ingress.
        load_valid=1; load_kind=3;
        if(!reuse_weights) begin load_vectors(2); load_vectors(1); end
        load_vectors(0);
        load_valid=0;
    end else if(reuse_weights) begin
        vec_valid=1; vec_kind=3; load_bank(0); vec_valid=0;
    end else if(c%13==7) begin
        maximum=d[14];
        if(d[15]>maximum) maximum=d[15];
        if(d[16]>maximum) maximum=d[16];
        for(a=0;a<maximum;a=a+1)
            for(bank=0;bank<3;bank=bank+1)
                if(a<d[14+bank]) send_byte(bank,a);
        @(negedge clk); load_valid=0;
    end else begin
        vec_valid=1; vec_kind=3;
        load_bank(2); load_bank(0); load_bank(1);
        vec_valid=0;
    end
    if(!start_ready || fault) $fatal(1,"Complete tile not ready");
end
endtask

task launch;
begin
    @(negedge clk); start_valid=1;
    @(negedge clk); start_valid=0;
    if(start_ready || load_ready || vec_ready || cfg_ready || !busy || fault || !cache_valid || cached_weights_id!=vd[0])
        $fatal(1,"Bad launch state");
end
endtask

task run_case(input integer number);
integer n, cycles, stalls, groups, terms;
reg held;
reg [55:0] held_value;
reg [1279:0] seen;
begin
    configure(); beats=0; loaded_bytes=0; count_transfers=1;
    load_all(); count_transfers=0;
    if(loaded_bytes!=d[14]+(reuse_weights ? 0 : d[15]+d[16])) $fatal(1,"Unexpected load byte count");
    if(beats!=(use_wide ? vd[5]+(reuse_weights ? 0 : vd[6]+vd[7]) : loaded_bytes)) $fatal(1,"Unexpected transfer count");
    $fdisplay(transfer_fd,"%0d %0d %0d %0d %0d %0d",number,c,use_wide,reuse_weights,beats,loaded_bytes);
    launch();
    n=0; cycles=0; stalls=0; held=0; seen=0;
    cfg_valid=1; cfg_ci=0; load_valid=1; load_kind=3; load_addr=0; load_data=255; start_valid=1;
    vec_valid=1; vec_kind=3; vec_addr=0; vec_data=0; vec_keep=0;
    cfg_weights_id=~cfg_weights_id; cfg_reuse=1; cfg_banked_load=~cfg_banked_load;
    out_ready=1;
    while(n<d[17]) begin
        @(posedge clk);
        if(fault || load_ready || vec_ready || cfg_ready || start_ready || !cache_valid || cached_weights_id!=vd[0])
            $fatal(1,"Busy tile accepted mutation");
        if(held && (!out_valid || {out_index,out_acc,out_data} !== held_value)) $fatal(1,"Stalled output changed");
        if(out_valid && out_ready) begin
            if(out_index>=d[17] || seen[out_index] !== 1'b0) $fatal(1,"Duplicate/out-of-range output");
            if({out_acc,out_data} !== expected[d[13]+out_index])
                $fatal(1,"Mismatch case=%0d index=%0d got=%08x%02x expected=%010x",number,out_index,out_acc,out_data,expected[d[13]+out_index]);
            seen[out_index]=1;
            $fdisplay(output_fd,"%0d %0d %08x %02x",number,out_index,out_acc,out_data);
            n=n+1; total=total+1;
        end
        held=out_valid && !out_ready; held_value={out_index,out_acc,out_data};
        if(held) stalls=stalls+1;
        @(negedge clk);
        cycles=cycles+1; out_ready=(cycles%19>3 && cycles%41>4);
        if(cycles>2000000) $fatal(1,"Tile timeout");
    end
    cfg_valid=0; load_valid=0; vec_valid=0; start_valid=0; out_ready=0;
    if(!done || busy || out_valid || !cfg_ready) $fatal(1,"Bad completion");
    groups=(d[2]+15)/16; terms=(d[0] ? 1 : d[1])*d[3]*d[3];
    if(cycles!=28*groups+d[8]*d[9]*(groups*(terms+8)+d[2])+stalls)
        $fatal(1,"Unexpected core latency case=%0d cycles=%0d expected=%0d stalls=%0d",number,cycles,28*groups+d[8]*d[9]*(groups*(terms+8)+d[2]),stalls);
    $fdisplay(stats_fd,"%0d %0d %0d %0d",number,cycles,n,stalls);
    jobs=jobs+1; stalls_total=stalls_total+stalls;
end
endtask

task read_descriptor;
begin
    parsed=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
        d[0],d[1],d[2],d[3],d[4],d[5],d[6],d[7],d[8],d[9],d[10],d[11],d[12],d[13],d[14],d[15],d[16],d[17]);
    if(parsed!=18) $fatal(1,"Bad descriptor");
    parsed=$fscanf(vector_fd,"%d %d %d %d %d %d %d %d\n",vd[0],vd[1],vd[2],vd[3],vd[4],vd[5],vd[6],vd[7]);
    if(parsed!=8) $fatal(1,"Bad vector descriptor");
end
endtask

task prime_cache;
begin
    use_wide=1; reuse_weights=0;
    reset_dut(); load_kind=0; vec_kind=0; configure(); load_all(); launch(); out_ready=1;
    while(!done) @(negedge clk);
    out_ready=0;
    if(!cache_valid || !cfg_ready || cached_weights_id!=vd[0]) $fatal(1,"Cache not committed after complete job");
end
endtask

task cache_and_vector_faults;
integer test, bank;
begin
    for(test=0;test<7;test=test+1) begin
        if(test<5) prime_cache();
        else begin
            if(test==6) prime_cache();
            reset_dut();
        end
        set_descriptor(); cfg_reuse=1;
        case(test)
            0: cfg_weights_id=vd[0]+1;
            1: cfg_ci=d[1]+1;
            2: cfg_co=d[2]-1;
            3: begin cfg_kernel=1; cfg_iw=7; cfg_ih=7; end
            4: begin cfg_depthwise=1; cfg_ci=d[2]; end
        endcase
        cfg_valid=1;
        @(negedge clk); cfg_valid=0;
        settle_configuration();
        if(!fault || cache_valid || load_ready || vec_ready || start_ready || out_valid)
            $fatal(1,"Unsafe cache reuse accepted test=%0d",test);
    end
    use_wide=1; reuse_weights=0;
    for(bank=0;bank<3;bank=bank+1) begin
        for(test=0;test<3;test=test+1) begin
            reset_dut(); vec_kind=0; configure();
            vec_kind=bank; vec_addr=0; {vec_keep,vec_data}=vectors[vd[2+bank]];
            case(test)
                0: vec_addr=1;
                1: vec_keep=0;
                2: vec_keep=vec_keep ^ 16'h8000;
            endcase
            vec_valid=1;
            @(negedge clk); vec_valid=0;
            if(!fault || cache_valid || vec_ready || start_ready || out_valid) $fatal(1,"Bad vector accepted");
        end
    end
    reset_dut(); vec_kind=0; configure();
    vec_kind=0; vec_addr=0; {vec_keep,vec_data}=vectors[vd[2]]; vec_valid=1;
    @(negedge clk); vec_valid=0; start_valid=1;
    repeat(7) @(negedge clk);
    if(start_ready || out_valid || cache_valid || fault) $fatal(1,"Incomplete vectors started");
    reset_dut(); vec_kind=0; configure(); load_all();
    vec_valid=1; vec_kind=3; start_valid=1;
    @(negedge clk); vec_valid=0; start_valid=0;
    if(!fault || cache_valid || out_valid || dut.state!=dut.LOAD) $fatal(1,"Vector/start race accepted");
    use_wide=0; reuse_weights=0; reset_dut();
end
endtask

task block_final_output;
integer n;
reg [55:0] value;
begin
    reset_dut(); configure(); load_all(); launch();
    n=0; out_ready=1;
    while(n<d[17]-1) begin
        @(posedge clk);
        if(out_valid && out_ready) begin
            if({out_acc,out_data} !== expected[d[13]+out_index]) $fatal(1,"Final-stall setup mismatch");
            n=n+1;
        end
        @(negedge clk);
    end
    out_ready=0;
    while(!out_valid) @(negedge clk);
    value={out_index,out_acc,out_data};
    cfg_valid=1; cfg_ci=0; load_valid=1; load_kind=3; start_valid=1;
    repeat(23) begin
        @(negedge clk);
        if(!out_valid || {out_index,out_acc,out_data} !== value || done || !busy || cfg_ready || fault)
            $fatal(1,"Final stalled output/completion changed");
    end
    if(out_index!=d[17]-1 || {out_acc,out_data} !== expected[d[13]+out_index]) $fatal(1,"Bad final output");
    out_ready=1;
    @(negedge clk);
    cfg_valid=0; load_valid=0; start_valid=0; out_ready=0;
    if(!done || busy || out_valid || !cfg_ready) $fatal(1,"Final handshake did not finish job");
    reset_dut();
end
endtask

initial begin
    $readmemh("output/inputs.hex",inputs); $readmemh("output/weights.hex",weights);
    $readmemh("output/coefficients.hex",coeffs); $readmemh("output/expected.hex",expected);
    $readmemh("output/vectors.hex",vectors);
    fd=$fopen("output/descriptors.txt","r"); output_fd=$fopen("output/rtl_outputs.txt","w");
    vector_fd=$fopen("output/vector_descriptors.txt","r"); transfer_fd=$fopen("output/rtl_transfers.txt","w");
    stats_fd=$fopen("output/rtl_cycles.txt","w");
    if(!fd || !vector_fd || !output_fd || !stats_fd || !transfer_fd) $fatal(1,"Cannot open vector files");
    c=0; read_descriptor();
    for(k=0;k<26;k=k+1) begin
        reset_dut(); set_descriptor();
        case(k)
            0: cfg_ci=0;
            1: cfg_co=81;
            2: cfg_iw=1;
            3: begin cfg_depthwise=1; cfg_co=1; end
            4: begin cfg_ci=80; cfg_co=80; cfg_kernel=3; cfg_dilation=1; cfg_stride=1; cfg_iw=6; cfg_ih=6; end
            5: begin cfg_depthwise=1; cfg_ci=80; cfg_co=80; cfg_kernel=3; cfg_stride=2; cfg_dilation=8; cfg_iw=23; cfg_ih=23; end
            6: cfg_ow=0;
            7: cfg_stride=0;
            8: cfg_dilation=0;
            9: cfg_kernel=0;
            10: cfg_co=0;
            11: cfg_oh=5;
            12: cfg_dilation=9;
            13: cfg_ci=127;
            14: cfg_co=127;
            15: cfg_iw=31;
            16: cfg_ih=31;
            17: cfg_ow=7;
            18: cfg_oh=7;
            19: cfg_stride=3;
            20: cfg_dilation=15;
            21: begin cfg_depthwise=1; cfg_ci=80; cfg_co=80; cfg_kernel=3; cfg_stride=2; cfg_dilation=8; cfg_iw=23; cfg_ih=23; end
            22: begin cfg_ci=127; cfg_co=127; cfg_kernel=3; cfg_iw=6; cfg_ih=6; end
            23: begin cfg_ci=80; cfg_co=80; cfg_iw=31; cfg_ih=31; end
            24: cfg_iw=0;
            25: cfg_ih=0;
        endcase
        cfg_valid=1;
        @(negedge clk); cfg_valid=0;
        settle_configuration();
        if(!fault || cfg_ready || load_ready || start_ready || out_valid) $fatal(1,"Bad descriptor not rejected %0d",k);
    end
    for(k=0;k<4;k=k+1) begin
        reset_dut(); set_descriptor(); cfg_valid=1;
        @(negedge clk); cfg_valid=0;
        repeat(k) @(negedge clk);
        reset_dut();
    end
    // Change every live configuration/data port after acceptance; none may leak
    // into the pending descriptor or be accepted before validation completes.
    reset_dut(); set_descriptor(); cfg_valid=1;
    @(negedge clk); cfg_valid=1; cfg_ci=0; cfg_co=0; cfg_kernel=0; cfg_stride=0;
    cfg_dilation=0; cfg_iw=0; cfg_ih=0; cfg_ow=0; cfg_oh=0; cfg_depthwise=~cfg_depthwise;
    cfg_reuse=1; cfg_banked_load=~cfg_banked_load; cfg_weights_id=~cfg_weights_id;
    load_valid=1; load_kind=3; vec_valid=1; vec_kind=3; start_valid=1;
    repeat(3) begin
        if(load_ready || vec_ready || start_ready || cfg_ready || out_valid || fault)
            $fatal(1,"Speculative traffic escaped configuration pipeline");
        @(negedge clk);
    end
    cfg_valid=0; load_valid=0; vec_valid=0; start_valid=0;
    settle_configuration();
    if(fault || dut.ci!=d[1] || dut.co!=d[2] || dut.kernel!=d[3] || dut.stride!=d[4] ||
        dut.dilation!=d[5] || dut.iw!=d[6] || dut.ih!=d[7] || dut.ow!=d[8] || dut.oh!=d[9] ||
        dut.depthwise!=d[0] || dut.banked_load!=use_wide || cached_weights_id!=vd[0])
        $fatal(1,"Live configuration corrupted captured descriptor");
    reset_dut();
    $display("PASS: staged config 26 invalid descriptors, 4 phase resets, immutable capture and traffic exclusion");
    for(b=0;b<4;b=b+1) begin
        reset_dut(); configure(); load_kind=b; load_addr=1; load_valid=1;
        @(negedge clk); load_valid=0;
        repeat(3) @(negedge clk);
        if(!fault || load_ready || start_ready || out_valid) $fatal(1,"Bad bank/order not rejected %0d",b);
    end
    reset_dut(); configure(); load_kind=0;
    load_valid=1; load_addr=0; load_data=0;
    @(negedge clk); load_valid=0; start_valid=1;
    repeat(10) @(negedge clk);
    if(start_ready || out_valid || dut.state!=dut.LOAD || fault) $fatal(1,"Incomplete tile started");
    for(k=0;k<6;k=k+1) begin
        reset_dut(); configure(); load_all(); launch();
        while(dut.state!=dut.RUN) @(negedge clk);
        repeat(k+1) @(negedge clk);
        reset_dut();
    end
    configure(); load_all(); launch();
    while(!out_valid) @(negedge clk);
    repeat(17) begin
        @(negedge clk);
        if(!out_valid || done || cfg_ready) $fatal(1,"Premature done while output blocked");
    end
    reset_dut(); configure(); load_all();
    @(negedge clk); load_kind=3; load_valid=1; start_valid=1;
    @(negedge clk); load_valid=0; start_valid=0;
    if(!fault || out_valid || dut.state!=dut.LOAD) $fatal(1,"Invalid write raced tile start");
    block_final_output();
    cache_and_vector_faults();
    reset_dut();
    for(pass=0;pass<3;pass=pass+1) begin
        parsed=$fseek(fd,0,0); parsed=$fseek(vector_fd,0,0);
        for(c=0;c<CASES;c=c+1) begin
            read_descriptor();
            use_wide=pass==1 || (pass==2 && c%2==1); reuse_weights=pass==2 && vd[1];
            load_kind=0; vec_kind=0; run_case(pass*CASES+c);
            if(c%500==0) $display("Progress pass=%0d %0d/%0d",pass,c,CASES);
        end
    end
    if(total!=3*OUTPUT_VALUES || jobs!=3*CASES || stalls_total==0) $fatal(1,"Incomplete coverage");
    $fclose(fd); $fclose(vector_fd); $fclose(output_fd); $fclose(stats_fd); $fclose(transfer_fd);
    $display("PASS: stream %0d jobs %0d exact outputs, %0d stalls",jobs,total,stalls_total);
    $display("PASS: resource probe matches core cycle-for-cycle");
    $finish;
end
initial begin #2000000000; $fatal(1,"Global timeout"); end
endmodule
