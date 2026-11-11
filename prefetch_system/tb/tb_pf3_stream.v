`timescale 1ns/1ps
`default_nettype none
module tb_pf3_stream;
    localparam NB     = 4;
    localparam ADDR_W = 64;
    localparam PA_W   = 56;
    localparam LINE_W = 58;
    localparam DEPTH  = 4;
    localparam MAXQ   = 65536;
    reg clk;
    reg rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;
    reg  [NB-1:0]        train_valid;
    reg  [NB-1:0]        train_no_train;
    reg  [NB*ADDR_W-1:0] train_addr;
    reg  [NB-1:0]        train_is_store;
    reg  [NB-1:0]        train_miss;
    reg  [NB-1:0]        train_pf_hit;
    reg                  pf_enable;
    wire                 cand_valid;
    wire [LINE_W-1:0]    cand_line;
    wire [NB-1:0]        cand_bank;
    wire                 cand_unique;
    wire                 held;
    assign held = 1'b0;
    l1d_pf3_stream u_dut (
        .clk            (clk),
        .rst            (rst),
        .pf_enable      (pf_enable),
        .train_valid    (train_valid),
        .train_no_train (train_no_train),
        .train_addr     (train_addr),
        .train_is_store (train_is_store),
        .train_miss     (train_miss),
        .train_pf_hit   (train_pf_hit),
        .held           (held),
        .cand_valid     (cand_valid),
        .cand_line      (cand_line),
        .cand_bank      (cand_bank),
        .cand_unique    (cand_unique)
    );
    reg                  ref_valid;
    reg  [PA_W-1:0]      ref_addr;
    reg                  ref_st;
    reg                  ref_miss;
    reg                  ref_pfh;
    wire                 ref_zero;
    wire                 ref_ready;
    wire                 ref_pf_valid;
    wire [49:0]          ref_pf_line;
    wire                 ref_pf_unique;
    wire                 ref_pf_flag;
    assign ref_zero  = 1'b0;
    assign ref_ready = 1'b1;
    l1d_pf_stream u_ref (
        .clk          (clk),
        .rst          (rst),
        .pf_enable    (pf_enable),
        .tr_valid     (ref_valid),
        .tr_addr      (ref_addr),
        .tr_is_store  (ref_st),
        .tr_no_train  (ref_zero),
        .tr_miss      (ref_miss),
        .tr_pf_hit    (ref_pfh),
        .pf_ready     (ref_ready),
        .pf_valid     (ref_pf_valid),
        .pf_line_addr (ref_pf_line),
        .pf_unique    (ref_pf_unique),
        .pf_flag      (ref_pf_flag)
    );
    reg  [LINE_W:0]  dut_q [0:MAXQ-1];
    reg  [LINE_W:0]  ref_q [0:MAXQ-1];
    integer          dut_wr, ref_wr, err_cnt, cyc;
    integer          seed, nev, gap, npages, ev, lane, pick, idx, r, i, g;
    reg  [43:0]      page_tab [0:15];
    reg  [5:0]       line_tab [0:15];
    reg              st_tab   [0:15];
    reg              dir_tab  [0:15];
    reg  [63:0]      seen_line [0:15];
    integer          conf_cyc;
    integer          first_cyc;
    integer          first_idx;
    always @(posedge clk) begin
        if (!rst) begin
            cyc = cyc + 1;
            if (cand_valid) begin
                dut_q[dut_wr] = {cand_unique, cand_line};
                dut_wr = dut_wr + 1;
                if (first_cyc < 0) first_cyc = cyc;
                if (^{cand_unique, cand_line, cand_bank} === 1'bx) begin
                    $display("ERROR cycle %0d: X on the candidate", cyc);
                    err_cnt = err_cnt + 1;
                end
                if (cand_bank !== (4'b0001 << cand_line[1:0])) begin
                    $display("ERROR cycle %0d: bank %b line %h", cyc, cand_bank, cand_line);
                    err_cnt = err_cnt + 1;
                end
            end
            if (ref_pf_valid) begin
                ref_q[ref_wr] = {ref_pf_unique, 8'd0, ref_pf_line};
                ref_wr = ref_wr + 1;
            end
        end
    end
    task send_record;
        input integer lane_n;
        input [PA_W-1:0] addr;
        input st, miss, pfh;
        begin
            @(negedge clk);
            train_valid = 0; train_no_train = 0; train_miss = 0; train_pf_hit = 0;
            train_valid[lane_n] = 1'b1;
            train_addr[lane_n*ADDR_W +: ADDR_W] = {8'd0, addr};
            train_is_store[lane_n] = st;
            train_miss[lane_n] = miss;
            train_pf_hit[lane_n] = pfh;
            ref_valid = 1'b1; ref_addr = addr; ref_st = st; ref_miss = miss; ref_pfh = pfh;
            @(negedge clk);
            train_valid = 0; ref_valid = 0;
        end
    endtask
    initial begin
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        if (!$value$plusargs("NEV=%d", nev)) nev = 4000;
        if (!$value$plusargs("GAP=%d", gap)) gap = 24;
        if (!$value$plusargs("PAGES=%d", npages)) npages = 6;
        dut_wr = 0; ref_wr = 0; err_cnt = 0; cyc = 0; first_cyc = -1;
        rst = 1; pf_enable = 1;
        train_valid = 0; train_no_train = 0; train_addr = 0; train_is_store = 0;
        train_miss = 0; train_pf_hit = 0;
        ref_valid = 0; ref_addr = 0; ref_st = 0; ref_miss = 0; ref_pfh = 0;
        repeat (4) @(posedge clk);
        rst = 0;
        send_record(2, {44'h12345, 6'd50, 6'd0}, 1'b0, 1'b1, 1'b0);
        repeat (10) @(posedge clk);
        send_record(1, {44'h12345, 6'd51, 6'd0}, 1'b0, 1'b1, 1'b0);
        repeat (10) @(posedge clk);
        first_cyc = -1;
        first_idx = dut_wr;
        conf_cyc = cyc + 1;
        send_record(0, {44'h12345, 6'd52, 6'd0}, 1'b0, 1'b1, 1'b0);
        repeat (20) @(posedge clk);
        if (first_cyc - conf_cyc != 2) begin
            $display("ERROR: first request %0d cycles after the record's S1 edge (want 2)",
                     first_cyc - conf_cyc);
            err_cnt = err_cnt + 1;
        end
        if (dut_wr <= first_idx || dut_q[first_idx] !== {1'b0, 8'd0, 44'h12345, 6'd53}) begin
            $display("ERROR: first request is not line 53");
            err_cnt = err_cnt + 1;
        end
        for (i = 0; i < 16; i = i + 1) begin
            page_tab[i] = {$random(seed), $random(seed)};
            line_tab[i] = $random(seed);
            st_tab[i]   = (i % 4 == 1);
            dir_tab[i]  = (i % 3 != 2);
            seen_line[i] = 0;
        end
        ev = 0;
        while (ev < nev) begin
            idx = ($random(seed) & 32'h7fffffff) % npages;
            r = ($random(seed) & 32'h7fffffff) % 100;
            if (r < 8) line_tab[idx] = $random(seed);
            else if (r < 12) line_tab[idx] = line_tab[idx];
            else if (r < 16) dir_tab[idx] = ~dir_tab[idx];
            else line_tab[idx] = dir_tab[idx] ? line_tab[idx] + 1 : line_tab[idx] - 1;
            if (r > 95) page_tab[idx] = {$random(seed), $random(seed)};
            seen_line[idx] = (r > 95) ? 64'd0 : seen_line[idx];
            seen_line[idx][line_tab[idx]] = 1'b1;
            send_record(($random(seed) & 32'h7fffffff) % NB, {page_tab[idx], line_tab[idx], 6'd0},
                        st_tab[idx], (($random(seed) & 32'h7fffffff) % 4 != 0),
                        (($random(seed) & 32'h7fffffff) % 6 == 0));
            for (g = 0; g < gap; g = g + 1) @(posedge clk);
            ev = ev + 1;
        end
        repeat (60) @(posedge clk);
        if (gap >= 24) begin
            if (dut_wr != ref_wr) begin
                $display("ERROR: new made %0d requests, 5-stage %0d", dut_wr, ref_wr);
                err_cnt = err_cnt + 1;
            end
            for (i = 0; i < dut_wr && i < ref_wr; i = i + 1)
                if (dut_q[i] !== ref_q[i]) begin
                    if (err_cnt < 20) $display("ERROR: request %0d new %h, 5-stage %h", i, dut_q[i], ref_q[i]);
                    err_cnt = err_cnt + 1;
                end
        end
        $display("SUMMARY stream seed=%0d events=%0d gap=%0d requests: new=%0d old=%0d errors=%0d",
                 seed, nev, gap, dut_wr, ref_wr, err_cnt);
        if (err_cnt == 0) $display("TEST PASSED");
        else $display("TEST FAILED");
        $finish;
    end
    initial begin
        #400000000;
        $display("ERROR: time-out");
        $display("TEST FAILED");
        $finish;
    end
endmodule
`default_nettype wire
