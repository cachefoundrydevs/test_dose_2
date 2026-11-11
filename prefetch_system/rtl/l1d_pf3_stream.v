`ifndef L1D_PF3_STREAM_V
`define L1D_PF3_STREAM_V
`default_nettype none
module l1d_pf3_stream #(
    parameter NB          = 4,
    parameter ADDR_W      = 64,
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
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      pf_enable,
    input  wire [NB-1:0]             train_valid,
    input  wire [NB-1:0]             train_no_train,
    input  wire [NB*ADDR_W-1:0]      train_addr,
    input  wire [NB-1:0]             train_is_store,
    input  wire [NB-1:0]             train_miss,
    input  wire [NB-1:0]             train_pf_hit,
    input  wire                      held,
    output reg                       cand_valid,
    output reg  [ADDR_W-$clog2(LINE_BYTES)-1:0] cand_line,
    output reg  [NB-1:0]             cand_bank,
    output reg                       cand_unique
);
    localparam NC         = STR_ENTRIES;
    localparam OFFSET_W   = $clog2(LINE_BYTES);
    localparam PAGE_W     = $clog2(PAGE_BYTES);
    localparam LIP_W      = PAGE_W - OFFSET_W;
    localparam PAGE_NUM_W = PA_W - PAGE_W;
    localparam LINE_W     = ADDR_W - OFFSET_W;
    localparam PAD_W      = ADDR_W - PA_W;
    localparam CONF_W     = $clog2(CONF_MAX + 1);
    localparam BANK_W     = $clog2(NB);
    localparam WIDE_W     = LIP_W + 2;
    localparam [WIDE_W-1:0] DEPTH_WIDE = DEPTH;
    localparam [WIDE_W-1:0] LAST_WIDE  = (1 << LIP_W) - 1;
    localparam [LIP_W-1:0]  LAST_LINE  = (1 << LIP_W) - 1;
    localparam [LIP_W-1:0]  LIP_ONE    = 1;
    reg  [NB-1:0]            lane_pick;
    reg                      lane_seen;
    reg  [NB*TAG_W-1:0]      lane_tag;
    wire [NB*LIP_W-1:0]      lane_line;
    wire [NB*(LIP_W+1)-1:0]  lane_line_p1;
    reg  [NB*LIP_W-1:0]      lane_tgt_up;
    reg  [NB*LIP_W-1:0]      lane_tgt_dn;
    reg  [WIDE_W-1:0]        line_wide;
    reg  [WIDE_W-1:0]        up_sum;
    reg  [WIDE_W-1:0]        dn_diff;
    reg                      pick_any;
    reg  [TAG_W-1:0]         pick_tag;
    reg  [PAGE_NUM_W-1:0]    pick_page;
    reg  [LIP_W-1:0]         pick_line;
    reg  [LIP_W-1:0]         pick_tgt_up;
    reg  [LIP_W-1:0]         pick_tgt_dn;
    reg                      pick_trig;
    reg                      pick_miss;
    reg                      pick_store;
    reg                      pick_same_tag;
    reg                      pick_same;
    reg                      pick_up;
    reg                      pick_dn;
    reg                      e1_vld;
    reg  [TAG_W-1:0]         e1_tag;
    reg  [PAGE_NUM_W-1:0]    e1_page;
    reg  [LIP_W-1:0]         e1_line;
    reg  [LIP_W:0]           e1_line_p1w;
    reg  [LIP_W-1:0]         e1_line_p1;
    reg  [LIP_W-1:0]         e1_line_m1;
    reg                      e1_top;
    reg                      e1_bot;
    reg  [LIP_W-1:0]         e1_tgt_up;
    reg  [LIP_W-1:0]         e1_tgt_dn;
    reg                      e1_trig;
    reg                      e1_miss;
    reg                      e1_store;
    reg                      e1_same_tag;
    reg                      e1_same;
    reg                      e1_up;
    reg                      e1_dn;
    reg  [NC-1:0]            e2_card;
    wire [NC-1:0]            card_hit;
    wire [NC-1:0]            card_pend;
    wire [NC-1:0]            card_valid;
    wire [NC*CONF_W-1:0]     card_conf;
    wire [NC-1:0]            card_dvld;
    wire [NC*LIP_W-1:0]      card_dline;
    wire [NC-1:0]            card_ddup;
    wire [NC-1:0]            card_dstore;
    wire [NC-1:0]            card_sgo;
    wire [NC-1:0]            card_sdone;
    wire [NC*LIP_W-1:0]      card_sline;
    wire [NC-1:0]            card_sdup;
    wire [NC*PAGE_NUM_W-1:0] card_page;
    wire [NC*TAG_W-1:0]      card_tag;
    wire [NC-1:0]            card_store;
    wire [NC-1:0]            card_alloc;
    wire [NC-1:0]            prev_card;
    wire                     any_hit;
    wire                     alloc;
    reg  [NC*3-1:0]          card_rank;
    reg  [NC-1:0]            victim;
    reg                      card_beaten;
    reg  [RECENT_N-1:0]       recent_vld;
    reg  [RECENT_N*TAG_W-1:0] recent_tag;
    reg  [RECENT_N*LIP_W-1:0] recent_line;
    wire [RECENT_N-1:0]       recent_tag_eq;
    reg  [NC-1:0]            rr_mask_q;
    reg  [NC-1:0]            sel_q;
    reg                      sel_vld_q;
    reg  [NC-1:0]            pick_high;
    reg  [NC-1:0]            pick_base;
    reg  [NC-1:0]            pick_one;
    reg  [NC-1:0]            pick_above;
    reg                      pick_seen;
    wire                     slot_free;
    wire                     scan_take;
    wire                     direct_ok;
    reg                      s_go;
    reg  [LIP_W-1:0]         s_line;
    reg                      s_dup;
    reg  [PAGE_NUM_W-1:0]    s_page;
    reg  [TAG_W-1:0]         s_tag;
    reg                      s_store;
    reg                      d_go;
    reg  [LIP_W-1:0]         d_line;
    reg                      d_dup;
    reg                      d_store;
    reg                      push;
    reg  [TAG_W-1:0]         push_tag;
    reg  [PAGE_NUM_W-1:0]    push_page;
    reg  [LIP_W-1:0]         push_line;
    reg                      push_store;
    genvar lane_g;
    generate
        for (lane_g = 0; lane_g < NB; lane_g = lane_g + 1) begin : g_lane
            assign lane_line[lane_g*LIP_W +: LIP_W] =
                train_addr[lane_g*ADDR_W + OFFSET_W +: LIP_W];
            assign lane_line_p1[lane_g*(LIP_W+1) +: LIP_W+1] =
                {1'b0, train_addr[lane_g*ADDR_W + OFFSET_W +: LIP_W]}
                + {{LIP_W{1'b0}}, 1'b1};
        end
    endgenerate
    always @* begin : lane_proc
        integer lane_idx;
        integer bit_idx;
        lane_tag    = {(NB*TAG_W){1'b0}};
        for (lane_idx = 0; lane_idx < NB; lane_idx = lane_idx + 1) begin
            for (bit_idx = 0; bit_idx < PAGE_NUM_W; bit_idx = bit_idx + 1) begin
                lane_tag[lane_idx*TAG_W + (bit_idx % TAG_W)] =
                    lane_tag[lane_idx*TAG_W + (bit_idx % TAG_W)]
                    ^ train_addr[lane_idx*ADDR_W + PAGE_W + bit_idx];
            end
            line_wide = {{(WIDE_W-LIP_W){1'b0}},
                         lane_line[lane_idx*LIP_W +: LIP_W]};
            up_sum    = line_wide + DEPTH_WIDE;
            lane_tgt_up[lane_idx*LIP_W +: LIP_W] =
                (up_sum > LAST_WIDE) ? LAST_LINE : up_sum[LIP_W-1:0];
            dn_diff   = line_wide - DEPTH_WIDE;
            lane_tgt_dn[lane_idx*LIP_W +: LIP_W] =
                (line_wide >= DEPTH_WIDE) ? dn_diff[LIP_W-1:0]
                                          : {LIP_W{1'b0}};
        end
    end
    always @* begin : pick_proc
        integer lane_idx;
        lane_seen = 1'b0;
        for (lane_idx = 0; lane_idx < NB; lane_idx = lane_idx + 1) begin
            lane_pick[lane_idx] = train_valid[lane_idx]
                                  & ~train_no_train[lane_idx] & ~lane_seen;
            lane_seen = lane_seen
                        | (train_valid[lane_idx] & ~train_no_train[lane_idx]);
        end
        pick_any      = 1'b0;
        pick_tag      = {TAG_W{1'b0}};
        pick_page     = {PAGE_NUM_W{1'b0}};
        pick_line     = {LIP_W{1'b0}};
        pick_tgt_up   = {LIP_W{1'b0}};
        pick_tgt_dn   = {LIP_W{1'b0}};
        pick_trig     = 1'b0;
        pick_miss     = 1'b0;
        pick_store    = 1'b0;
        pick_same_tag = 1'b0;
        pick_same     = 1'b0;
        pick_up       = 1'b0;
        pick_dn       = 1'b0;
        for (lane_idx = 0; lane_idx < NB; lane_idx = lane_idx + 1) begin
            pick_any    = pick_any | lane_pick[lane_idx];
            pick_tag    = pick_tag | ({TAG_W{lane_pick[lane_idx]}}
                          & lane_tag[lane_idx*TAG_W +: TAG_W]);
            pick_page   = pick_page | ({PAGE_NUM_W{lane_pick[lane_idx]}}
                          & train_addr[lane_idx*ADDR_W + PAGE_W +: PAGE_NUM_W]);
            pick_line   = pick_line | ({LIP_W{lane_pick[lane_idx]}}
                          & lane_line[lane_idx*LIP_W +: LIP_W]);
            pick_tgt_up = pick_tgt_up | ({LIP_W{lane_pick[lane_idx]}}
                          & lane_tgt_up[lane_idx*LIP_W +: LIP_W]);
            pick_tgt_dn = pick_tgt_dn | ({LIP_W{lane_pick[lane_idx]}}
                          & lane_tgt_dn[lane_idx*LIP_W +: LIP_W]);
            pick_trig   = pick_trig | (lane_pick[lane_idx]
                          & (train_miss[lane_idx] | train_pf_hit[lane_idx]));
            pick_miss   = pick_miss | (lane_pick[lane_idx] & train_miss[lane_idx]);
            pick_store  = pick_store | (lane_pick[lane_idx]
                          & train_is_store[lane_idx]);
            pick_same_tag = pick_same_tag | (lane_pick[lane_idx]
                & (lane_tag[lane_idx*TAG_W +: TAG_W] == e1_tag));
            pick_same = pick_same | (lane_pick[lane_idx]
                & (lane_line[lane_idx*LIP_W +: LIP_W] == e1_line));
            pick_up   = pick_up | (lane_pick[lane_idx]
                & ({1'b0, lane_line[lane_idx*LIP_W +: LIP_W]} == e1_line_p1w));
            pick_dn   = pick_dn | (lane_pick[lane_idx]
                & (lane_line_p1[lane_idx*(LIP_W+1) +: LIP_W+1]
                   == {1'b0, e1_line}));
        end
    end
    always @(posedge clk) begin : s1_reg_proc
        if (rst) begin
            e1_vld <= 1'b0;
        end
        else begin
            e1_vld <= pick_any & pf_enable;
        end
        e1_tag      <= pick_tag;
        e1_page     <= pick_page;
        e1_line     <= pick_line;
        e1_line_p1w <= {1'b0, pick_line} + {{LIP_W{1'b0}}, 1'b1};
        e1_line_p1  <= pick_line + LIP_ONE;
        e1_line_m1  <= pick_line - LIP_ONE;
        e1_top      <= (pick_line == LAST_LINE);
        e1_bot      <= (pick_line == {LIP_W{1'b0}});
        e1_tgt_up   <= pick_tgt_up;
        e1_tgt_dn   <= pick_tgt_dn;
        e1_trig     <= pick_trig;
        e1_miss     <= pick_miss;
        e1_store    <= pick_store;
        e1_same_tag <= pick_same_tag;
        e1_same     <= pick_same;
        e1_up       <= pick_up;
        e1_dn       <= pick_dn;
    end
    genvar key_g;
    generate
        for (key_g = 0; key_g < RECENT_N; key_g = key_g + 1) begin : g_recent_eq
            assign recent_tag_eq[key_g] =
                (recent_tag[key_g*TAG_W +: TAG_W] == e1_tag);
        end
    endgenerate
    genvar card_g;
    generate
        for (card_g = 0; card_g < NC; card_g = card_g + 1) begin : g_card
            assign prev_card[card_g]  = e2_card[card_g];
            assign card_alloc[card_g] = alloc & victim[card_g];
            l1d_pf3_stream_card #(
                .NB         (NB),
                .TAG_W      (TAG_W),
                .PAGE_NUM_W (PAGE_NUM_W),
                .LIP_W      (LIP_W),
                .CONF_W     (CONF_W),
                .CONF_ON    (CONF_ON),
                .CONF_MAX   (CONF_MAX),
                .RECENT_N   (RECENT_N)
            ) u_card (
                .clk           (clk),
                .rst           (rst),
                .flush         (~pf_enable),
                .lane_pick     (lane_pick),
                .lane_tag      (lane_tag),
                .lane_line     (lane_line),
                .lane_line_p1  (lane_line_p1),
                .ev_vld        (e1_vld),
                .ev_tag        (e1_tag),
                .ev_page       (e1_page),
                .ev_line       (e1_line),
                .ev_line_p1    (e1_line_p1),
                .ev_line_m1    (e1_line_m1),
                .ev_top        (e1_top),
                .ev_bot        (e1_bot),
                .ev_tgt_up     (e1_tgt_up),
                .ev_tgt_dn     (e1_tgt_dn),
                .ev_trig       (e1_trig),
                .ev_store      (e1_store),
                .prev_card     (prev_card[card_g]),
                .prev_same_tag (e1_same_tag),
                .prev_same     (e1_same),
                .prev_up       (e1_up),
                .prev_dn       (e1_dn),
                .alloc_en      (card_alloc[card_g]),
                .direct_ok     (direct_ok),
                .scan_sel      (sel_q[card_g]),
                .scan_take     (scan_take),
                .recent_tag_eq (recent_tag_eq),
                .recent_line   (recent_line),
                .recent_tag    (recent_tag),
                .recent_vld    (recent_vld),
                .hit           (card_hit[card_g]),
                .pend_out      (card_pend[card_g]),
                .valid_out     (card_valid[card_g]),
                .conf_out      (card_conf[card_g*CONF_W +: CONF_W]),
                .dir_vld       (card_dvld[card_g]),
                .dir_line      (card_dline[card_g*LIP_W +: LIP_W]),
                .dir_dup       (card_ddup[card_g]),
                .dir_store     (card_dstore[card_g]),
                .scan_go       (card_sgo[card_g]),
                .scan_done     (card_sdone[card_g]),
                .scan_line     (card_sline[card_g*LIP_W +: LIP_W]),
                .scan_dup      (card_sdup[card_g]),
                .page_out      (card_page[card_g*PAGE_NUM_W +: PAGE_NUM_W]),
                .tag_out       (card_tag[card_g*TAG_W +: TAG_W]),
                .store_out     (card_store[card_g])
            );
        end
    endgenerate
    assign any_hit = |card_hit;
    assign alloc   = e1_vld & ~any_hit & e1_miss;
    always @* begin : victim_proc
        integer card_idx;
        integer other_idx;
        for (card_idx = 0; card_idx < NC; card_idx = card_idx + 1) begin
            card_rank[card_idx*3 +: 3] = card_valid[card_idx]
                ? ({{(3-CONF_W){1'b0}}, card_conf[card_idx*CONF_W +: CONF_W]}
                   + 3'd1)
                : 3'd0;
        end
        for (card_idx = 0; card_idx < NC; card_idx = card_idx + 1) begin
            card_beaten = 1'b0;
            for (other_idx = 0; other_idx < NC; other_idx = other_idx + 1) begin
                if (other_idx != card_idx) begin
                    if ((card_rank[other_idx*3 +: 3] < card_rank[card_idx*3 +: 3])
                        || ((card_rank[other_idx*3 +: 3] == card_rank[card_idx*3 +: 3])
                            && (other_idx < card_idx))) begin
                        card_beaten = 1'b1;
                    end
                end
            end
            victim[card_idx] = ~card_beaten;
        end
    end
    assign slot_free = ~cand_valid & ~held;
    assign scan_take = slot_free & pf_enable;
    assign direct_ok = slot_free & pf_enable & ~sel_vld_q;
    always @* begin : cand_sel_proc
        integer card_idx;
        s_go    = 1'b0;
        s_line  = {LIP_W{1'b0}};
        s_dup   = 1'b0;
        s_page  = {PAGE_NUM_W{1'b0}};
        s_tag   = {TAG_W{1'b0}};
        s_store = 1'b0;
        d_go    = 1'b0;
        d_line  = {LIP_W{1'b0}};
        d_dup   = 1'b0;
        d_store = 1'b0;
        for (card_idx = 0; card_idx < NC; card_idx = card_idx + 1) begin
            s_go    = s_go | card_sgo[card_idx];
            s_line  = s_line | ({LIP_W{sel_q[card_idx]}}
                      & card_sline[card_idx*LIP_W +: LIP_W]);
            s_dup   = s_dup | (sel_q[card_idx] & card_sdup[card_idx]);
            s_page  = s_page | ({PAGE_NUM_W{sel_q[card_idx]}}
                      & card_page[card_idx*PAGE_NUM_W +: PAGE_NUM_W]);
            s_tag   = s_tag | ({TAG_W{sel_q[card_idx]}}
                      & card_tag[card_idx*TAG_W +: TAG_W]);
            s_store = s_store | (sel_q[card_idx] & card_store[card_idx]);
            d_go    = d_go | card_dvld[card_idx];
            d_line  = d_line | ({LIP_W{card_hit[card_idx]}}
                      & card_dline[card_idx*LIP_W +: LIP_W]);
            d_dup   = d_dup | (card_hit[card_idx] & card_ddup[card_idx]);
            d_store = d_store | (card_hit[card_idx] & card_dstore[card_idx]);
        end
        if (scan_take && s_go) begin
            push       = ~s_dup;
            push_tag   = s_tag;
            push_page  = s_page;
            push_line  = s_line;
            push_store = s_store;
        end
        else begin
            push       = d_go & ~d_dup;
            push_tag   = e1_tag;
            push_page  = e1_page;
            push_line  = d_line;
            push_store = d_store;
        end
    end
    always @* begin : scan_pick_proc
        integer card_idx;
        pick_high = card_pend & rr_mask_q;
        pick_base = (|pick_high) ? pick_high : card_pend;
        pick_one  = {NC{1'b0}};
        pick_seen = 1'b0;
        for (card_idx = 0; card_idx < NC; card_idx = card_idx + 1) begin
            if (pick_base[card_idx] && !pick_seen) begin
                pick_one[card_idx] = 1'b1;
                pick_seen          = 1'b1;
            end
        end
        pick_above = {NC{1'b0}};
        pick_seen  = 1'b0;
        for (card_idx = 0; card_idx < NC; card_idx = card_idx + 1) begin
            pick_above[card_idx] = pick_seen;
            pick_seen            = pick_seen | pick_one[card_idx];
        end
    end
    always @(posedge clk) begin : scan_reg_proc
        integer bank_idx;
        if (rst || !pf_enable) begin
            sel_vld_q   <= 1'b0;
            sel_q       <= {NC{1'b0}};
            rr_mask_q   <= {NC{1'b1}};
            cand_valid  <= 1'b0;
            recent_vld  <= {RECENT_N{1'b0}};
            e2_card     <= {NC{1'b0}};
        end
        else begin
            if (!sel_vld_q || scan_take) begin
                sel_vld_q <= |card_pend;
                sel_q     <= pick_one;
                if (|card_pend) begin
                    rr_mask_q <= pick_above;
                end
            end
            cand_valid <= push;
            if (push) begin
                recent_vld <= {recent_vld[RECENT_N-2:0], 1'b1};
            end
            e2_card <= card_hit | card_alloc;
        end
        if (push) begin
            cand_line   <= {{PAD_W{1'b0}}, push_page, push_line};
            cand_unique <= push_store;
            recent_tag  <= {recent_tag[(RECENT_N-1)*TAG_W-1:0], push_tag};
            recent_line <= {recent_line[(RECENT_N-1)*LIP_W-1:0], push_line};
            for (bank_idx = 0; bank_idx < NB; bank_idx = bank_idx + 1) begin
                cand_bank[bank_idx] <=
                    (push_line[BANK_W-1:0] == bank_idx[BANK_W-1:0]);
            end
        end
    end
`ifdef L1D_DEBUG
    always @(posedge clk) begin : debug_proc
        if (!rst) begin
            if ((card_hit & (card_hit - 1'b1)) != {NC{1'b0}}) begin
                $display("[%0t] L1D PF3_STREAM ERROR two cards hit", $time);
            end
            if (alloc && ((victim & (victim - 1'b1)) != {NC{1'b0}})) begin
                $display("[%0t] L1D PF3_STREAM ERROR victim not one-hot",
                         $time);
            end
        end
    end
`endif
endmodule
`default_nettype wire
`endif
