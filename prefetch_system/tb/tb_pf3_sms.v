`timescale 1ns/1ps
`default_nettype none
module tb_pf3_sms;
    localparam NB     = 4;
    localparam PC_W   = 64;
    localparam ADDR_W = 64;
    localparam PA_W   = 56;
    localparam LINE_W = 58;
    localparam PLW    = 50;
    localparam MAXQ   = 65536;
    reg clk;
    reg rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;
    reg  [NB-1:0]        train_valid;
    reg  [NB-1:0]        train_no_train;
    reg  [NB*PC_W-1:0]   train_pc;
    reg  [NB*ADDR_W-1:0] train_addr;
    reg  [NB-1:0]        train_zero;
    reg  [NB-1:0]        evict_valid;
    reg  [NB*LINE_W-1:0] evict_line;
    reg                  pf_enable;
    wire                 load_valid;
    wire [44:0]          load_region;
    wire [4:0]           load_line;
    wire [4:0]           load_first;
    wire [NB-1:0]        load_first_bank;
    wire [31:0]          load_rest;
    wire                 held;
    wire                 cand_valid;
    wire [LINE_W-1:0]    cand_line;
    wire [NB-1:0]        cand_bank;
    assign held = 1'b0;
    l1d_pf3_sms_core u_core (
        .clk             (clk),
        .rst             (rst),
        .pf_enable       (pf_enable),
        .train_valid     (train_valid),
        .train_no_train  (train_no_train),
        .train_pc        (train_pc),
        .train_addr      (train_addr),
        .evict_valid     (evict_valid),
        .evict_line_addr (evict_line),
        .load_valid      (load_valid),
        .load_region     (load_region),
        .load_line       (load_line),
        .load_first      (load_first),
        .load_first_bank (load_first_bank),
        .load_rest       (load_rest)
    );
    l1d_pf3_sms_expand u_expand (
        .clk             (clk),
        .rst             (rst),
        .pf_enable       (pf_enable),
        .load_valid      (load_valid),
        .load_region     (load_region),
        .load_line       (load_line),
        .load_first      (load_first),
        .load_first_bank (load_first_bank),
        .load_rest       (load_rest),
        .held            (held),
        .cand_valid      (cand_valid),
        .cand_line       (cand_line),
        .cand_bank       (cand_bank)
    );
    wire [NB*PLW-1:0]    ref_tr_line;
    wire [NB*PLW-1:0]    ref_ev_line;
    reg                  ref_fb_valid;
    reg  [PLW-1:0]       ref_fb_addr;
    wire [1:0]           ref_fb_result;
    wire                 ref_ready;
    wire                 ref_pf_valid;
    wire [PLW-1:0]       ref_pf_line;
    assign ref_fb_result = 2'd0;
    assign ref_ready = 1'b1;
    genvar lg;
    generate
        for (lg = 0; lg < NB; lg = lg + 1) begin : g_ref_lane
            assign ref_tr_line[lg*PLW +: PLW] = train_addr[lg*ADDR_W + 6 +: PLW];
            assign ref_ev_line[lg*PLW +: PLW] = evict_line[lg*LINE_W +: PLW];
        end
    endgenerate
    l1d_pf_sms #(.PC_W(PC_W), .N_PORTS(NB), .N_BANKS(NB)) u_ref (
        .clk          (clk),
        .rst          (rst),
        .pf_enable    (pf_enable),
        .tr_valid     (train_valid),
        .tr_no_train  (train_no_train),
        .tr_pc        (train_pc),
        .tr_line_addr (ref_tr_line),
        .tr_is_store  (train_zero),
        .tr_miss      (train_zero),
        .tr_pf_hit    (train_zero),
        .ev_valid     (evict_valid),
        .ev_line_addr (ref_ev_line),
        .pf_fb_valid  (ref_fb_valid),
        .pf_fb_addr   (ref_fb_addr),
        .pf_fb_result (ref_fb_result),
        .pf_ready     (ref_ready),
        .pf_valid     (ref_pf_valid),
        .pf_line_addr (ref_pf_line)
    );
    reg  [PLW:0]     fb_pipe [0:2];
    always @(posedge clk) begin
        if (rst) begin
            fb_pipe[0] <= 0; fb_pipe[1] <= 0; fb_pipe[2] <= 0;
            ref_fb_valid <= 1'b0;
        end
        else begin
            fb_pipe[0] <= {ref_pf_valid, ref_pf_line};
            fb_pipe[1] <= fb_pipe[0];
            fb_pipe[2] <= fb_pipe[1];
            ref_fb_valid <= fb_pipe[2][PLW];
            ref_fb_addr  <= fb_pipe[2][PLW-1:0];
        end
    end
    reg  [PLW-1:0]  dut_q [0:MAXQ-1];
    reg  [PLW-1:0]  ref_q [0:MAXQ-1];
    integer         dut_wr, ref_wr, err_cnt, cyc, first_cyc, trig_cyc, first_idx;
    integer         seed, ngen, gap, npcs, gen, i, j, k, lane, g, nlines;
    reg  [PC_W-1:0] pc_tab   [0:7];
    reg  [4:0]      trig_tab [0:7];
    reg  [31:0]     foot_tab [0:7];
    reg  [44:0]     region;
    reg  [4:0]      ln;
    always @(posedge clk) begin
        if (!rst) begin
            cyc = cyc + 1;
            if (cand_valid) begin
                dut_q[dut_wr] = cand_line[PLW-1:0];
                dut_wr = dut_wr + 1;
                if (first_cyc < 0) first_cyc = cyc;
                if (^{cand_line, cand_bank} === 1'bx) begin
                    $display("ERROR cycle %0d: X on the candidate", cyc);
                    err_cnt = err_cnt + 1;
                end
                if (cand_bank !== (4'b0001 << cand_line[1:0])) begin
                    $display("ERROR cycle %0d: bank %b line %h", cyc, cand_bank, cand_line);
                    err_cnt = err_cnt + 1;
                end
            end
            if (ref_pf_valid) begin
                ref_q[ref_wr] = ref_pf_line;
                ref_wr = ref_wr + 1;
            end
        end
    end
    task send_train;
        input integer lane_n;
        input [PC_W-1:0] pc;
        input [44:0] reg_n;
        input [4:0] line_n;
        begin
            @(negedge clk);
            train_valid = 0; evict_valid = 0;
            train_valid[lane_n] = 1'b1;
            train_pc[lane_n*PC_W +: PC_W] = pc;
            train_addr[lane_n*ADDR_W +: ADDR_W] = {8'd0, reg_n, line_n, 6'd0};
            @(negedge clk);
            train_valid = 0;
            for (g = 0; g < gap; g = g + 1) @(posedge clk);
        end
    endtask
    task send_evict;
        input integer lane_n;
        input [44:0] reg_n;
        input [4:0] line_n;
        begin
            @(negedge clk);
            train_valid = 0; evict_valid = 0;
            evict_valid[lane_n] = 1'b1;
            evict_line[lane_n*LINE_W +: LINE_W] = {8'd0, reg_n, line_n};
            @(negedge clk);
            evict_valid = 0;
            for (g = 0; g < gap; g = g + 1) @(posedge clk);
        end
    endtask
    initial begin
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        if (!$value$plusargs("NGEN=%d", ngen)) ngen = 600;
        if (!$value$plusargs("GAP=%d", gap)) gap = 40;
        if (!$value$plusargs("PCS=%d", npcs)) npcs = 6;
        dut_wr = 0; ref_wr = 0; err_cnt = 0; cyc = 0; first_cyc = -1;
        rst = 1; pf_enable = 1;
        train_valid = 0; train_no_train = 0; train_pc = 0; train_addr = 0; train_zero = 0;
        evict_valid = 0; evict_line = 0;
        for (i = 0; i < 8; i = i + 1) begin
            pc_tab[i]   = {$random(seed), $random(seed)};
            trig_tab[i] = $random(seed);
            foot_tab[i] = $random(seed) & $random(seed);
        end
        repeat (4) @(posedge clk);
        rst = 0;
        send_train(0, 64'h0000_0000_0040_1000, 45'h2468A, 5'd0);
        send_train(1, 64'h0000_0000_0040_1004, 45'h2468A, 5'd3);
        send_train(2, 64'h0000_0000_0040_1008, 45'h2468A, 5'd6);
        send_evict(3, 45'h2468A, 5'd3);
        first_cyc = -1;
        first_idx = dut_wr;
        @(negedge clk);
        trig_cyc = cyc + 1;
        train_valid = 4'b0001;
        train_pc[0 +: PC_W] = 64'h0000_0000_0040_1000;
        train_addr[0 +: ADDR_W] = {8'd0, 45'h2468B, 5'd0, 6'd0};
        @(negedge clk);
        train_valid = 0;
        repeat (gap) @(posedge clk);
        if (first_cyc - trig_cyc != 2) begin
            $display("ERROR: first SMS request %0d cycles after the trigger's S1 edge (want 2)",
                     first_cyc - trig_cyc);
            err_cnt = err_cnt + 1;
        end
        if (dut_wr < first_idx + 2 || dut_q[first_idx] !== {45'h2468B, 5'd3}
            || dut_q[first_idx + 1] !== {45'h2468B, 5'd6}) begin
            $display("ERROR: README example: expected lines 3 then 6 of the new region");
            err_cnt = err_cnt + 1;
        end
        for (gen = 0; gen < ngen; gen = gen + 1) begin
            k = ($random(seed) & 32'h7fffffff) % npcs;
            region = {$random(seed), $random(seed)};
            lane = ($random(seed) & 32'h7fffffff) % NB;
            send_train(lane, pc_tab[k], region, trig_tab[k]);
            nlines = 0;
            for (j = 0; j < 32; j = j + 1) begin
                if (foot_tab[k][j] && j != trig_tab[k] && nlines < 6) begin
                    ln = j;
                    send_train(($random(seed) & 32'h7fffffff) % NB,
                               {$random(seed), $random(seed)}, region, ln);
                    nlines = nlines + 1;
                end
            end
            if ((($random(seed) & 32'h7fffffff) % 4) != 0) begin
                send_evict(($random(seed) & 32'h7fffffff) % NB, region, trig_tab[k]);
            end
            if ((($random(seed) & 32'h7fffffff) % 16) == 0) foot_tab[k] = $random(seed);
        end
        repeat (200) @(posedge clk);
        if (dut_wr != ref_wr) begin
            $display("ERROR: new made %0d requests, 7-stage %0d", dut_wr, ref_wr);
            err_cnt = err_cnt + 1;
        end
        for (i = 0; i < dut_wr && i < ref_wr; i = i + 1)
            if (dut_q[i] !== ref_q[i]) begin
                if (err_cnt < 20) $display("ERROR: request %0d new %h, 7-stage %h", i, dut_q[i], ref_q[i]);
                err_cnt = err_cnt + 1;
            end
        $display("SUMMARY sms seed=%0d generations=%0d requests: new=%0d old=%0d errors=%0d",
                 seed, ngen, dut_wr, ref_wr, err_cnt);
        if (err_cnt == 0) $display("TEST PASSED");
        else $display("TEST FAILED");
        $finish;
    end
    initial begin
        #800000000;
        $display("ERROR: time-out");
        $display("TEST FAILED");
        $finish;
    end
endmodule
`default_nettype wire
