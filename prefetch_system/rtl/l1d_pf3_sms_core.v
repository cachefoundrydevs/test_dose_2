`ifndef L1D_PF3_SMS_CORE_V
`define L1D_PF3_SMS_CORE_V
`default_nettype none
module l1d_pf3_sms_core #(
    parameter NB               = 4,
    parameter PC_W             = 64,
    parameter ADDR_W           = 64,
    parameter PA_W             = 56,
    parameter LINE_BYTES       = 64,
    parameter LINE_W           = 58,
    parameter REGION_BYTES     = 2048,
    parameter FT_ENTRIES       = 16,
    parameter AT_ENTRIES       = 32,
    parameter PHT_SETS         = 32,
    parameter PHT_WAYS         = 4,
    parameter REGION_TAG_W     = 16,
    parameter PC_HASH_W        = 12,
    parameter PHT_TAG_W        = 8,
    parameter TRAIN_FIFO_DEPTH = 4,
    parameter EVT_FIFO_DEPTH   = 4
) (
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      pf_enable,
    input  wire [NB-1:0]             train_valid,
    input  wire [NB-1:0]             train_no_train,
    input  wire [NB*PC_W-1:0]        train_pc,
    input  wire [NB*ADDR_W-1:0]      train_addr,
    input  wire [NB-1:0]             evict_valid,
    input  wire [NB*LINE_W-1:0]      evict_line_addr,
    output wire                      load_valid,
    output wire [PA_W-$clog2(LINE_BYTES)-$clog2(REGION_BYTES/LINE_BYTES)-1:0]
                                     load_region,
    output wire [$clog2(REGION_BYTES/LINE_BYTES)-1:0] load_line,
    output wire [$clog2(REGION_BYTES/LINE_BYTES)-1:0] load_first,
    output wire [NB-1:0]             load_first_bank,
    output wire [(REGION_BYTES/LINE_BYTES)-1:0] load_rest
);
    localparam OFFSET_W     = $clog2(LINE_BYTES);
    localparam PLINE_W      = PA_W - OFFSET_W;
    localparam LIR_W        = $clog2(REGION_BYTES / LINE_BYTES);
    localparam REGION_NUM_W = PLINE_W - LIR_W;
    localparam PATTERN_W    = (1 << LIR_W);
    localparam KEY_W        = PC_HASH_W + LIR_W;
    localparam SET_W        = $clog2(PHT_SETS);
    localparam WAY_W        = $clog2(PHT_WAYS);
    localparam FT_IDX_W     = $clog2(FT_ENTRIES);
    localparam AT_IDX_W     = $clog2(AT_ENTRIES);
    localparam PHT_TOTAL    = PHT_SETS * PHT_WAYS;
    localparam PORT_W       = $clog2(NB);
    localparam BANK_W       = $clog2(NB);
    localparam TREC_W = REGION_NUM_W + LIR_W + REGION_TAG_W + SET_W
                        + PHT_TAG_W;
    localparam EREC_W = REGION_NUM_W + LIR_W + REGION_TAG_W;
    localparam [PORT_W-1:0] PORT_LAST = NB - 1;
    reg  [NB*PC_HASH_W-1:0]  lane_pch;
    reg  [NB*REGION_TAG_W-1:0] lane_rtag;
    reg  [NB*SET_W-1:0]      lane_set;
    reg  [NB*PHT_TAG_W-1:0]  lane_ptag;
    reg  [NB*REGION_TAG_W-1:0] evl_rtag;
    reg  [KEY_W-1:0]         lane_key;
    reg  [PC_HASH_W-1:0]     pch_one;
    reg  [REGION_NUM_W-1:0]  region_one;
    reg  [NB-1:0]            tr_ok;
    reg  [NB-1:0]            tr_pick;
    reg  [NB-1:0]            ev_pick;
    reg                      tr_seen;
    reg                      ev_seen;
    reg  [PORT_W-1:0]        rot_idx;
    reg  [TREC_W-1:0]        tr_word;
    reg  [EREC_W-1:0]        ev_word;
    reg                      tr_fresh;
    reg                      ev_fresh;
    reg  [PORT_W-1:0]        train_rot_q;
    reg  [PORT_W-1:0]        evt_rot_q;
    wire                     tq_vld;
    wire [TREC_W-1:0]        tq_head;
    wire                     eq_vld;
    wire [EREC_W-1:0]        eq_head;
    wire                     tr_avail;
    wire                     ev_avail;
    wire                     take_evt;
    wire                     take_tr;
    wire                     tq_push;
    wire                     eq_push;
    wire                     tq_pop;
    wire                     eq_pop;
    wire [TREC_W-1:0]        tr_src;
    wire [EREC_W-1:0]        ev_src;
    reg                      prefer_evt_q;
    reg                      e1_vld;
    reg                      e1_evt;
    reg  [REGION_NUM_W-1:0]  e1_region;
    reg  [LIR_W-1:0]         e1_line;
    reg  [REGION_TAG_W-1:0]  e1_rtag;
    reg  [SET_W-1:0]         e1_set;
    reg  [PHT_TAG_W-1:0]     e1_ptag;
    reg  [FT_ENTRIES-1:0]               ft_vld;
    reg  [FT_ENTRIES*REGION_TAG_W-1:0]  ft_tag;
    reg  [FT_ENTRIES*LIR_W-1:0]         ft_line;
    reg  [FT_ENTRIES*SET_W-1:0]         ft_pset;
    reg  [FT_ENTRIES*PHT_TAG_W-1:0]     ft_ptag;
    reg  [FT_IDX_W-1:0]                 ft_ring;
    reg  [AT_ENTRIES-1:0]               at_vld;
    reg  [AT_ENTRIES*REGION_TAG_W-1:0]  at_tag;
    reg  [AT_ENTRIES*LIR_W-1:0]         at_line;
    reg  [AT_ENTRIES*SET_W-1:0]         at_pset;
    reg  [AT_ENTRIES*PHT_TAG_W-1:0]     at_ptag;
    reg  [AT_ENTRIES*PATTERN_W-1:0]     at_pat;
    reg  [AT_IDX_W-1:0]                 at_ring;
    reg  [PHT_TOTAL-1:0]                pht_vld;
    reg  [PHT_TOTAL*PHT_TAG_W-1:0]      pht_tag;
    reg  [PHT_TOTAL*LIR_W-1:0]          pht_line;
    reg  [PHT_TOTAL*PATTERN_W-1:0]      pht_rest;
    reg  [PHT_TOTAL*LIR_W-1:0]          pht_first;
    reg  [PHT_TOTAL*NB-1:0]             pht_fbank;
    reg  [PHT_TOTAL-1:0]                pht_nz;
    reg  [PHT_SETS*WAY_W-1:0]           pht_ptr;
    reg  [FT_ENTRIES-1:0]    ft_hit;
    reg  [AT_ENTRIES-1:0]    at_hit;
    reg  [AT_ENTRIES-1:0]    at_has_line;
    wire                     any_ft;
    wire                     any_at;
    reg  [LIR_W-1:0]         ft_rd_line;
    reg  [SET_W-1:0]         ft_rd_pset;
    reg  [PHT_TAG_W-1:0]     ft_rd_ptag;
    reg  [LIR_W-1:0]         at_rd_line;
    reg  [SET_W-1:0]         at_rd_pset;
    reg  [PHT_TAG_W-1:0]     at_rd_ptag;
    reg  [PATTERN_W-1:0]     at_rd_pat;
    reg                      at_rd_has;
    reg  [FT_ENTRIES-1:0]    ft_vic;
    reg  [AT_ENTRIES-1:0]    at_vic;
    reg                      ft_free_seen;
    reg                      at_free_seen;
    reg                      vic_vld;
    reg  [LIR_W-1:0]         vic_line;
    reg  [SET_W-1:0]         vic_pset;
    reg  [PHT_TAG_W-1:0]     vic_ptag;
    reg  [PATTERN_W-1:0]     vic_pat;
    wire [PATTERN_W-1:0]     line_oh;
    wire [PATTERN_W-1:0]     ft_line_oh;
    wire                     do_at_set;
    wire                     do_promote;
    wire                     do_trigger;
    wire                     do_end_gen;
    wire                     do_ft_discard;
    wire                     pw_req;
    reg  [PHT_TOTAL-1:0]     pht_hit;
    wire [PHT_SETS-1:0]      e1_set1h;
    reg                      pht_any;
    reg  [LIR_W-1:0]         rd_first;
    reg  [NB-1:0]            rd_fbank;
    reg  [PATTERN_W-1:0]     rd_rest;
    reg                      w_vld;
    reg  [SET_W-1:0]         w_set;
    reg  [PHT_TAG_W-1:0]     w_ptag;
    reg  [LIR_W-1:0]         w_line;
    reg  [PATTERN_W-1:0]     w_pat;
    reg  [PHT_SETS-1:0]      w_set1h;
    reg  [PHT_TOTAL-1:0]     w_tmatch;
    reg  [PATTERN_W-1:0]     w_all;
    reg  [PATTERN_W-1:0]     w_high;
    reg  [PATTERN_W-1:0]     w_above;
    reg  [PATTERN_W-1:0]     w_ffs_above;
    reg  [PATTERN_W-1:0]     w_ffs_all;
    reg  [PATTERN_W-1:0]     w_first_oh;
    reg  [LIR_W-1:0]         w_first;
    reg  [NB-1:0]            w_fbank;
    reg                      w_seen_a;
    reg                      w_seen_b;
    reg  [LIR_W-1:0]         bit_number;
    reg                      x_vld;
    reg  [PHT_SETS-1:0]      x_set1h;
    reg  [PHT_TAG_W-1:0]     x_ptag;
    reg  [LIR_W-1:0]         x_line;
    reg  [PATTERN_W-1:0]     x_rest;
    reg  [LIR_W-1:0]         x_first;
    reg  [NB-1:0]            x_fbank;
    reg                      x_nz;
    reg  [PHT_TOTAL-1:0]     x_tmatch;
    reg  [PHT_TOTAL-1:0]     x_write;
    reg  [PHT_SETS-1:0]      x_adv;
    reg  [PHT_WAYS-1:0]      x_m;
    reg  [PHT_WAYS-1:0]      x_f;
    reg  [PHT_WAYS-1:0]      x_pick;
    reg                      x_seen;
    reg  [WAY_W-1:0]         x_ptr;
    always @* begin : hash_proc
        integer lane_idx;
        integer bit_idx;
        lane_pch  = {(NB*PC_HASH_W){1'b0}};
        lane_rtag = {(NB*REGION_TAG_W){1'b0}};
        lane_set  = {(NB*SET_W){1'b0}};
        lane_ptag = {(NB*PHT_TAG_W){1'b0}};
        evl_rtag  = {(NB*REGION_TAG_W){1'b0}};
        for (lane_idx = 0; lane_idx < NB; lane_idx = lane_idx + 1) begin
            pch_one = {PC_HASH_W{1'b0}};
            for (bit_idx = 0; bit_idx < PC_W; bit_idx = bit_idx + 1) begin
                pch_one[bit_idx % PC_HASH_W] = pch_one[bit_idx % PC_HASH_W]
                    ^ train_pc[lane_idx*PC_W + bit_idx];
            end
            lane_pch[lane_idx*PC_HASH_W +: PC_HASH_W] = pch_one;
            region_one = train_addr[lane_idx*ADDR_W + OFFSET_W + LIR_W +: REGION_NUM_W];
            for (bit_idx = 0; bit_idx < REGION_NUM_W; bit_idx = bit_idx + 1) begin
                lane_rtag[lane_idx*REGION_TAG_W + (bit_idx % REGION_TAG_W)] =
                    lane_rtag[lane_idx*REGION_TAG_W + (bit_idx % REGION_TAG_W)]
                    ^ region_one[bit_idx];
            end
            lane_key = {pch_one, train_addr[lane_idx*ADDR_W + OFFSET_W +: LIR_W]};
            for (bit_idx = 0; bit_idx < KEY_W; bit_idx = bit_idx + 1) begin
                lane_set[lane_idx*SET_W + (bit_idx % SET_W)] =
                    lane_set[lane_idx*SET_W + (bit_idx % SET_W)]
                    ^ lane_key[bit_idx];
                lane_ptag[lane_idx*PHT_TAG_W + ((bit_idx + 3) % PHT_TAG_W)] =
                    lane_ptag[lane_idx*PHT_TAG_W + ((bit_idx + 3) % PHT_TAG_W)]
                    ^ lane_key[bit_idx];
            end
            region_one = evict_line_addr[lane_idx*LINE_W + LIR_W +: REGION_NUM_W];
            for (bit_idx = 0; bit_idx < REGION_NUM_W; bit_idx = bit_idx + 1) begin
                evl_rtag[lane_idx*REGION_TAG_W + (bit_idx % REGION_TAG_W)] =
                    evl_rtag[lane_idx*REGION_TAG_W + (bit_idx % REGION_TAG_W)]
                    ^ region_one[bit_idx];
            end
        end
    end
    always @* begin : pick_proc
        integer lane_idx;
        integer scan_idx;
        tr_ok   = train_valid & ~train_no_train & {NB{pf_enable}};
        tr_pick = {NB{1'b0}};
        ev_pick = {NB{1'b0}};
        tr_seen = 1'b0;
        ev_seen = 1'b0;
        for (scan_idx = 0; scan_idx < NB; scan_idx = scan_idx + 1) begin
            rot_idx = scan_idx[PORT_W-1:0] + train_rot_q;
            if (tr_ok[rot_idx] && !tr_seen) begin
                tr_pick[rot_idx] = 1'b1;
                tr_seen          = 1'b1;
            end
            rot_idx = scan_idx[PORT_W-1:0] + evt_rot_q;
            if (evict_valid[rot_idx] && pf_enable && !ev_seen) begin
                ev_pick[rot_idx] = 1'b1;
                ev_seen          = 1'b1;
            end
        end
        tr_fresh = tr_seen;
        ev_fresh = ev_seen;
        tr_word  = {TREC_W{1'b0}};
        ev_word  = {EREC_W{1'b0}};
        for (lane_idx = 0; lane_idx < NB; lane_idx = lane_idx + 1) begin
            tr_word = tr_word | ({TREC_W{tr_pick[lane_idx]}} & {
                train_addr[lane_idx*ADDR_W + OFFSET_W + LIR_W +: REGION_NUM_W],
                train_addr[lane_idx*ADDR_W + OFFSET_W +: LIR_W],
                lane_rtag[lane_idx*REGION_TAG_W +: REGION_TAG_W],
                lane_set[lane_idx*SET_W +: SET_W],
                lane_ptag[lane_idx*PHT_TAG_W +: PHT_TAG_W]});
            ev_word = ev_word | ({EREC_W{ev_pick[lane_idx]}} & {
                evict_line_addr[lane_idx*LINE_W + LIR_W +: REGION_NUM_W],
                evict_line_addr[lane_idx*LINE_W +: LIR_W],
                evl_rtag[lane_idx*REGION_TAG_W +: REGION_TAG_W]});
        end
    end
    always @(posedge clk) begin : rotation_proc
        if (rst) begin
            train_rot_q <= {PORT_W{1'b0}};
            evt_rot_q   <= {PORT_W{1'b0}};
        end
        else begin
            train_rot_q <= (train_rot_q == PORT_LAST) ? {PORT_W{1'b0}}
                                                      : train_rot_q + 1'b1;
            evt_rot_q   <= (evt_rot_q == PORT_LAST) ? {PORT_W{1'b0}}
                                                    : evt_rot_q + 1'b1;
        end
    end
    assign tr_avail = tq_vld | tr_fresh;
    assign ev_avail = eq_vld | ev_fresh;
    assign take_evt = ev_avail & (~tr_avail | prefer_evt_q);
    assign take_tr  = tr_avail & ~take_evt;
    assign tr_src   = tq_vld ? tq_head : tr_word;
    assign ev_src   = eq_vld ? eq_head : ev_word;
    assign tq_pop   = take_tr & tq_vld;
    assign eq_pop   = take_evt & eq_vld;
    assign tq_push  = tr_fresh & ~(take_tr & ~tq_vld);
    assign eq_push  = ev_fresh & ~(take_evt & ~eq_vld);
    l1d_pf_sms_fifo #(
        .WIDTH (TREC_W),
        .DEPTH (TRAIN_FIFO_DEPTH)
    ) u_train_fifo (
        .clk        (clk),
        .rst        (rst),
        .push_valid (tq_push),
        .push_data  (tr_word),
        .pop_en     (tq_pop),
        .head_valid (tq_vld),
        .head_data  (tq_head)
    );
    l1d_pf_sms_fifo #(
        .WIDTH (EREC_W),
        .DEPTH (EVT_FIFO_DEPTH)
    ) u_evict_fifo (
        .clk        (clk),
        .rst        (rst),
        .push_valid (eq_push),
        .push_data  (ev_word),
        .pop_en     (eq_pop),
        .head_valid (eq_vld),
        .head_data  (eq_head)
    );
    always @(posedge clk) begin : s1_reg_proc
        if (rst) begin
            prefer_evt_q <= 1'b0;
            e1_vld       <= 1'b0;
        end
        else begin
            if (tr_avail && ev_avail) begin
                prefer_evt_q <= ~prefer_evt_q;
            end
            e1_vld <= (take_tr | take_evt) & pf_enable;
        end
        e1_evt <= take_evt;
        if (take_evt) begin
            {e1_region, e1_line, e1_rtag} <= ev_src;
        end
        else begin
            {e1_region, e1_line, e1_rtag, e1_set, e1_ptag} <= tr_src;
        end
    end
    assign line_oh = {{(PATTERN_W-1){1'b0}}, 1'b1} << e1_line;
    genvar set_g;
    generate
        for (set_g = 0; set_g < PHT_SETS; set_g = set_g + 1) begin : g_set1h
            assign e1_set1h[set_g] = (e1_set == set_g);
        end
    endgenerate
    always @* begin : s2_cam_proc
        integer ent_idx;
        for (ent_idx = 0; ent_idx < FT_ENTRIES; ent_idx = ent_idx + 1) begin
            ft_hit[ent_idx] = ft_vld[ent_idx]
                & (ft_tag[ent_idx*REGION_TAG_W +: REGION_TAG_W] == e1_rtag);
        end
        for (ent_idx = 0; ent_idx < AT_ENTRIES; ent_idx = ent_idx + 1) begin
            at_hit[ent_idx] = at_vld[ent_idx]
                & (at_tag[ent_idx*REGION_TAG_W +: REGION_TAG_W] == e1_rtag);
            at_has_line[ent_idx] =
                |(at_pat[ent_idx*PATTERN_W +: PATTERN_W] & line_oh);
        end
        for (ent_idx = 0; ent_idx < PHT_TOTAL; ent_idx = ent_idx + 1) begin
            pht_hit[ent_idx] = pht_vld[ent_idx] & e1_set1h[ent_idx / PHT_WAYS]
                & (pht_tag[ent_idx*PHT_TAG_W +: PHT_TAG_W] == e1_ptag)
                & (pht_line[ent_idx*LIR_W +: LIR_W] == e1_line)
                & pht_nz[ent_idx];
        end
    end
    assign any_ft = |ft_hit;
    assign any_at = |at_hit;
    always @* begin : s2_read_proc
        integer ent_idx;
        ft_rd_line = {LIR_W{1'b0}};
        ft_rd_pset = {SET_W{1'b0}};
        ft_rd_ptag = {PHT_TAG_W{1'b0}};
        for (ent_idx = 0; ent_idx < FT_ENTRIES; ent_idx = ent_idx + 1) begin
            ft_rd_line = ft_rd_line | ({LIR_W{ft_hit[ent_idx]}}
                         & ft_line[ent_idx*LIR_W +: LIR_W]);
            ft_rd_pset = ft_rd_pset | ({SET_W{ft_hit[ent_idx]}}
                         & ft_pset[ent_idx*SET_W +: SET_W]);
            ft_rd_ptag = ft_rd_ptag | ({PHT_TAG_W{ft_hit[ent_idx]}}
                         & ft_ptag[ent_idx*PHT_TAG_W +: PHT_TAG_W]);
        end
        at_rd_line = {LIR_W{1'b0}};
        at_rd_pset = {SET_W{1'b0}};
        at_rd_ptag = {PHT_TAG_W{1'b0}};
        at_rd_pat  = {PATTERN_W{1'b0}};
        at_rd_has  = 1'b0;
        for (ent_idx = 0; ent_idx < AT_ENTRIES; ent_idx = ent_idx + 1) begin
            at_rd_line = at_rd_line | ({LIR_W{at_hit[ent_idx]}}
                         & at_line[ent_idx*LIR_W +: LIR_W]);
            at_rd_pset = at_rd_pset | ({SET_W{at_hit[ent_idx]}}
                         & at_pset[ent_idx*SET_W +: SET_W]);
            at_rd_ptag = at_rd_ptag | ({PHT_TAG_W{at_hit[ent_idx]}}
                         & at_ptag[ent_idx*PHT_TAG_W +: PHT_TAG_W]);
            at_rd_pat  = at_rd_pat | ({PATTERN_W{at_hit[ent_idx]}}
                         & at_pat[ent_idx*PATTERN_W +: PATTERN_W]);
            at_rd_has  = at_rd_has | (at_hit[ent_idx] & at_has_line[ent_idx]);
        end
        ft_vic       = {FT_ENTRIES{1'b0}};
        at_vic       = {AT_ENTRIES{1'b0}};
        ft_free_seen = 1'b0;
        at_free_seen = 1'b0;
        for (ent_idx = 0; ent_idx < FT_ENTRIES; ent_idx = ent_idx + 1) begin
            if (!ft_vld[ent_idx] && !ft_free_seen) begin
                ft_vic[ent_idx] = 1'b1;
                ft_free_seen    = 1'b1;
            end
        end
        if (!ft_free_seen) begin
            ft_vic[ft_ring] = 1'b1;
        end
        for (ent_idx = 0; ent_idx < AT_ENTRIES; ent_idx = ent_idx + 1) begin
            if (!at_vld[ent_idx] && !at_free_seen) begin
                at_vic[ent_idx] = 1'b1;
                at_free_seen    = 1'b1;
            end
        end
        if (!at_free_seen) begin
            at_vic[at_ring] = 1'b1;
        end
        vic_vld  = 1'b0;
        vic_line = {LIR_W{1'b0}};
        vic_pset = {SET_W{1'b0}};
        vic_ptag = {PHT_TAG_W{1'b0}};
        vic_pat  = {PATTERN_W{1'b0}};
        for (ent_idx = 0; ent_idx < AT_ENTRIES; ent_idx = ent_idx + 1) begin
            vic_vld  = vic_vld | (at_vic[ent_idx] & at_vld[ent_idx]);
            vic_line = vic_line | ({LIR_W{at_vic[ent_idx]}}
                       & at_line[ent_idx*LIR_W +: LIR_W]);
            vic_pset = vic_pset | ({SET_W{at_vic[ent_idx]}}
                       & at_pset[ent_idx*SET_W +: SET_W]);
            vic_ptag = vic_ptag | ({PHT_TAG_W{at_vic[ent_idx]}}
                       & at_ptag[ent_idx*PHT_TAG_W +: PHT_TAG_W]);
            vic_pat  = vic_pat | ({PATTERN_W{at_vic[ent_idx]}}
                       & at_pat[ent_idx*PATTERN_W +: PATTERN_W]);
        end
        pht_any  = 1'b0;
        rd_first = {LIR_W{1'b0}};
        rd_fbank = {NB{1'b0}};
        rd_rest  = {PATTERN_W{1'b0}};
        for (ent_idx = 0; ent_idx < PHT_TOTAL; ent_idx = ent_idx + 1) begin
            pht_any  = pht_any | pht_hit[ent_idx];
            rd_first = rd_first | ({LIR_W{pht_hit[ent_idx]}}
                       & pht_first[ent_idx*LIR_W +: LIR_W]);
            rd_fbank = rd_fbank | ({NB{pht_hit[ent_idx]}}
                       & pht_fbank[ent_idx*NB +: NB]);
            rd_rest  = rd_rest | ({PATTERN_W{pht_hit[ent_idx]}}
                       & pht_rest[ent_idx*PATTERN_W +: PATTERN_W]);
        end
    end
    assign ft_line_oh    = {{(PATTERN_W-1){1'b0}}, 1'b1} << ft_rd_line;
    assign do_at_set     = e1_vld & ~e1_evt & any_at;
    assign do_promote    = e1_vld & ~e1_evt & ~any_at & any_ft
                           & (e1_line != ft_rd_line);
    assign do_trigger    = e1_vld & ~e1_evt & ~any_at & ~any_ft;
    assign do_end_gen    = e1_vld & e1_evt & any_at & at_rd_has;
    assign do_ft_discard = e1_vld & e1_evt & ~any_at & any_ft;
    assign pw_req        = do_end_gen | (do_promote & vic_vld);
    assign load_valid      = do_trigger & pht_any;
    assign load_region     = e1_region;
    assign load_line       = e1_line;
    assign load_first      = rd_first;
    assign load_first_bank = rd_fbank;
    assign load_rest       = rd_rest;
    always @(posedge clk) begin : table_proc
        integer ent_idx;
        if (rst) begin
            ft_vld  <= {FT_ENTRIES{1'b0}};
            at_vld  <= {AT_ENTRIES{1'b0}};
            ft_ring <= {FT_IDX_W{1'b0}};
            at_ring <= {AT_IDX_W{1'b0}};
            w_vld   <= 1'b0;
        end
        else begin
            if (e1_vld && !e1_evt && !ft_free_seen) begin
                ft_ring <= ft_ring + 1'b1;
            end
            if (e1_vld && !e1_evt && !at_free_seen) begin
                at_ring <= at_ring + 1'b1;
            end
            for (ent_idx = 0; ent_idx < FT_ENTRIES; ent_idx = ent_idx + 1) begin
                if ((do_promote || do_ft_discard) && ft_hit[ent_idx]) begin
                    ft_vld[ent_idx] <= 1'b0;
                end
                if (do_trigger && ft_vic[ent_idx]) begin
                    ft_vld[ent_idx] <= 1'b1;
                end
            end
            for (ent_idx = 0; ent_idx < AT_ENTRIES; ent_idx = ent_idx + 1) begin
                if (do_end_gen && at_hit[ent_idx]) begin
                    at_vld[ent_idx] <= 1'b0;
                end
                if (do_promote && at_vic[ent_idx]) begin
                    at_vld[ent_idx] <= 1'b1;
                end
            end
            w_vld <= pw_req;
        end
        for (ent_idx = 0; ent_idx < FT_ENTRIES; ent_idx = ent_idx + 1) begin
            if (do_trigger && ft_vic[ent_idx]) begin
                ft_tag[ent_idx*REGION_TAG_W +: REGION_TAG_W] <= e1_rtag;
                ft_line[ent_idx*LIR_W +: LIR_W]              <= e1_line;
                ft_pset[ent_idx*SET_W +: SET_W]              <= e1_set;
                ft_ptag[ent_idx*PHT_TAG_W +: PHT_TAG_W]      <= e1_ptag;
            end
        end
        for (ent_idx = 0; ent_idx < AT_ENTRIES; ent_idx = ent_idx + 1) begin
            if (do_at_set && at_hit[ent_idx]) begin
                at_pat[ent_idx*PATTERN_W +: PATTERN_W] <=
                    at_pat[ent_idx*PATTERN_W +: PATTERN_W] | line_oh;
            end
            if (do_promote && at_vic[ent_idx]) begin
                at_tag[ent_idx*REGION_TAG_W +: REGION_TAG_W] <= e1_rtag;
                at_line[ent_idx*LIR_W +: LIR_W]              <= ft_rd_line;
                at_pset[ent_idx*SET_W +: SET_W]              <= ft_rd_pset;
                at_ptag[ent_idx*PHT_TAG_W +: PHT_TAG_W]      <= ft_rd_ptag;
                at_pat[ent_idx*PATTERN_W +: PATTERN_W]       <= ft_line_oh | line_oh;
            end
        end
        if (do_end_gen) begin
            w_set  <= at_rd_pset;
            w_ptag <= at_rd_ptag;
            w_line <= at_rd_line;
            w_pat  <= at_rd_pat;
        end
        else begin
            w_set  <= vic_pset;
            w_ptag <= vic_ptag;
            w_line <= vic_line;
            w_pat  <= vic_pat;
        end
    end
    always @* begin : w1_proc
        integer ent_idx;
        integer bit_idx;
        for (ent_idx = 0; ent_idx < PHT_SETS; ent_idx = ent_idx + 1) begin
            w_set1h[ent_idx] = (w_set == ent_idx[SET_W-1:0]);
        end
        for (ent_idx = 0; ent_idx < PHT_TOTAL; ent_idx = ent_idx + 1) begin
            if (x_vld && x_write[ent_idx]) begin
                w_tmatch[ent_idx] = (x_ptag == w_ptag);
            end
            else begin
                w_tmatch[ent_idx] = pht_vld[ent_idx]
                    & (pht_tag[ent_idx*PHT_TAG_W +: PHT_TAG_W] == w_ptag);
            end
        end
        w_all = w_pat & ~({{(PATTERN_W-1){1'b0}}, 1'b1} << w_line);
        for (bit_idx = 0; bit_idx < PATTERN_W; bit_idx = bit_idx + 1) begin
            bit_number      = bit_idx;
            w_high[bit_idx] = (bit_number > w_line);
        end
        w_above     = w_all & w_high;
        w_ffs_above = {PATTERN_W{1'b0}};
        w_ffs_all   = {PATTERN_W{1'b0}};
        w_seen_a    = 1'b0;
        w_seen_b    = 1'b0;
        for (bit_idx = 0; bit_idx < PATTERN_W; bit_idx = bit_idx + 1) begin
            w_ffs_above[bit_idx] = w_above[bit_idx] & ~w_seen_a;
            w_seen_a             = w_seen_a | w_above[bit_idx];
            w_ffs_all[bit_idx]   = w_all[bit_idx] & ~w_seen_b;
            w_seen_b             = w_seen_b | w_all[bit_idx];
        end
        w_first_oh = w_seen_a ? w_ffs_above : w_ffs_all;
        w_first = {LIR_W{1'b0}};
        for (bit_idx = 0; bit_idx < PATTERN_W; bit_idx = bit_idx + 1) begin
            bit_number = bit_idx;
            w_first = w_first | ({LIR_W{w_first_oh[bit_idx]}} & bit_number);
        end
        for (bit_idx = 0; bit_idx < NB; bit_idx = bit_idx + 1) begin
            w_fbank[bit_idx] = (w_first[BANK_W-1:0] == bit_idx[BANK_W-1:0]);
        end
    end
    always @(posedge clk) begin : w1_reg_proc
        if (rst) begin
            x_vld <= 1'b0;
        end
        else begin
            x_vld <= w_vld;
        end
        x_set1h  <= w_set1h;
        x_ptag   <= w_ptag;
        x_line   <= w_line;
        x_rest   <= w_all & ~w_first_oh;
        x_first  <= w_first;
        x_fbank  <= w_fbank;
        x_nz     <= |w_all;
        x_tmatch <= w_tmatch;
    end
    always @* begin : w2_proc
        integer set_idx;
        integer way_idx;
        for (set_idx = 0; set_idx < PHT_SETS; set_idx = set_idx + 1) begin
            x_m    = x_tmatch[set_idx*PHT_WAYS +: PHT_WAYS];
            x_f    = ~pht_vld[set_idx*PHT_WAYS +: PHT_WAYS];
            x_ptr  = pht_ptr[set_idx*WAY_W +: WAY_W];
            x_pick = {PHT_WAYS{1'b0}};
            x_seen = 1'b0;
            for (way_idx = 0; way_idx < PHT_WAYS; way_idx = way_idx + 1) begin
                if (x_m[way_idx] && !x_seen) begin
                    x_pick[way_idx] = 1'b1;
                    x_seen          = 1'b1;
                end
            end
            for (way_idx = 0; way_idx < PHT_WAYS; way_idx = way_idx + 1) begin
                if (x_f[way_idx] && !x_seen) begin
                    x_pick[way_idx] = 1'b1;
                    x_seen          = 1'b1;
                end
            end
            x_adv[set_idx] = x_vld & x_set1h[set_idx] & ~x_seen;
            if (!x_seen) begin
                x_pick[x_ptr] = 1'b1;
            end
            x_write[set_idx*PHT_WAYS +: PHT_WAYS] =
                x_pick & {PHT_WAYS{x_vld & x_set1h[set_idx]}};
        end
    end
    always @(posedge clk) begin : pht_proc
        integer ent_idx;
        integer set_idx;
        if (rst) begin
            pht_vld <= {PHT_TOTAL{1'b0}};
            pht_ptr <= {(PHT_SETS*WAY_W){1'b0}};
        end
        else begin
            for (ent_idx = 0; ent_idx < PHT_TOTAL; ent_idx = ent_idx + 1) begin
                if (x_write[ent_idx]) begin
                    pht_vld[ent_idx] <= 1'b1;
                end
            end
            for (set_idx = 0; set_idx < PHT_SETS; set_idx = set_idx + 1) begin
                if (x_adv[set_idx]) begin
                    pht_ptr[set_idx*WAY_W +: WAY_W] <=
                        pht_ptr[set_idx*WAY_W +: WAY_W] + 1'b1;
                end
            end
        end
        for (ent_idx = 0; ent_idx < PHT_TOTAL; ent_idx = ent_idx + 1) begin
            if (x_write[ent_idx]) begin
                pht_tag[ent_idx*PHT_TAG_W +: PHT_TAG_W]  <= x_ptag;
                pht_line[ent_idx*LIR_W +: LIR_W]         <= x_line;
                pht_rest[ent_idx*PATTERN_W +: PATTERN_W] <= x_rest;
                pht_first[ent_idx*LIR_W +: LIR_W]        <= x_first;
                pht_fbank[ent_idx*NB +: NB]              <= x_fbank;
                pht_nz[ent_idx]                          <= x_nz;
            end
        end
    end
`ifdef L1D_DEBUG
    always @(posedge clk) begin : debug_proc
        if (!rst && e1_vld) begin
            if ((ft_hit & (ft_hit - 1'b1)) != {FT_ENTRIES{1'b0}}) begin
                $display("[%0t] L1D PF3_SMS ERROR two FT entries", $time);
            end
            if ((at_hit & (at_hit - 1'b1)) != {AT_ENTRIES{1'b0}}) begin
                $display("[%0t] L1D PF3_SMS ERROR two AT entries", $time);
            end
            if (any_ft && any_at) begin
                $display("[%0t] L1D PF3_SMS ERROR region in FT and AT", $time);
            end
            if ((pht_hit & (pht_hit - 1'b1)) != {PHT_TOTAL{1'b0}}) begin
                $display("[%0t] L1D PF3_SMS ERROR two PHT entries", $time);
            end
        end
    end
`endif
endmodule
`default_nettype wire
`endif
