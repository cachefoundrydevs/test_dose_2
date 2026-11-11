`ifndef L1D_PF_STREAM_V
`define L1D_PF_STREAM_V
`default_nettype none
module l1d_pf_stream #(
    parameter PA_W        = 56,
    parameter LINE_BYTES  = 64,
    parameter PAGE_BYTES  = 4096,
    parameter STR_ENTRIES = 16,
    parameter TAG_W       = 12,
    parameter DEPTH       = 4,
    parameter CONF_ON     = 2,
    parameter CONF_MAX    = 3,
    parameter RECENT_N    = 4
) (
    input  wire                                   clk,
    input  wire                                   rst,
    input  wire                                   pf_enable,
    input  wire                                   tr_valid,
    input  wire [PA_W-1:0]                        tr_addr,
    input  wire                                   tr_is_store,
    input  wire                                   tr_no_train,
    input  wire                                   tr_miss,
    input  wire                                   tr_pf_hit,
    input  wire                                   pf_ready,
    output wire                                   pf_valid,
    output wire [PA_W-$clog2(LINE_BYTES)-1:0]     pf_line_addr,
    output wire                                   pf_unique,
    output wire                                   pf_flag
);
    localparam OFFSET_W    = $clog2(LINE_BYTES);
    localparam PAGE_W      = $clog2(PAGE_BYTES);
    localparam LIP_W       = PAGE_W - OFFSET_W;
    localparam LIP1_W      = LIP_W + 1;
    localparam PAGE_NUM_W  = PA_W - PAGE_W;
    localparam CONF_W      = $clog2(CONF_MAX + 1);
    localparam DEPTH_W     = $clog2(DEPTH + 1);
    localparam WIDE_W      = LIP_W + DEPTH_W + 1;
    localparam KEY_W       = TAG_W + LIP_W;
    localparam DATA_W      = PAGE_NUM_W + LIP_W + 1;
    localparam [LIP_W-1:0]  LAST_LINE = {LIP_W{1'b1}};
    localparam [WIDE_W-1:0] DEPTH_WIDE = DEPTH;
    localparam [WIDE_W-1:0] LAST_WIDE  = LAST_LINE;
    localparam [CONF_W-1:0] CONF_ON_V  = CONF_ON;
    localparam [CONF_W-1:0] CONF_MAX_V = CONF_MAX;
    localparam [LIP1_W-1:0] ONE_LIP1   = {{LIP_W{1'b0}}, 1'b1};
    reg  [STR_ENTRIES-1:0]            valid_q;
    reg  [STR_ENTRIES*TAG_W-1:0]      tag_q;
    reg  [STR_ENTRIES*PAGE_NUM_W-1:0] page_q;
    reg  [STR_ENTRIES*LIP_W-1:0]      last_q;
    reg  [STR_ENTRIES-1:0]            dir_q;
    reg  [STR_ENTRIES*CONF_W-1:0]     conf_q;
    reg  [STR_ENTRIES*LIP_W-1:0]      ahead_q;
    reg  [STR_ENTRIES*LIP_W-1:0]      tgt_q;
    reg  [STR_ENTRIES-1:0]            store_q;
    reg  [STR_ENTRIES-1:0]            pend_q;
    wire                    s0_event_ok;
    wire [PAGE_NUM_W-1:0]   s0_page;
    wire [LIP_W-1:0]        s0_line;
    wire [TAG_W-1:0]        s0_tag;
    wire                    s0_trigger;
    wire [WIDE_W-1:0]       s0_line_wide;
    wire [WIDE_W-1:0]       s0_up_sum;
    wire [WIDE_W-1:0]       s0_dn_diff;
    wire [LIP_W-1:0]        s0_tgt_up;
    wire [LIP_W-1:0]        s0_tgt_dn;
    reg  [STR_ENTRIES-1:0]  s0_hit_vec;
    reg  [STR_ENTRIES-1:0]  s0_victim;
    wire                    s0_same_prev;
    reg  [STR_ENTRIES-1:0]  victim_elig;
    reg  [STR_ENTRIES-1:0]  tier_mask;
    reg  [STR_ENTRIES-1:0]  tier_pick;
    reg                     victim_found;
    reg                     m_vld_q;
    reg  [TAG_W-1:0]        m_tag_q;
    reg  [PAGE_NUM_W-1:0]   m_page_q;
    reg  [LIP_W-1:0]        m_line_q;
    reg                     m_store_q;
    reg                     m_miss_q;
    reg                     m_trig_q;
    reg  [LIP_W-1:0]        m_tgt_up_q;
    reg  [LIP_W-1:0]        m_tgt_dn_q;
    reg  [STR_ENTRIES-1:0]  m_hit_q;
    reg                     m_same_prev_q;
    reg  [STR_ENTRIES-1:0]  m_victim_q;
    reg  [STR_ENTRIES-1:0]  p_alloc_q;
    wire                    fwd_alloc;
    reg  [STR_ENTRIES-1:0]  hit_eff;
    wire                    hit_any;
    wire                    alloc_new;
    reg  [LIP_W-1:0]        rd_last;
    reg                     rd_dir;
    reg  [CONF_W-1:0]       rd_conf;
    reg  [LIP_W-1:0]        rd_ahead;
    reg  [LIP_W-1:0]        rd_tgt;
    reg                     rd_pend;
    wire [LIP1_W-1:0]       line_wide7;
    wire [LIP1_W-1:0]       last_wide7;
    wire                    delta_same;
    wire                    delta_up;
    wire                    delta_down;
    wire                    conf_unset;
    wire                    step_up;
    wire                    step_down;
    wire                    step_ok;
    wire                    flip_ok;
    wire                    ahead_behind;
    reg  [CONF_W-1:0]       new_conf;
    reg                     new_dir;
    reg  [LIP_W-1:0]        new_ahead;
    reg  [LIP_W-1:0]        new_tgt;
    wire                    new_pend;
    reg  [STR_ENTRIES-1:0]  rr_mask_q;
    reg  [STR_ENTRIES-1:0]  sel_q;
    reg                     sel_vld_q;
    reg  [STR_ENTRIES-1:0]  pick_high;
    reg  [STR_ENTRIES-1:0]  pick_base;
    reg  [STR_ENTRIES-1:0]  pick_one;
    reg  [STR_ENTRIES-1:0]  pick_above;
    reg                     pick_seen;
    wire                    allow_build;
    reg  [LIP_W-1:0]        sel_ahead;
    reg  [LIP_W-1:0]        sel_tgt;
    reg                     sel_dir;
    reg                     sel_pend;
    reg                     sel_store;
    reg  [PAGE_NUM_W-1:0]   sel_page;
    reg  [TAG_W-1:0]        sel_tag;
    wire                    build_done;
    wire [LIP_W-1:0]        build_next;
    wire                    build_issue;
    wire                    build_finish;
    reg                     cand_vld_q;
    reg  [PAGE_NUM_W-1:0]   cand_page_q;
    reg  [LIP_W-1:0]        cand_line_q;
    reg                     cand_store_q;
    reg  [TAG_W-1:0]        cand_tag_q;
    reg  [RECENT_N*KEY_W-1:0] recent_key_q;
    reg  [RECENT_N-1:0]     recent_vld_q;
    reg                     cand_dup;
    wire                    cand_push;
    wire                    queue_pop;
    reg                     q0_vld_q;
    reg  [DATA_W-1:0]       q0_data_q;
    reg                     q1_vld_q;
    reg  [DATA_W-1:0]       q1_data_q;
    integer entry_idx;
    function [TAG_W-1:0] fold_page;
        input [PAGE_NUM_W-1:0] page_number;
        integer bit_idx;
        reg [TAG_W-1:0] folded;
        begin
            folded = {TAG_W{1'b0}};
            for (bit_idx = 0; bit_idx < PAGE_NUM_W; bit_idx = bit_idx + 1) begin
                folded[bit_idx % TAG_W] = folded[bit_idx % TAG_W]
                                          ^ page_number[bit_idx];
            end
            fold_page = folded;
        end
    endfunction
    assign s0_event_ok  = tr_valid & pf_enable & ~tr_no_train;
    assign s0_page      = tr_addr[PA_W-1:PAGE_W];
    assign s0_line      = tr_addr[PAGE_W-1:OFFSET_W];
    assign s0_tag       = fold_page(s0_page);
    assign s0_trigger   = tr_miss | tr_pf_hit;
    assign s0_line_wide = {{(WIDE_W-LIP_W){1'b0}}, s0_line};
    assign s0_up_sum    = s0_line_wide + DEPTH_WIDE;
    assign s0_dn_diff   = s0_line_wide - DEPTH_WIDE;
    assign s0_tgt_up    = (s0_up_sum > LAST_WIDE) ? LAST_LINE
                                                  : s0_up_sum[LIP_W-1:0];
    assign s0_tgt_dn    = (s0_line_wide >= DEPTH_WIDE) ? s0_dn_diff[LIP_W-1:0]
                                                       : {LIP_W{1'b0}};
    assign s0_same_prev = m_vld_q & (m_tag_q == s0_tag);
    always @* begin : s0_compare_proc
        integer entry_idx;
        for (entry_idx = 0; entry_idx < STR_ENTRIES; entry_idx = entry_idx + 1) begin
            s0_hit_vec[entry_idx] = valid_q[entry_idx]
                & (tag_q[entry_idx*TAG_W +: TAG_W] == s0_tag);
        end
    end
    always @* begin : s0_victim_proc
        integer tier_idx;
        integer entry_idx;
        tier_pick = {STR_ENTRIES{1'b0}};
        for (entry_idx = 0; entry_idx < STR_ENTRIES; entry_idx = entry_idx + 1) begin
            victim_elig[entry_idx] = ~(m_vld_q & m_victim_q[entry_idx]);
        end
        for (tier_idx = CONF_MAX + 1; tier_idx >= 0; tier_idx = tier_idx - 1) begin
            tier_mask = {STR_ENTRIES{1'b0}};
            for (entry_idx = 0; entry_idx < STR_ENTRIES; entry_idx = entry_idx + 1) begin
                if (tier_idx == 0) begin
                    tier_mask[entry_idx] = victim_elig[entry_idx]
                                           & ~valid_q[entry_idx];
                end
                else begin
                    tier_mask[entry_idx] = victim_elig[entry_idx]
                        & valid_q[entry_idx]
                        & ({{(32-CONF_W){1'b0}}, conf_q[entry_idx*CONF_W +: CONF_W]}
                           == (tier_idx - 1));
                end
            end
            if (|tier_mask) begin
                tier_pick = tier_mask;
            end
        end
        s0_victim    = {STR_ENTRIES{1'b0}};
        victim_found = 1'b0;
        for (entry_idx = 0; entry_idx < STR_ENTRIES; entry_idx = entry_idx + 1) begin
            if (tier_pick[entry_idx] && !victim_found) begin
                s0_victim[entry_idx] = 1'b1;
                victim_found         = 1'b1;
            end
        end
    end
    always @(posedge clk) begin : s0_register_proc
        if (rst) begin
            m_vld_q       <= 1'b0;
            m_same_prev_q <= 1'b0;
            m_tag_q       <= {TAG_W{1'b0}};
            m_hit_q       <= {STR_ENTRIES{1'b0}};
            m_victim_q    <= {STR_ENTRIES{1'b0}};
        end
        else begin
            m_vld_q       <= s0_event_ok;
            m_same_prev_q <= s0_same_prev;
            m_tag_q       <= s0_tag;
            m_hit_q       <= s0_hit_vec;
            m_victim_q    <= s0_victim;
        end
        m_page_q   <= s0_page;
        m_line_q   <= s0_line;
        m_store_q  <= tr_is_store;
        m_miss_q   <= tr_miss;
        m_trig_q   <= s0_trigger;
        m_tgt_up_q <= s0_tgt_up;
        m_tgt_dn_q <= s0_tgt_dn;
    end
    assign fwd_alloc = m_same_prev_q & (|p_alloc_q);
    always @* begin : s1_hit_proc
        if (fwd_alloc) begin
            hit_eff = p_alloc_q;
        end
        else begin
            hit_eff = m_hit_q & ~p_alloc_q;
        end
    end
    assign hit_any   = |hit_eff;
    assign alloc_new = m_vld_q & ~hit_any & m_miss_q;
    always @* begin : s1_read_proc
        integer entry_idx;
        rd_last  = {LIP_W{1'b0}};
        rd_dir   = 1'b0;
        rd_conf  = {CONF_W{1'b0}};
        rd_ahead = {LIP_W{1'b0}};
        rd_tgt   = {LIP_W{1'b0}};
        rd_pend  = 1'b0;
        for (entry_idx = 0; entry_idx < STR_ENTRIES; entry_idx = entry_idx + 1) begin
            rd_last  = rd_last  | (last_q[entry_idx*LIP_W +: LIP_W]
                                   & {LIP_W{hit_eff[entry_idx]}});
            rd_dir   = rd_dir   | (dir_q[entry_idx] & hit_eff[entry_idx]);
            rd_conf  = rd_conf  | (conf_q[entry_idx*CONF_W +: CONF_W]
                                   & {CONF_W{hit_eff[entry_idx]}});
            rd_ahead = rd_ahead | (ahead_q[entry_idx*LIP_W +: LIP_W]
                                   & {LIP_W{hit_eff[entry_idx]}});
            rd_tgt   = rd_tgt   | (tgt_q[entry_idx*LIP_W +: LIP_W]
                                   & {LIP_W{hit_eff[entry_idx]}});
            rd_pend  = rd_pend  | (pend_q[entry_idx] & hit_eff[entry_idx]);
        end
    end
    assign line_wide7  = {1'b0, m_line_q};
    assign last_wide7  = {1'b0, rd_last};
    assign delta_same  = (m_line_q == rd_last);
    assign delta_up    = (line_wide7 == (last_wide7 + ONE_LIP1));
    assign delta_down  = (line_wide7 == (last_wide7 - ONE_LIP1));
    assign conf_unset  = (rd_conf == {CONF_W{1'b0}});
    assign step_up     = delta_up   & (conf_unset |  rd_dir);
    assign step_down   = delta_down & (conf_unset | ~rd_dir);
    assign step_ok     = step_up | step_down;
    assign flip_ok     = (delta_up | delta_down) & ~step_ok;
    assign ahead_behind = delta_up ? (rd_ahead < m_line_q)
                                   : (rd_ahead > m_line_q);
    always @* begin : s1_rule_proc
        if (delta_same) begin
            new_conf  = rd_conf;
            new_dir   = rd_dir;
            new_ahead = rd_ahead;
            new_tgt   = rd_tgt;
        end
        else if (step_ok) begin
            new_conf  = (rd_conf == CONF_MAX_V) ? rd_conf
                        : (rd_conf + {{(CONF_W-1){1'b0}}, 1'b1});
            new_dir   = delta_up;
            new_ahead = ((rd_conf < CONF_ON_V) || ahead_behind) ? m_line_q
                                                                : rd_ahead;
            new_tgt   = delta_up ? m_tgt_up_q : m_tgt_dn_q;
        end
        else if (flip_ok) begin
            new_conf  = {CONF_W{1'b0}};
            new_dir   = delta_up;
            new_ahead = m_line_q;
            new_tgt   = delta_up ? m_tgt_up_q : m_tgt_dn_q;
        end
        else begin
            new_conf  = {CONF_W{1'b0}};
            new_dir   = 1'b0;
            new_ahead = m_line_q;
            new_tgt   = m_tgt_dn_q;
        end
    end
    assign new_pend = (new_conf >= CONF_ON_V) & (m_trig_q | rd_pend);
    assign allow_build = ~cand_vld_q | ~q1_vld_q;
    always @* begin : s2_pick_proc
        integer entry_idx;
        pick_high = pend_q & rr_mask_q;
        pick_base = (|pick_high) ? pick_high : pend_q;
        pick_one  = {STR_ENTRIES{1'b0}};
        pick_seen = 1'b0;
        for (entry_idx = 0; entry_idx < STR_ENTRIES; entry_idx = entry_idx + 1) begin
            if (pick_base[entry_idx] && !pick_seen) begin
                pick_one[entry_idx] = 1'b1;
                pick_seen           = 1'b1;
            end
        end
        pick_above = {STR_ENTRIES{1'b0}};
        pick_seen  = 1'b0;
        for (entry_idx = 0; entry_idx < STR_ENTRIES; entry_idx = entry_idx + 1) begin
            pick_above[entry_idx] = pick_seen;
            pick_seen             = pick_seen | pick_one[entry_idx];
        end
    end
    always @* begin : s3_read_proc
        integer entry_idx;
        sel_ahead = {LIP_W{1'b0}};
        sel_tgt   = {LIP_W{1'b0}};
        sel_dir   = 1'b0;
        sel_pend  = 1'b0;
        sel_store = 1'b0;
        sel_page  = {PAGE_NUM_W{1'b0}};
        sel_tag   = {TAG_W{1'b0}};
        for (entry_idx = 0; entry_idx < STR_ENTRIES; entry_idx = entry_idx + 1) begin
            sel_ahead = sel_ahead | (ahead_q[entry_idx*LIP_W +: LIP_W]
                                     & {LIP_W{sel_q[entry_idx]}});
            sel_tgt   = sel_tgt   | (tgt_q[entry_idx*LIP_W +: LIP_W]
                                     & {LIP_W{sel_q[entry_idx]}});
            sel_dir   = sel_dir   | (dir_q[entry_idx] & sel_q[entry_idx]);
            sel_pend  = sel_pend  | (pend_q[entry_idx] & sel_q[entry_idx]);
            sel_store = sel_store | (store_q[entry_idx] & sel_q[entry_idx]);
            sel_page  = sel_page  | (page_q[entry_idx*PAGE_NUM_W +: PAGE_NUM_W]
                                     & {PAGE_NUM_W{sel_q[entry_idx]}});
            sel_tag   = sel_tag   | (tag_q[entry_idx*TAG_W +: TAG_W]
                                     & {TAG_W{sel_q[entry_idx]}});
        end
    end
    assign build_done   = sel_dir ? (sel_ahead >= sel_tgt)
                                  : (sel_ahead <= sel_tgt);
    assign build_next   = sel_dir ? (sel_ahead + {{(LIP_W-1){1'b0}}, 1'b1})
                                  : (sel_ahead - {{(LIP_W-1){1'b0}}, 1'b1});
    assign build_issue  = sel_vld_q & allow_build & sel_pend & ~build_done;
    assign build_finish = sel_vld_q & allow_build & sel_pend & build_done;
    always @* begin : s4_dup_proc
        integer recent_idx;
        cand_dup = 1'b0;
        for (recent_idx = 0; recent_idx < RECENT_N; recent_idx = recent_idx + 1) begin
            if (recent_vld_q[recent_idx]
                && (recent_key_q[recent_idx*KEY_W +: KEY_W]
                    == {cand_tag_q, cand_line_q})) begin
                cand_dup = 1'b1;
            end
        end
    end
    assign cand_push = cand_vld_q & ~cand_dup & ~q1_vld_q;
    assign queue_pop = q0_vld_q & pf_ready;
    always @(posedge clk) begin : table_proc
        if (rst || !pf_enable) begin
            pend_q     <= {STR_ENTRIES{1'b0}};
            sel_vld_q  <= 1'b0;
            sel_q      <= {STR_ENTRIES{1'b0}};
            cand_vld_q <= 1'b0;
            q0_vld_q   <= 1'b0;
            q1_vld_q   <= 1'b0;
            rr_mask_q  <= {STR_ENTRIES{1'b1}};
            recent_vld_q <= {RECENT_N{1'b0}};
            p_alloc_q  <= {STR_ENTRIES{1'b0}};
            if (rst) begin
                valid_q <= {STR_ENTRIES{1'b0}};
                tag_q   <= {(STR_ENTRIES*TAG_W){1'b0}};
                page_q  <= {(STR_ENTRIES*PAGE_NUM_W){1'b0}};
                last_q  <= {(STR_ENTRIES*LIP_W){1'b0}};
                dir_q   <= {STR_ENTRIES{1'b0}};
                conf_q  <= {(STR_ENTRIES*CONF_W){1'b0}};
                ahead_q <= {(STR_ENTRIES*LIP_W){1'b0}};
                tgt_q   <= {(STR_ENTRIES*LIP_W){1'b0}};
                store_q <= {STR_ENTRIES{1'b0}};
            end
        end
        else begin
            if (!sel_vld_q || allow_build) begin
                sel_vld_q <= |pend_q;
                sel_q     <= pick_one;
                if (|pend_q) begin
                    rr_mask_q <= pick_above;
                end
            end
            if (allow_build) begin
                cand_vld_q   <= build_issue;
                cand_page_q  <= sel_page;
                cand_line_q  <= build_next;
                cand_store_q <= sel_store;
                cand_tag_q   <= sel_tag;
            end
            if (cand_push) begin
                recent_key_q <= {recent_key_q[(RECENT_N-1)*KEY_W-1:0],
                                 cand_tag_q, cand_line_q};
                recent_vld_q <= {recent_vld_q[RECENT_N-2:0], 1'b1};
            end
            if (!q0_vld_q) begin
                if (cand_push) begin
                    q0_vld_q  <= 1'b1;
                    q0_data_q <= {cand_page_q, cand_line_q, cand_store_q};
                end
            end
            else if (queue_pop) begin
                if (q1_vld_q) begin
                    q0_data_q <= q1_data_q;
                    q1_vld_q  <= 1'b0;
                end
                else if (cand_push) begin
                    q0_data_q <= {cand_page_q, cand_line_q, cand_store_q};
                end
                else begin
                    q0_vld_q <= 1'b0;
                end
            end
            else if (cand_push) begin
                q1_vld_q  <= 1'b1;
                q1_data_q <= {cand_page_q, cand_line_q, cand_store_q};
            end
            for (entry_idx = 0; entry_idx < STR_ENTRIES; entry_idx = entry_idx + 1) begin
                if (sel_q[entry_idx] && build_issue) begin
                    ahead_q[entry_idx*LIP_W +: LIP_W] <= build_next;
                end
                if (sel_q[entry_idx] && build_finish) begin
                    pend_q[entry_idx] <= 1'b0;
                end
            end
            p_alloc_q <= m_victim_q & {STR_ENTRIES{alloc_new}};
            for (entry_idx = 0; entry_idx < STR_ENTRIES; entry_idx = entry_idx + 1) begin
                if (m_vld_q && hit_eff[entry_idx]) begin
                    page_q[entry_idx*PAGE_NUM_W +: PAGE_NUM_W] <= m_page_q;
                    last_q[entry_idx*LIP_W +: LIP_W]           <= m_line_q;
                    dir_q[entry_idx]                           <= new_dir;
                    conf_q[entry_idx*CONF_W +: CONF_W]         <= new_conf;
                    ahead_q[entry_idx*LIP_W +: LIP_W]          <= new_ahead;
                    tgt_q[entry_idx*LIP_W +: LIP_W]            <= new_tgt;
                    pend_q[entry_idx]                          <= new_pend;
                end
                else if (alloc_new && m_victim_q[entry_idx]) begin
                    valid_q[entry_idx]                         <= 1'b1;
                    tag_q[entry_idx*TAG_W +: TAG_W]            <= m_tag_q;
                    page_q[entry_idx*PAGE_NUM_W +: PAGE_NUM_W] <= m_page_q;
                    last_q[entry_idx*LIP_W +: LIP_W]           <= m_line_q;
                    dir_q[entry_idx]                           <= 1'b0;
                    conf_q[entry_idx*CONF_W +: CONF_W]         <= {CONF_W{1'b0}};
                    ahead_q[entry_idx*LIP_W +: LIP_W]          <= m_line_q;
                    tgt_q[entry_idx*LIP_W +: LIP_W]            <= m_tgt_dn_q;
                    store_q[entry_idx]                         <= m_store_q;
                    pend_q[entry_idx]                          <= 1'b0;
                end
            end
        end
    end
    wire [DATA_W-1:0] head_data;
    assign head_data    = q0_data_q;
    assign pf_valid     = q0_vld_q;
    assign pf_line_addr = head_data[DATA_W-1:1];
    assign pf_unique    = head_data[0];
    assign pf_flag      = 1'b1;
`ifdef L1D_DEBUG
    integer check_a;
    integer check_b;
    always @(posedge clk) begin : debug_proc
        if (!rst) begin
            if ((hit_eff & (hit_eff - 1'b1)) != {STR_ENTRIES{1'b0}}) begin
                $display("L1D_PF_STREAM ERROR: two cards updated at %0t", $time);
            end
            if (alloc_new && ((m_victim_q & (m_victim_q - 1'b1))
                              != {STR_ENTRIES{1'b0}} || m_victim_q == 0)) begin
                $display("L1D_PF_STREAM ERROR: victim not one-hot at %0t", $time);
            end
            for (check_a = 0; check_a < STR_ENTRIES; check_a = check_a + 1) begin
                for (check_b = check_a + 1; check_b < STR_ENTRIES; check_b = check_b + 1) begin
                    if (valid_q[check_a] && valid_q[check_b]
                        && tag_q[check_a*TAG_W +: TAG_W]
                           == tag_q[check_b*TAG_W +: TAG_W]) begin
                        $display("L1D_PF_STREAM ERROR: duplicate tag %0d %0d at %0t",
                                 check_a, check_b, $time);
                    end
                end
            end
        end
    end
`endif
endmodule
`default_nettype wire
`endif
