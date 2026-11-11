`ifndef L1D_PF3_STREAM_CARD_V
`define L1D_PF3_STREAM_CARD_V
`default_nettype none
module l1d_pf3_stream_card #(
    parameter NB         = 4,
    parameter TAG_W      = 12,
    parameter PAGE_NUM_W = 44,
    parameter LIP_W      = 6,
    parameter CONF_W     = 2,
    parameter CONF_ON    = 2,
    parameter CONF_MAX   = 3,
    parameter RECENT_N   = 4
) (
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      flush,
    input  wire [NB-1:0]             lane_pick,
    input  wire [NB*TAG_W-1:0]       lane_tag,
    input  wire [NB*LIP_W-1:0]       lane_line,
    input  wire [NB*(LIP_W+1)-1:0]   lane_line_p1,
    input  wire                      ev_vld,
    input  wire [TAG_W-1:0]          ev_tag,
    input  wire [PAGE_NUM_W-1:0]     ev_page,
    input  wire [LIP_W-1:0]          ev_line,
    input  wire [LIP_W-1:0]          ev_line_p1,
    input  wire [LIP_W-1:0]          ev_line_m1,
    input  wire                      ev_top,
    input  wire                      ev_bot,
    input  wire [LIP_W-1:0]          ev_tgt_up,
    input  wire [LIP_W-1:0]          ev_tgt_dn,
    input  wire                      ev_trig,
    input  wire                      ev_store,
    input  wire                      prev_card,
    input  wire                      prev_same_tag,
    input  wire                      prev_same,
    input  wire                      prev_up,
    input  wire                      prev_dn,
    input  wire                      alloc_en,
    input  wire                      direct_ok,
    input  wire                      scan_sel,
    input  wire                      scan_take,
    input  wire [RECENT_N-1:0]       recent_tag_eq,
    input  wire [RECENT_N*LIP_W-1:0] recent_line,
    input  wire [RECENT_N*TAG_W-1:0] recent_tag,
    input  wire [RECENT_N-1:0]       recent_vld,
    output wire                      hit,
    output wire                      pend_out,
    output wire                      valid_out,
    output wire [CONF_W-1:0]         conf_out,
    output wire                      dir_vld,
    output wire [LIP_W-1:0]          dir_line,
    output wire                      dir_dup,
    output wire                      dir_store,
    output wire                      scan_go,
    output wire                      scan_done,
    output wire [LIP_W-1:0]          scan_line,
    output wire                      scan_dup,
    output wire [PAGE_NUM_W-1:0]     page_out,
    output wire [TAG_W-1:0]          tag_out,
    output wire                      store_out
);
    localparam [CONF_W-1:0] CONF_ON_V  = CONF_ON;
    localparam [CONF_W-1:0] CONF_MAX_V = CONF_MAX;
    localparam [CONF_W-1:0] CONF_ONE   = 1;
    localparam [LIP_W-1:0]  LIP_ONE    = 1;
    reg                   valid_q;
    reg  [TAG_W-1:0]      tag_q;
    reg  [PAGE_NUM_W-1:0] page_q;
    reg  [LIP_W-1:0]      last_q;
    reg  [LIP_W:0]        last_p1_q;
    reg                   dir_q;
    reg  [CONF_W-1:0]     conf_q;
    reg  [LIP_W-1:0]      ahead_q;
    reg  [LIP_W-1:0]      tgt_q;
    reg                   store_q;
    reg                   pend_q;
    reg                   s1_hit_q;
    reg                   s1_same_q;
    reg                   s1_up_q;
    reg                   s1_dn_q;
    reg  [NB-1:0]         lane_hit;
    reg  [NB-1:0]         lane_same;
    reg  [NB-1:0]         lane_up;
    reg  [NB-1:0]         lane_dn;
    integer               lane_idx;
    wire                  c_same;
    wire                  c_up;
    wire                  c_dn;
    wire                  behind_up;
    wire                  behind_dn;
    wire                  conf_unset;
    wire                  step_up;
    wire                  step_dn;
    wire                  step_ok;
    wire                  flip_ok;
    wire                  ahead_behind;
    reg  [CONF_W-1:0]     new_conf;
    reg                   new_dir;
    reg  [LIP_W-1:0]      new_ahead;
    reg  [LIP_W-1:0]      new_tgt;
    wire                  new_pend;
    wire [LIP_W-1:0]      ahead_p1;
    wire [LIP_W-1:0]      ahead_m1;
    reg  [LIP_W-1:0]      d_next;
    reg                   d_done;
    wire                  d_make;
    wire                  d_finish;
    wire                  cur_done;
    wire [LIP_W-1:0]      cur_next;
    reg                   key_dup;
    reg                   d_dup_r;
    reg                   s_dup_r;
    integer               key_idx;
    always @* begin : s1_cmp_proc
        for (lane_idx = 0; lane_idx < NB; lane_idx = lane_idx + 1) begin
            lane_hit[lane_idx]  = valid_q
                & (tag_q == lane_tag[lane_idx*TAG_W +: TAG_W]);
            lane_same[lane_idx] = (last_q == lane_line[lane_idx*LIP_W +: LIP_W]);
            lane_up[lane_idx]   = ({1'b0, lane_line[lane_idx*LIP_W +: LIP_W]}
                                   == last_p1_q);
            lane_dn[lane_idx]   = (lane_line_p1[lane_idx*(LIP_W+1) +: LIP_W+1]
                                   == {1'b0, last_q});
        end
    end
    always @(posedge clk) begin : s1_reg_proc
        s1_hit_q  <= |(lane_pick & lane_hit);
        s1_same_q <= |(lane_pick & lane_same);
        s1_up_q   <= |(lane_pick & lane_up);
        s1_dn_q   <= |(lane_pick & lane_dn);
    end
    assign hit    = ev_vld & (prev_card ? prev_same_tag : s1_hit_q);
    assign c_same = prev_card ? prev_same : s1_same_q;
    assign c_up   = prev_card ? prev_up   : s1_up_q;
    assign c_dn   = prev_card ? prev_dn   : s1_dn_q;
    assign behind_up = (ahead_q < ev_line);
    assign behind_dn = (ahead_q > ev_line);
    assign conf_unset   = (conf_q == {CONF_W{1'b0}});
    assign step_up      = c_up & (conf_unset | dir_q);
    assign step_dn      = c_dn & (conf_unset | ~dir_q);
    assign step_ok      = step_up | step_dn;
    assign flip_ok      = (c_up | c_dn) & ~step_ok;
    assign ahead_behind = c_up ? behind_up : behind_dn;
    always @* begin : rule_proc
        if (c_same) begin
            new_conf  = conf_q;
            new_dir   = dir_q;
            new_ahead = ahead_q;
            new_tgt   = tgt_q;
        end
        else if (step_ok) begin
            new_conf  = (conf_q == CONF_MAX_V) ? conf_q : (conf_q + CONF_ONE);
            new_dir   = c_up;
            new_ahead = ((conf_q < CONF_ON_V) || ahead_behind) ? ev_line
                                                               : ahead_q;
            new_tgt   = c_up ? ev_tgt_up : ev_tgt_dn;
        end
        else if (flip_ok) begin
            new_conf  = {CONF_W{1'b0}};
            new_dir   = c_up;
            new_ahead = ev_line;
            new_tgt   = c_up ? ev_tgt_up : ev_tgt_dn;
        end
        else begin
            new_conf  = {CONF_W{1'b0}};
            new_dir   = 1'b0;
            new_ahead = ev_line;
            new_tgt   = ev_tgt_dn;
        end
    end
    assign new_pend = (new_conf >= CONF_ON_V) & (ev_trig | pend_q);
    assign ahead_p1 = ahead_q + LIP_ONE;
    assign ahead_m1 = ahead_q - LIP_ONE;
    always @* begin : direct_proc
        if (!c_same && (!step_ok || (conf_q < CONF_ON_V) || ahead_behind)) begin
            d_next = new_dir ? ev_line_p1 : ev_line_m1;
            d_done = new_dir ? ev_top : ev_bot;
        end
        else begin
            d_next = new_dir ? ahead_p1 : ahead_m1;
            d_done = new_dir ? (ahead_q >= new_tgt) : (ahead_q <= new_tgt);
        end
        d_dup_r = 1'b0;
        for (key_idx = 0; key_idx < RECENT_N; key_idx = key_idx + 1) begin
            key_dup = recent_vld[key_idx] & recent_tag_eq[key_idx]
                      & (recent_line[key_idx*LIP_W +: LIP_W] == d_next);
            d_dup_r = d_dup_r | key_dup;
        end
    end
    assign d_make   = hit & new_pend & ~d_done & direct_ok;
    assign d_finish = hit & new_pend & d_done;
    assign dir_vld   = d_make;
    assign dir_line  = d_next;
    assign dir_dup   = d_dup_r;
    assign dir_store = alloc_en ? ev_store : store_q;
    assign cur_done = dir_q ? (ahead_q >= tgt_q) : (ahead_q <= tgt_q);
    assign cur_next = dir_q ? ahead_p1 : ahead_m1;
    always @* begin : scan_dup_proc
        s_dup_r = 1'b0;
        for (key_idx = 0; key_idx < RECENT_N; key_idx = key_idx + 1) begin
            key_dup = recent_vld[key_idx]
                      & (recent_tag[key_idx*TAG_W +: TAG_W] == tag_q)
                      & (recent_line[key_idx*LIP_W +: LIP_W] == cur_next);
            s_dup_r = s_dup_r | key_dup;
        end
    end
    assign scan_go   = scan_sel & pend_q & ~cur_done;
    assign scan_done = scan_sel & pend_q & cur_done;
    assign scan_line = cur_next;
    assign scan_dup  = s_dup_r;
    always @(posedge clk) begin : card_ctl_proc
        if (rst) begin
            valid_q <= 1'b0;
            pend_q  <= 1'b0;
        end
        else if (flush) begin
            pend_q  <= 1'b0;
        end
        else if (alloc_en) begin
            valid_q <= 1'b1;
            pend_q  <= 1'b0;
        end
        else if (hit) begin
            pend_q  <= new_pend & ~d_finish;
        end
        else if (scan_take && scan_done) begin
            pend_q  <= 1'b0;
        end
    end
    always @(posedge clk) begin : card_data_proc
        if (alloc_en) begin
            tag_q     <= ev_tag;
            page_q    <= ev_page;
            last_q    <= ev_line;
            last_p1_q <= {1'b0, ev_line} + {{LIP_W{1'b0}}, 1'b1};
            dir_q     <= 1'b0;
            conf_q    <= {CONF_W{1'b0}};
            ahead_q   <= ev_line;
            tgt_q     <= ev_tgt_dn;
            store_q   <= ev_store;
        end
        else if (hit) begin
            page_q    <= ev_page;
            last_q    <= ev_line;
            last_p1_q <= {1'b0, ev_line} + {{LIP_W{1'b0}}, 1'b1};
            dir_q     <= new_dir;
            conf_q    <= new_conf;
            ahead_q   <= d_make ? d_next : new_ahead;
            tgt_q     <= new_tgt;
        end
        else if (scan_take && scan_go) begin
            ahead_q   <= cur_next;
        end
    end
    assign pend_out  = pend_q;
    assign valid_out = valid_q;
    assign conf_out  = conf_q;
    assign page_out  = page_q;
    assign tag_out   = tag_q;
    assign store_out = store_q;
endmodule
`default_nettype wire
`endif
