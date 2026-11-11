`ifndef L1D_PF_SMS_CORE_V
`define L1D_PF_SMS_CORE_V
`default_nettype none
module l1d_pf_sms_core #(
    parameter LINE_ADDR_W  = 50,
    parameter LIR_W        = 5,
    parameter PC_HASH_W    = 12,
    parameter REGION_TAG_W = 16,
    parameter FT_ENTRIES   = 16,
    parameter AT_ENTRIES   = 32,
    parameter PHT_SETS     = 32,
    parameter PHT_WAYS     = 4,
    parameter PHT_TAG_W    = 8
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         train_head_valid,
    input  wire [PC_HASH_W-1:0]         train_head_pc_hash,
    input  wire [LINE_ADDR_W-1:0]       train_head_line_addr,
    input  wire                         evt_head_valid,
    input  wire [LINE_ADDR_W-1:0]       evt_head_line_addr,
    output wire                         train_pop,
    output wire                         evt_pop,
    output wire                         load_valid,
    output wire [LINE_ADDR_W-LIR_W-1:0] load_region,
    output wire [(1<<LIR_W)-1:0]        load_mask,
    output wire [LIR_W-1:0]             load_line
);
    localparam REGION_NUM_W = LINE_ADDR_W - LIR_W;
    localparam PATTERN_W    = (1 << LIR_W);
    localparam KEY_W        = PC_HASH_W + LIR_W;
    localparam SET_W        = $clog2(PHT_SETS);
    localparam WAY_W        = $clog2(PHT_WAYS);
    localparam FT_IDX_W     = $clog2(FT_ENTRIES);
    localparam AT_IDX_W     = $clog2(AT_ENTRIES);
    localparam PHT_TOTAL    = PHT_SETS * PHT_WAYS;
    reg  [FT_ENTRIES-1:0]                ft_vld_q;
    reg  [FT_ENTRIES*REGION_TAG_W-1:0]   ft_tag_q;
    reg  [FT_ENTRIES*PC_HASH_W-1:0]      ft_pc_q;
    reg  [FT_ENTRIES*LIR_W-1:0]          ft_line_q;
    reg  [FT_IDX_W-1:0]                  ft_ring_q;
    reg  [AT_ENTRIES-1:0]                at_vld_q;
    reg  [AT_ENTRIES*REGION_TAG_W-1:0]   at_tag_q;
    reg  [AT_ENTRIES*PC_HASH_W-1:0]      at_pc_q;
    reg  [AT_ENTRIES*LIR_W-1:0]          at_line_q;
    reg  [AT_ENTRIES*PATTERN_W-1:0]      at_pat_q;
    reg  [AT_IDX_W-1:0]                  at_ring_q;
    reg  [PHT_TOTAL-1:0]                 pht_vld_q;
    reg  [PHT_TOTAL*PHT_TAG_W-1:0]       pht_tag_q;
    reg  [PHT_TOTAL*PATTERN_W-1:0]       pht_pat_q;
    reg  [PHT_SETS*WAY_W-1:0]            pht_ptr_q;
    reg                                  prefer_evt_q;
    wire                                 take_evt;
    wire                                 take_train;
    wire [LINE_ADDR_W-1:0]               s0_line_addr;
    wire [REGION_NUM_W-1:0]              s0_region;
    wire [LIR_W-1:0]                     s0_line;
    wire [REGION_TAG_W-1:0]              s0_tag;
    wire [KEY_W-1:0]                     s0_key;
    wire [PATTERN_W-1:0]                 s0_line_oh;
    reg                                  e_vld_q;
    reg                                  e_evt_q;
    reg  [REGION_NUM_W-1:0]              e_region_q;
    reg  [REGION_TAG_W-1:0]              e_tag_q;
    reg  [LIR_W-1:0]                     e_line_q;
    reg  [PATTERN_W-1:0]                 e_line_oh_q;
    reg  [PC_HASH_W-1:0]                 e_pc_q;
    reg  [SET_W-1:0]                     e_set_q;
    reg  [PHT_TAG_W-1:0]                 e_ptag_q;
    reg  [FT_ENTRIES-1:0]                s1_ft_hit;
    reg  [AT_ENTRIES-1:0]                s1_at_hit;
    wire                                 s1_same_prev;
    reg  [FT_ENTRIES-1:0]                ft_free;
    reg  [FT_ENTRIES-1:0]                s1_ft_vic;
    reg  [AT_ENTRIES-1:0]                at_free;
    reg  [AT_ENTRIES-1:0]                s1_at_vic;
    reg                                  ft_seen;
    reg                                  at_seen;
    reg  [PHT_WAYS-1:0]                  s1_pht_vld;
    reg  [PHT_WAYS*PHT_TAG_W-1:0]        s1_pht_tag;
    reg  [PHT_WAYS*PATTERN_W-1:0]        s1_pht_pat;
    integer                              pht_base;
    reg                                  f_vld_q;
    reg                                  f_evt_q;
    reg  [REGION_NUM_W-1:0]              f_region_q;
    reg  [REGION_TAG_W-1:0]              f_tag_q;
    reg  [LIR_W-1:0]                     f_line_q;
    reg  [PATTERN_W-1:0]                 f_line_oh_q;
    reg  [PC_HASH_W-1:0]                 f_pc_q;
    reg  [PHT_TAG_W-1:0]                 f_ptag_q;
    reg  [FT_ENTRIES-1:0]                f_ft_hit_q;
    reg  [AT_ENTRIES-1:0]                f_at_hit_q;
    reg                                  f_same_prev_q;
    reg  [FT_ENTRIES-1:0]                f_ft_vic_q;
    reg  [AT_ENTRIES-1:0]                f_at_vic_q;
    reg  [PHT_WAYS-1:0]                  f_pht_vld_q;
    reg  [PHT_WAYS*PHT_TAG_W-1:0]        f_pht_tag_q;
    reg  [PHT_WAYS*PATTERN_W-1:0]        f_pht_pat_q;
    reg  [FT_ENTRIES-1:0]                p_ft_alloc_q;
    reg  [AT_ENTRIES-1:0]                p_at_alloc_q;
    wire                                 fwd_ft;
    wire                                 fwd_at;
    reg  [FT_ENTRIES-1:0]                ft_eff;
    reg  [AT_ENTRIES-1:0]                at_eff;
    wire                                 any_ft;
    wire                                 any_at;
    reg  [PC_HASH_W-1:0]                 ft_rd_pc;
    reg  [LIR_W-1:0]                     ft_rd_line;
    reg  [PC_HASH_W-1:0]                 at_rd_pc;
    reg  [LIR_W-1:0]                     at_rd_line;
    reg  [PATTERN_W-1:0]                 at_rd_pat;
    reg                                  vic_rd_vld;
    reg  [PC_HASH_W-1:0]                 vic_rd_pc;
    reg  [LIR_W-1:0]                     vic_rd_line;
    reg  [PATTERN_W-1:0]                 vic_rd_pat;
    wire                                 do_at_set;
    wire                                 do_promote;
    wire                                 do_trigger;
    wire                                 do_end_gen;
    wire                                 do_ft_discard;
    wire                                 pw_req;
    reg  [PC_HASH_W-1:0]                 pw_pc;
    reg  [LIR_W-1:0]                     pw_line;
    reg  [PATTERN_W-1:0]                 pw_pat;
    wire [KEY_W-1:0]                     pw_key;
    wire [PATTERN_W-1:0]                 ft_line_oh;
    reg  [PHT_WAYS-1:0]                  pht_hit_way;
    reg  [PATTERN_W-1:0]                 pht_hit_pat;
    wire [PATTERN_W-1:0]                 pht_pat_rest;
    reg                                  w_vld_q;
    reg  [SET_W-1:0]                     w_set_q;
    reg  [PHT_TAG_W-1:0]                 w_tag_q;
    reg  [PATTERN_W-1:0]                 w_pat_q;
    reg  [PHT_WAYS-1:0]                  w_match;
    reg  [PHT_WAYS-1:0]                  w_free;
    reg  [PHT_WAYS-1:0]                  w_way_one;
    reg  [WAY_W-1:0]                     w_ptr;
    reg                                  w_seen;
    reg                                  w_adv;
    integer entry_idx;
    integer way_idx;
    integer w_base;
    function [REGION_TAG_W-1:0] fold_region;
        input [REGION_NUM_W-1:0] region_number;
        integer bit_idx;
        reg [REGION_TAG_W-1:0] folded;
        begin
            folded = {REGION_TAG_W{1'b0}};
            for (bit_idx = 0; bit_idx < REGION_NUM_W; bit_idx = bit_idx + 1) begin
                folded[bit_idx % REGION_TAG_W] =
                    folded[bit_idx % REGION_TAG_W] ^ region_number[bit_idx];
            end
            fold_region = folded;
        end
    endfunction
    function [SET_W-1:0] fold_set;
        input [KEY_W-1:0] key_value;
        integer bit_idx;
        reg [SET_W-1:0] folded;
        begin
            folded = {SET_W{1'b0}};
            for (bit_idx = 0; bit_idx < KEY_W; bit_idx = bit_idx + 1) begin
                folded[bit_idx % SET_W] = folded[bit_idx % SET_W]
                                          ^ key_value[bit_idx];
            end
            fold_set = folded;
        end
    endfunction
    function [PHT_TAG_W-1:0] fold_ptag;
        input [KEY_W-1:0] key_value;
        integer bit_idx;
        reg [PHT_TAG_W-1:0] folded;
        begin
            folded = {PHT_TAG_W{1'b0}};
            for (bit_idx = 0; bit_idx < KEY_W; bit_idx = bit_idx + 1) begin
                folded[(bit_idx + 3) % PHT_TAG_W] =
                    folded[(bit_idx + 3) % PHT_TAG_W] ^ key_value[bit_idx];
            end
            fold_ptag = folded;
        end
    endfunction
    function [PATTERN_W-1:0] one_hot_line;
        input [LIR_W-1:0] line_number;
        reg [PATTERN_W-1:0] decoded;
        begin
            decoded              = {PATTERN_W{1'b0}};
            decoded[line_number] = 1'b1;
            one_hot_line         = decoded;
        end
    endfunction
    assign take_evt     = evt_head_valid & (~train_head_valid | prefer_evt_q);
    assign take_train   = train_head_valid & ~take_evt;
    assign train_pop    = take_train;
    assign evt_pop      = take_evt;
    assign s0_line_addr = take_evt ? evt_head_line_addr : train_head_line_addr;
    assign s0_region    = s0_line_addr[LINE_ADDR_W-1:LIR_W];
    assign s0_line      = s0_line_addr[LIR_W-1:0];
    assign s0_tag       = fold_region(s0_region);
    assign s0_key       = {train_head_pc_hash, s0_line};
    assign s0_line_oh   = one_hot_line(s0_line);
    always @(posedge clk) begin : s0_register_proc
        if (rst) begin
            prefer_evt_q <= 1'b0;
            e_vld_q      <= 1'b0;
        end
        else begin
            if (evt_head_valid && train_head_valid) begin
                prefer_evt_q <= ~prefer_evt_q;
            end
            e_vld_q <= take_evt | take_train;
        end
        e_evt_q     <= take_evt;
        e_region_q  <= s0_region;
        e_tag_q     <= s0_tag;
        e_line_q    <= s0_line;
        e_line_oh_q <= s0_line_oh;
        e_pc_q      <= train_head_pc_hash;
        e_set_q     <= fold_set(s0_key);
        e_ptag_q    <= fold_ptag(s0_key);
    end
    always @* begin : s1_compare_proc
        integer entry_idx;
        for (entry_idx = 0; entry_idx < FT_ENTRIES; entry_idx = entry_idx + 1) begin
            s1_ft_hit[entry_idx] = ft_vld_q[entry_idx]
                & (ft_tag_q[entry_idx*REGION_TAG_W +: REGION_TAG_W] == e_tag_q);
        end
        for (entry_idx = 0; entry_idx < AT_ENTRIES; entry_idx = entry_idx + 1) begin
            s1_at_hit[entry_idx] = at_vld_q[entry_idx]
                & (at_tag_q[entry_idx*REGION_TAG_W +: REGION_TAG_W] == e_tag_q);
        end
    end
    assign s1_same_prev = f_vld_q & (f_tag_q == e_tag_q);
    always @* begin : s1_victim_proc
        integer entry_idx;
        ft_seen = 1'b0;
        at_seen = 1'b0;
        s1_ft_vic = {FT_ENTRIES{1'b0}};
        s1_at_vic = {AT_ENTRIES{1'b0}};
        for (entry_idx = 0; entry_idx < FT_ENTRIES; entry_idx = entry_idx + 1) begin
            ft_free[entry_idx] = ~ft_vld_q[entry_idx]
                                 & ~(f_vld_q & f_ft_vic_q[entry_idx]);
        end
        for (entry_idx = 0; entry_idx < AT_ENTRIES; entry_idx = entry_idx + 1) begin
            at_free[entry_idx] = ~at_vld_q[entry_idx]
                                 & ~(f_vld_q & f_at_vic_q[entry_idx]);
        end
        for (entry_idx = 0; entry_idx < FT_ENTRIES; entry_idx = entry_idx + 1) begin
            if (ft_free[entry_idx] && !ft_seen) begin
                s1_ft_vic[entry_idx] = 1'b1;
                ft_seen              = 1'b1;
            end
        end
        if (!ft_seen) begin
            s1_ft_vic[ft_ring_q] = 1'b1;
        end
        for (entry_idx = 0; entry_idx < AT_ENTRIES; entry_idx = entry_idx + 1) begin
            if (at_free[entry_idx] && !at_seen) begin
                s1_at_vic[entry_idx] = 1'b1;
                at_seen              = 1'b1;
            end
        end
        if (!at_seen) begin
            s1_at_vic[at_ring_q] = 1'b1;
        end
    end
    always @* begin : s1_pht_read_proc
        integer way_idx;
        pht_base   = e_set_q * PHT_WAYS;
        s1_pht_vld = {PHT_WAYS{1'b0}};
        s1_pht_tag = {(PHT_WAYS*PHT_TAG_W){1'b0}};
        s1_pht_pat = {(PHT_WAYS*PATTERN_W){1'b0}};
        for (way_idx = 0; way_idx < PHT_WAYS; way_idx = way_idx + 1) begin
            s1_pht_vld[way_idx] = pht_vld_q[pht_base + way_idx];
            s1_pht_tag[way_idx*PHT_TAG_W +: PHT_TAG_W] =
                pht_tag_q[(pht_base + way_idx)*PHT_TAG_W +: PHT_TAG_W];
            s1_pht_pat[way_idx*PATTERN_W +: PATTERN_W] =
                pht_pat_q[(pht_base + way_idx)*PATTERN_W +: PATTERN_W];
        end
    end
    always @(posedge clk) begin : s1_register_proc
        if (rst) begin
            f_vld_q       <= 1'b0;
            f_same_prev_q <= 1'b0;
            f_tag_q       <= {REGION_TAG_W{1'b0}};
            f_ft_hit_q    <= {FT_ENTRIES{1'b0}};
            f_at_hit_q    <= {AT_ENTRIES{1'b0}};
            f_ft_vic_q    <= {FT_ENTRIES{1'b0}};
            f_at_vic_q    <= {AT_ENTRIES{1'b0}};
        end
        else begin
            f_vld_q       <= e_vld_q;
            f_same_prev_q <= s1_same_prev;
            f_tag_q       <= e_tag_q;
            f_ft_hit_q    <= s1_ft_hit;
            f_at_hit_q    <= s1_at_hit;
            f_ft_vic_q    <= s1_ft_vic;
            f_at_vic_q    <= s1_at_vic;
        end
        f_evt_q     <= e_evt_q;
        f_region_q  <= e_region_q;
        f_line_q    <= e_line_q;
        f_line_oh_q <= e_line_oh_q;
        f_pc_q      <= e_pc_q;
        f_ptag_q    <= e_ptag_q;
        f_pht_vld_q <= s1_pht_vld;
        f_pht_tag_q <= s1_pht_tag;
        f_pht_pat_q <= s1_pht_pat;
    end
    assign fwd_ft = f_same_prev_q & (|p_ft_alloc_q);
    assign fwd_at = f_same_prev_q & (|p_at_alloc_q);
    always @* begin : s2_effective_proc
        if (fwd_at) begin
            ft_eff = {FT_ENTRIES{1'b0}};
            at_eff = p_at_alloc_q;
        end
        else if (fwd_ft) begin
            ft_eff = p_ft_alloc_q;
            at_eff = {AT_ENTRIES{1'b0}};
        end
        else begin
            ft_eff = f_ft_hit_q & ft_vld_q & ~p_ft_alloc_q;
            at_eff = f_at_hit_q & at_vld_q & ~p_at_alloc_q;
        end
    end
    assign any_ft = |ft_eff;
    assign any_at = |at_eff;
    always @* begin : s2_read_proc
        integer entry_idx;
        ft_rd_pc    = {PC_HASH_W{1'b0}};
        ft_rd_line  = {LIR_W{1'b0}};
        at_rd_pc    = {PC_HASH_W{1'b0}};
        at_rd_line  = {LIR_W{1'b0}};
        at_rd_pat   = {PATTERN_W{1'b0}};
        vic_rd_vld  = 1'b0;
        vic_rd_pc   = {PC_HASH_W{1'b0}};
        vic_rd_line = {LIR_W{1'b0}};
        vic_rd_pat  = {PATTERN_W{1'b0}};
        for (entry_idx = 0; entry_idx < FT_ENTRIES; entry_idx = entry_idx + 1) begin
            ft_rd_pc   = ft_rd_pc | (ft_pc_q[entry_idx*PC_HASH_W +: PC_HASH_W]
                                     & {PC_HASH_W{ft_eff[entry_idx]}});
            ft_rd_line = ft_rd_line | (ft_line_q[entry_idx*LIR_W +: LIR_W]
                                       & {LIR_W{ft_eff[entry_idx]}});
        end
        for (entry_idx = 0; entry_idx < AT_ENTRIES; entry_idx = entry_idx + 1) begin
            at_rd_pc    = at_rd_pc | (at_pc_q[entry_idx*PC_HASH_W +: PC_HASH_W]
                                      & {PC_HASH_W{at_eff[entry_idx]}});
            at_rd_line  = at_rd_line | (at_line_q[entry_idx*LIR_W +: LIR_W]
                                        & {LIR_W{at_eff[entry_idx]}});
            at_rd_pat   = at_rd_pat | (at_pat_q[entry_idx*PATTERN_W +: PATTERN_W]
                                       & {PATTERN_W{at_eff[entry_idx]}});
            vic_rd_vld  = vic_rd_vld | (at_vld_q[entry_idx] & f_at_vic_q[entry_idx]);
            vic_rd_pc   = vic_rd_pc | (at_pc_q[entry_idx*PC_HASH_W +: PC_HASH_W]
                                       & {PC_HASH_W{f_at_vic_q[entry_idx]}});
            vic_rd_line = vic_rd_line | (at_line_q[entry_idx*LIR_W +: LIR_W]
                                         & {LIR_W{f_at_vic_q[entry_idx]}});
            vic_rd_pat  = vic_rd_pat | (at_pat_q[entry_idx*PATTERN_W +: PATTERN_W]
                                        & {PATTERN_W{f_at_vic_q[entry_idx]}});
        end
    end
    assign ft_line_oh    = one_hot_line(ft_rd_line);
    assign do_at_set     = f_vld_q & ~f_evt_q & any_at;
    assign do_promote    = f_vld_q & ~f_evt_q & ~any_at & any_ft
                           & (f_line_q != ft_rd_line);
    assign do_trigger    = f_vld_q & ~f_evt_q & ~any_at & ~any_ft;
    assign do_end_gen    = f_vld_q & f_evt_q & any_at
                           & (|(at_rd_pat & f_line_oh_q));
    assign do_ft_discard = f_vld_q & f_evt_q & ~any_at & any_ft;
    assign pw_req = do_end_gen | (do_promote & vic_rd_vld);
    always @* begin : s2_pht_write_proc
        if (do_end_gen) begin
            pw_pc   = at_rd_pc;
            pw_line = at_rd_line;
            pw_pat  = at_rd_pat;
        end
        else begin
            pw_pc   = vic_rd_pc;
            pw_line = vic_rd_line;
            pw_pat  = vic_rd_pat;
        end
    end
    assign pw_key = {pw_pc, pw_line};
    always @* begin : s2_pht_lookup_proc
        integer way_idx;
        pht_hit_way = {PHT_WAYS{1'b0}};
        pht_hit_pat = {PATTERN_W{1'b0}};
        for (way_idx = 0; way_idx < PHT_WAYS; way_idx = way_idx + 1) begin
            pht_hit_way[way_idx] = f_pht_vld_q[way_idx]
                & (f_pht_tag_q[way_idx*PHT_TAG_W +: PHT_TAG_W] == f_ptag_q);
            pht_hit_pat = pht_hit_pat
                | (f_pht_pat_q[way_idx*PATTERN_W +: PATTERN_W]
                   & {PATTERN_W{pht_hit_way[way_idx]}});
        end
    end
    assign pht_pat_rest = pht_hit_pat & ~f_line_oh_q;
    assign load_valid   = do_trigger & (|pht_hit_way) & (|pht_pat_rest);
    assign load_region  = f_region_q;
    assign load_mask    = pht_pat_rest;
    assign load_line    = f_line_q;
    always @(posedge clk) begin : table_proc
        if (rst) begin
            ft_vld_q     <= {FT_ENTRIES{1'b0}};
            at_vld_q     <= {AT_ENTRIES{1'b0}};
            ft_ring_q    <= {FT_IDX_W{1'b0}};
            at_ring_q    <= {AT_IDX_W{1'b0}};
            p_ft_alloc_q <= {FT_ENTRIES{1'b0}};
            p_at_alloc_q <= {AT_ENTRIES{1'b0}};
            w_vld_q      <= 1'b0;
        end
        else begin
            if (e_vld_q && !e_evt_q && !ft_seen) begin
                ft_ring_q <= ft_ring_q + 1'b1;
            end
            if (e_vld_q && !e_evt_q && !at_seen) begin
                at_ring_q <= at_ring_q + 1'b1;
            end
            p_ft_alloc_q <= f_ft_vic_q & {FT_ENTRIES{do_trigger}};
            p_at_alloc_q <= f_at_vic_q & {AT_ENTRIES{do_promote}};
            for (entry_idx = 0; entry_idx < FT_ENTRIES; entry_idx = entry_idx + 1) begin
                if ((do_promote || do_ft_discard) && ft_eff[entry_idx]) begin
                    ft_vld_q[entry_idx] <= 1'b0;
                end
                if (do_trigger && f_ft_vic_q[entry_idx]) begin
                    ft_vld_q[entry_idx] <= 1'b1;
                    ft_tag_q[entry_idx*REGION_TAG_W +: REGION_TAG_W] <= f_tag_q;
                    ft_pc_q[entry_idx*PC_HASH_W +: PC_HASH_W]        <= f_pc_q;
                    ft_line_q[entry_idx*LIR_W +: LIR_W]              <= f_line_q;
                end
            end
            for (entry_idx = 0; entry_idx < AT_ENTRIES; entry_idx = entry_idx + 1) begin
                if (do_at_set && at_eff[entry_idx]) begin
                    at_pat_q[entry_idx*PATTERN_W +: PATTERN_W] <=
                        at_pat_q[entry_idx*PATTERN_W +: PATTERN_W] | f_line_oh_q;
                end
                if (do_end_gen && at_eff[entry_idx]) begin
                    at_vld_q[entry_idx] <= 1'b0;
                end
                if (do_promote && f_at_vic_q[entry_idx]) begin
                    at_vld_q[entry_idx] <= 1'b1;
                    at_tag_q[entry_idx*REGION_TAG_W +: REGION_TAG_W] <= f_tag_q;
                    at_pc_q[entry_idx*PC_HASH_W +: PC_HASH_W]        <= ft_rd_pc;
                    at_line_q[entry_idx*LIR_W +: LIR_W]              <= ft_rd_line;
                    at_pat_q[entry_idx*PATTERN_W +: PATTERN_W]       <=
                        ft_line_oh | f_line_oh_q;
                end
            end
            w_vld_q <= pw_req;
        end
        w_set_q <= fold_set(pw_key);
        w_tag_q <= fold_ptag(pw_key);
        w_pat_q <= pw_pat;
    end
    always @* begin : w_way_proc
        integer way_idx;
        w_base    = w_set_q * PHT_WAYS;
        w_ptr     = pht_ptr_q[w_set_q*WAY_W +: WAY_W];
        w_match   = {PHT_WAYS{1'b0}};
        w_free    = {PHT_WAYS{1'b0}};
        w_way_one = {PHT_WAYS{1'b0}};
        w_seen    = 1'b0;
        for (way_idx = 0; way_idx < PHT_WAYS; way_idx = way_idx + 1) begin
            w_match[way_idx] = pht_vld_q[w_base + way_idx]
                & (pht_tag_q[(w_base + way_idx)*PHT_TAG_W +: PHT_TAG_W] == w_tag_q);
            w_free[way_idx]  = ~pht_vld_q[w_base + way_idx];
        end
        for (way_idx = 0; way_idx < PHT_WAYS; way_idx = way_idx + 1) begin
            if (w_match[way_idx] && !w_seen) begin
                w_way_one[way_idx] = 1'b1;
                w_seen             = 1'b1;
            end
        end
        for (way_idx = 0; way_idx < PHT_WAYS; way_idx = way_idx + 1) begin
            if (w_free[way_idx] && !w_seen) begin
                w_way_one[way_idx] = 1'b1;
                w_seen             = 1'b1;
            end
        end
        w_adv = !w_seen;
        if (!w_seen) begin
            w_way_one[w_ptr] = 1'b1;
        end
    end
    always @(posedge clk) begin : pht_proc
        if (rst) begin
            pht_vld_q <= {PHT_TOTAL{1'b0}};
            pht_ptr_q <= {(PHT_SETS*WAY_W){1'b0}};
            pht_tag_q <= {(PHT_TOTAL*PHT_TAG_W){1'b0}};
            pht_pat_q <= {(PHT_TOTAL*PATTERN_W){1'b0}};
        end
        else if (w_vld_q) begin
            for (way_idx = 0; way_idx < PHT_WAYS; way_idx = way_idx + 1) begin
                if (w_way_one[way_idx]) begin
                    pht_vld_q[w_base + way_idx] <= 1'b1;
                    pht_tag_q[(w_base + way_idx)*PHT_TAG_W +: PHT_TAG_W] <= w_tag_q;
                    pht_pat_q[(w_base + way_idx)*PATTERN_W +: PATTERN_W] <= w_pat_q;
                end
            end
            if (w_adv) begin
                pht_ptr_q[w_set_q*WAY_W +: WAY_W] <= w_ptr + 1'b1;
            end
        end
    end
`ifdef L1D_DEBUG
    integer check_a;
    integer check_b;
    always @(posedge clk) begin : debug_proc
        if (!rst) begin
            if (f_vld_q && ((ft_eff & (ft_eff - 1'b1)) != {FT_ENTRIES{1'b0}})) begin
                $display("L1D_PF_SMS ERROR: two FT entries used at %0t", $time);
            end
            if (f_vld_q && ((at_eff & (at_eff - 1'b1)) != {AT_ENTRIES{1'b0}})) begin
                $display("L1D_PF_SMS ERROR: two AT entries used at %0t", $time);
            end
            if (f_vld_q && any_ft && any_at) begin
                $display("L1D_PF_SMS ERROR: region in FT and AT at %0t", $time);
            end
            if (do_promote && ((f_at_vic_q & (f_at_vic_q - 1'b1)) != {AT_ENTRIES{1'b0}}
                               || f_at_vic_q == {AT_ENTRIES{1'b0}})) begin
                $display("L1D_PF_SMS ERROR: AT victim not one-hot at %0t", $time);
            end
            for (check_a = 0; check_a < AT_ENTRIES; check_a = check_a + 1) begin
                for (check_b = check_a + 1; check_b < AT_ENTRIES; check_b = check_b + 1) begin
                    if (at_vld_q[check_a] && at_vld_q[check_b]
                        && at_tag_q[check_a*REGION_TAG_W +: REGION_TAG_W]
                           == at_tag_q[check_b*REGION_TAG_W +: REGION_TAG_W]) begin
                        $display("L1D_PF_SMS ERROR: duplicate AT tag at %0t", $time);
                    end
                end
            end
        end
    end
`endif
endmodule
`default_nettype wire
`endif
