`timescale 1ns/1ps
`default_nettype none
module tb_pf3_stride;
    localparam NB       = 4;
    localparam PC_W     = 64;
    localparam ADDR_W   = 64;
    localparam PA_W     = 56;
    localparam NS       = 16;
    localparam NW       = 4;
    localparam TAG_W    = 12;
    localparam PH_W     = 10;
    localparam PAGE_W   = 12;
    localparam OFFSET_W = 6;
    localparam LIP_W    = 6;
    localparam PPN_W    = 44;
    localparam LINE_W   = 58;
    localparam FILT     = 4;
    localparam MAXQ     = 65536;
    reg clk;
    reg rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;
    reg  [NB-1:0]        train_valid;
    reg  [NB-1:0]        train_no_train;
    reg  [NB-1:0]        train_is_store;
    reg  [NB*PC_W-1:0]   train_pc;
    reg  [NB*ADDR_W-1:0] train_addr;
    wire                 cand_valid;
    wire [LINE_W-1:0]    cand_line;
    wire [NB-1:0]        cand_bank;
    wire                 cand_unique;
    reg                  pf_enable;
    reg                  clear;
    l1d_pf3_stride u_dut (
        .clk            (clk),
        .rst            (rst),
        .pf_enable      (pf_enable),
        .clear          (clear),
        .train_valid    (train_valid),
        .train_no_train (train_no_train),
        .train_is_store (train_is_store),
        .train_pc       (train_pc),
        .train_addr     (train_addr),
        .cand_valid     (cand_valid),
        .cand_line      (cand_line),
        .cand_bank      (cand_bank),
        .cand_unique    (cand_unique)
    );
    reg                  ref_valid;
    reg  [PC_W-1:0]      ref_pc;
    reg  [PA_W-1:0]      ref_pa;
    reg                  ref_st;
    wire                 ref_pf_valid;
    wire [ADDR_W-1:0]    ref_pf_addr;
    wire                 ref_pf_unique;
    wire                 ref_ready;
    assign ref_ready = 1'b1;
    l1d_pf_stride u_ref (
        .rst         (rst),
        .clk         (clk),
        .clear       (clear),
        .tr_valid    (ref_valid),
        .tr_pc       (ref_pc),
        .tr_pa       (ref_pa),
        .tr_is_store (ref_st),
        .pf_ready    (ref_ready),
        .pf_valid    (ref_pf_valid),
        .pf_addr     (ref_pf_addr),
        .pf_unique   (ref_pf_unique)
    );
    reg                  m_valid  [0:NS*NW-1];
    reg                  m_st     [0:NS*NW-1];
    reg  [TAG_W-1:0]     m_tag    [0:NS*NW-1];
    reg  [1:0]           m_state  [0:NS*NW-1];
    reg  [12:0]          m_stride [0:NS*NW-1];
    reg  [11:0]          m_lo     [0:NS*NW-1];
    reg  [PH_W-1:0]      m_ph     [0:NS*NW-1];
    reg  [FILT-1:0]      m_fv;
    reg  [PH_W-1:0]      m_fph    [0:FILT-1];
    reg  [LIP_W-1:0]     m_flip   [0:FILT-1];
    reg  [LINE_W:0]      exp_q    [0:MAXQ-1];
    reg  [31:0]          exp_t    [0:MAXQ-1];
    integer              exp_wr, exp_rd;
    reg  [LINE_W:0]      ref_q    [0:MAXQ-1];
    integer              ref_wr;
    integer              dut_cnt, err_cnt, cyc;
    integer              lat_bad;
    integer              seed, nev, rate, npcs, sameset, use_ref;
    reg  [PC_W-1:0]      pc_tab   [0:31];
    reg  [12:0]          str_tab  [0:31];
    reg  [PA_W-1:0]      addr_tab [0:31];
    reg                  st_tab   [0:31];
    integer              ev, i, k, lane, pick, idx, r;
    function [TAG_W-1:0] fold_tag;
        input [PC_W-1:0] pc;
        integer b;
        reg [TAG_W-1:0] t;
        begin
            t = 0;
            for (b = 0; b < PC_W - 5; b = b + 1) t[b % TAG_W] = t[b % TAG_W] ^ pc[5 + b];
            fold_tag = t;
        end
    endfunction
    function [PH_W-1:0] fold_ph;
        input [PA_W-1:0] pa;
        integer b;
        reg [PH_W-1:0] t;
        begin
            t = 0;
            for (b = 0; b < PPN_W; b = b + 1) t[b % PH_W] = t[b % PH_W] ^ pa[12 + b];
            fold_ph = t;
        end
    endfunction
    function [2:0] cls_of;
        input integer e;
        begin
            if (!m_valid[e]) cls_of = 0;
            else case (m_state[e])
                2'd3: cls_of = 1;
                2'd0: cls_of = 2;
                2'd1: cls_of = 3;
                default: cls_of = 4;
            endcase
        end
    endfunction
    task model_event;
        input [PC_W-1:0] pc;
        input [PA_W-1:0] pa;
        input            st;
        input [31:0]     tcyc;
        integer set, w, e, hitw, vic, f;
        reg [TAG_W-1:0] tag;
        reg [PH_W-1:0] ph;
        reg [11:0] lo;
        reg sp, correct, keep, issue, dup, inpage;
        reg [12:0] dl, es, nxs;
        reg [1:0] estate, nxst;
        reg [14:0] tgt;
        reg [LIP_W-1:0] lip;
        reg [2:0] bc;
        begin
            set = pc[4:1];
            tag = fold_tag(pc);
            ph  = fold_ph(pa);
            lo  = pa[11:0];
            hitw = -1;
            for (w = 0; w < NW; w = w + 1) begin
                e = set * NW + w;
                if (m_valid[e] && m_tag[e] == tag && m_st[e] == st) hitw = w;
            end
            if (hitw < 0) begin
                vic = 0; bc = 7;
                for (w = 0; w < NW; w = w + 1) begin
                    if (cls_of(set * NW + w) < bc) begin
                        bc = cls_of(set * NW + w); vic = w;
                    end
                end
                e = set * NW + vic;
                m_valid[e] = 1; m_st[e] = st; m_tag[e] = tag; m_state[e] = 2'd0;
                m_stride[e] = 0; m_lo[e] = lo; m_ph[e] = ph;
            end
            else begin
                e = set * NW + hitw;
                es = m_stride[e]; estate = m_state[e];
                sp = (ph == m_ph[e]);
                dl = {1'b0, lo} - {1'b0, m_lo[e]};
                correct = sp && (dl == es);
                keep = correct || (estate == 2'd2);
                nxs = keep ? es : (sp ? dl : 13'd0);
                case (estate)
                    2'd0: nxst = correct ? 2'd2 : 2'd1;
                    2'd1: nxst = correct ? 2'd2 : 2'd3;
                    2'd2: nxst = correct ? 2'd2 : 2'd0;
                    default: nxst = correct ? 2'd1 : 2'd3;
                endcase
                issue = correct && (estate != 2'd3) && (es != 0);
                m_stride[e] = nxs; m_state[e] = nxst; m_lo[e] = lo; m_ph[e] = ph;
                if (issue) begin
                    tgt = {3'b000, lo} + ({{2{es[12]}}, es} << 1);
                    inpage = (tgt[14:12] == 3'b000);
                    lip = tgt[11:6];
                    dup = 0;
                    for (f = 0; f < FILT; f = f + 1)
                        if (m_fv[f] && m_fph[f] == ph && m_flip[f] == lip) dup = 1;
                    if (inpage && !dup && lip != lo[11:6]) begin
                        exp_q[exp_wr] = {st, 8'd0, pa[55:12], lip};
                        exp_t[exp_wr] = tcyc;
                        exp_wr = exp_wr + 1;
                        for (f = FILT - 1; f > 0; f = f - 1) begin
                            m_fv[f] = m_fv[f-1]; m_fph[f] = m_fph[f-1]; m_flip[f] = m_flip[f-1];
                        end
                        m_fv[0] = 1; m_fph[0] = ph; m_flip[0] = lip;
                    end
                end
            end
        end
    endtask
    always @(posedge clk) begin
        if (!rst) begin
            cyc = cyc + 1;
            if (cand_valid) begin
                if (exp_rd >= exp_wr) begin
                    $display("ERROR cycle %0d: DUT request %h, model has none", cyc, cand_line);
                    err_cnt = err_cnt + 1;
                end
                else begin
                    if ({cand_unique, cand_line} !== exp_q[exp_rd]) begin
                        $display("ERROR cycle %0d: DUT %b %h, model %b %h", cyc, cand_unique, cand_line,
                                 exp_q[exp_rd][LINE_W], exp_q[exp_rd][LINE_W-1:0]);
                        err_cnt = err_cnt + 1;
                    end
                    if (cyc - exp_t[exp_rd] != 2) lat_bad = lat_bad + 1;
                    if (cand_bank !== (4'b0001 << cand_line[1:0])) begin
                        $display("ERROR cycle %0d: bank %b for line %h", cyc, cand_bank, cand_line);
                        err_cnt = err_cnt + 1;
                    end
                    exp_rd = exp_rd + 1;
                end
                dut_cnt = dut_cnt + 1;
            end
            if (ref_pf_valid) begin
                ref_q[ref_wr] = {ref_pf_unique, ref_pf_addr[63:6]};
                ref_wr = ref_wr + 1;
            end
        end
    end
    initial begin
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        if (!$value$plusargs("NEV=%d", nev)) nev = 20000;
        if (!$value$plusargs("RATE=%d", rate)) rate = 70;
        if (!$value$plusargs("PCS=%d", npcs)) npcs = 12;
        if (!$value$plusargs("SAMESET=%d", sameset)) sameset = 0;
        if (!$value$plusargs("REF=%d", use_ref)) use_ref = 1;
        exp_wr = 0; exp_rd = 0; ref_wr = 0; dut_cnt = 0; err_cnt = 0; cyc = 0; lat_bad = 0;
        m_fv = 0;
        for (i = 0; i < NS * NW; i = i + 1) begin
            m_valid[i] = 0; m_state[i] = 0; m_st[i] = 0; m_tag[i] = 0; m_stride[i] = 0;
            m_lo[i] = 0; m_ph[i] = 0;
        end
        for (i = 0; i < 32; i = i + 1) begin
            r = $random(seed);
            pc_tab[i] = {$random(seed), $random(seed)};
            pc_tab[i][0] = 1'b0;
            if (sameset != 0) pc_tab[i][4:1] = i % 2;
            else pc_tab[i][4:1] = i % 16;
            case (i % 8)
                0: str_tab[i] = 13'd64;
                1: str_tab[i] = 13'd8;
                2: str_tab[i] = -13'sd128;
                3: str_tab[i] = 13'd192;
                4: str_tab[i] = 13'd0;
                5: str_tab[i] = 13'd4000;
                6: str_tab[i] = 13'd4;
                default: str_tab[i] = -13'sd64;
            endcase
            addr_tab[i] = {$random(seed), $random(seed)};
            st_tab[i] = (i % 5 == 3);
        end
        rst = 1; pf_enable = 1; clear = 0;
        train_valid = 0; train_no_train = 0; train_is_store = 0; train_pc = 0; train_addr = 0;
        ref_valid = 0; ref_pc = 0; ref_pa = 0; ref_st = 0;
        repeat (4) @(posedge clk);
        rst = 0;
        ev = 0;
        while (ev < nev) begin
            @(negedge clk);
            train_valid = 0; train_no_train = 0; ref_valid = 0;
            if (($random(seed) & 32'h7fffffff) % 100 < rate) begin
                pick = -1;
                for (lane = 0; lane < NB; lane = lane + 1) begin
                    if ((($random(seed) & 32'h7fffffff) % 3 == 0) || (lane == NB - 1 && pick < 0)) begin
                        idx = ($random(seed) & 32'h7fffffff) % npcs;
                        r = ($random(seed) & 32'h7fffffff) % 100;
                        if (r < 4) addr_tab[idx] = {$random(seed), $random(seed)};
                        else if (r < 6) addr_tab[idx][11:0] = $random(seed);
                        else addr_tab[idx] = addr_tab[idx] + {{(PA_W-13){str_tab[idx][12]}}, str_tab[idx]};
                        train_valid[lane] = 1'b1;
                        train_no_train[lane] = (($random(seed) & 32'h7fffffff) % 10 == 0);
                        train_is_store[lane] = st_tab[idx];
                        train_pc[lane*PC_W +: PC_W] = pc_tab[idx];
                        train_addr[lane*ADDR_W +: ADDR_W] = {8'd0, addr_tab[idx]};
                        if (pick < 0 && !train_no_train[lane]) pick = lane;
                    end
                end
                if (pick >= 0) begin
                    model_event(train_pc[pick*PC_W +: PC_W], train_addr[pick*ADDR_W +: PA_W],
                                train_is_store[pick], cyc + 1);
                    ref_valid = 1'b1;
                    ref_pc = train_pc[pick*PC_W +: PC_W];
                    ref_pa = train_addr[pick*ADDR_W +: PA_W];
                    ref_st = train_is_store[pick];
                    ev = ev + 1;
                end
            end
        end
        @(negedge clk);
        train_valid = 0; ref_valid = 0;
        repeat (40) @(posedge clk);
        if (exp_rd != exp_wr) begin
            $display("ERROR: model has %0d requests the DUT never made", exp_wr - exp_rd);
            err_cnt = err_cnt + 1;
        end
        if (lat_bad != 0) begin
            $display("ERROR: %0d requests not 2 cycles after their record (S3)", lat_bad);
            err_cnt = err_cnt + 1;
        end
        if (use_ref != 0) begin
            if (ref_wr != exp_wr) begin
                $display("ERROR: 9-stage RTL made %0d requests, model %0d", ref_wr, exp_wr);
                err_cnt = err_cnt + 1;
            end
            else begin
                for (i = 0; i < ref_wr; i = i + 1)
                    if (ref_q[i] !== exp_q[i]) begin
                        if (err_cnt < 20) $display("ERROR: 9-stage request %0d %h, model %h", i, ref_q[i], exp_q[i]);
                        err_cnt = err_cnt + 1;
                    end
            end
        end
        $display("SUMMARY stride seed=%0d events=%0d requests: dut=%0d model=%0d ref=%0d errors=%0d",
                 seed, nev, dut_cnt, exp_wr, ref_wr, err_cnt);
        if (err_cnt == 0) $display("TEST PASSED");
        else $display("TEST FAILED");
        $finish;
    end
    initial begin
        #200000000;
        $display("ERROR: time-out");
        $display("TEST FAILED");
        $finish;
    end
endmodule
`default_nettype wire
