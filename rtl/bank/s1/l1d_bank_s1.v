`ifndef L1D_BANK_S1_V
`define L1D_BANK_S1_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_bank_s1 #(
    `L1D_PARAMS,
    parameter BANK_ID = 0
) (
    clk, rst,
    s1_valid, s1_kind, s1_seat, s1_req, s1_mid, s1_line, s1_mway, s1_mop, s1_sinv, s1_sid, s1_kill,
    tag_words_q, s1_words,
    lock_valid, lock_line,
    q1_state, q1_swap, q1_slot, q1_is_prefetch, vc_al_ok, vc_al_slot,
    rsv_sc_match,
    r_held, rsv_clear_valid, rsv_clear_line,
    vec_read_slot, vec_read_line_data,
    s2_valid, s2_kind, s2_seat, s2_req, s2_mid, s2_line, s2_sinv, s2_sid,
    s2_hit, s2_scfail, s2_snp_hit, s2_hand, s2_way, s2_held, s2_swap, s2_kill,
    s2_words, s2_lines, s2_st_be, s2_st_din,
    s2_wbpend, s2_vvalid, s2_vdirty, s2_vshared, s2_vline, s2_slot,
    s2_raw_hit, s2_pf_hit,
    s2_data_synd, s2_data_fix, s2_data_ce, s2_data_ue,
    s2_tag_synd, s2_tag_fix, s2_tag_ce, s2_tag_ue, s2_tag_blocked,
    s2_tags
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam [BANK_W-1:0]   BANK_C = BANK_ID;
    localparam [OFFSET_W-1:0] OFF0   = {OFFSET_W{1'b0}};
    localparam SYND_W   = WAYS * GRANULES * DATA_HAM_W;
    localparam TSYND_W  = WAYS * TAG_HAM_W;
    localparam FIX_W    = WAYS * GRANULES;
    input  wire                        clk;
    input  wire                        rst;
    input  wire                        s1_valid;
    input  wire [1:0]                  s1_kind;
    input  wire [SEAT_W-1:0]           s1_seat;
    input  wire [REQ_W-1:0]            s1_req;
    input  wire [MSHR_ID_W-1:0]        s1_mid;
    input  wire [LINE_ADDR_W-1:0]      s1_line;
    input  wire [WAY_W-1:0]            s1_mway;
    input  wire                        s1_mop;
    input  wire                        s1_sinv;
    input  wire [SNP_ID_W-1:0]         s1_sid;
    input  wire                        s1_kill;
    input  wire [WAYS*TWORD_W-1:0]     tag_words_q;
    input  wire [WAYS*DWORD_W-1:0]     s1_words;
    input  wire                        lock_valid;
    input  wire [LINE_ADDR_W-1:0]      lock_line;
    input  wire [1:0]                  q1_state;
    input  wire                        q1_swap;
    input  wire [VC_ID_W-1:0]          q1_slot;
    input  wire                        q1_is_prefetch;
    input  wire                        vc_al_ok;
    input  wire [VC_ID_W-1:0]          vc_al_slot;
    input  wire                        rsv_sc_match;
    output wire                        r_held;
    output wire                        rsv_clear_valid;
    output wire [LINE_ADDR_W-1:0]      rsv_clear_line;
    output wire [VEC_SLOT_W-1:0]       vec_read_slot;
    input  wire [LINE_W-1:0]           vec_read_line_data;
    output reg                         s2_valid;
    output reg  [1:0]                  s2_kind;
    output reg  [SEAT_W-1:0]           s2_seat;
    output reg  [REQ_W-1:0]            s2_req;
    output reg  [MSHR_ID_W-1:0]        s2_mid;
    output reg  [LINE_ADDR_W-1:0]      s2_line;
    output reg                         s2_sinv;
    output reg  [SNP_ID_W-1:0]         s2_sid;
    output reg                         s2_hit;
    output reg                         s2_scfail;
    output reg                         s2_snp_hit;
    output reg                         s2_hand;
    output reg  [WAY_W-1:0]            s2_way;
    output reg                         s2_held;
    output reg                         s2_swap;
    output reg                         s2_kill;
    output reg  [WAYS*WRITE_DATA_WIDTH-1:0] s2_words;
    output reg  [WAYS*LINE_W-1:0]      s2_lines;
    output reg  [LINE_BYTES-1:0]       s2_st_be;
    output reg  [LINE_W-1:0]           s2_st_din;
    output reg                         s2_wbpend;
    output reg                         s2_vvalid;
    output reg                         s2_vdirty;
    output reg                         s2_vshared;
    output reg  [LINE_ADDR_W-1:0]      s2_vline;
    output reg  [VC_ID_W-1:0]          s2_slot;
    output reg                         s2_raw_hit;
    output reg                         s2_pf_hit;
    output reg  [SYND_W-1:0]           s2_data_synd;
    output reg  [FIX_W-1:0]            s2_data_fix;
    output reg  [WAYS-1:0]             s2_data_ce;
    output reg  [WAYS-1:0]             s2_data_ue;
    output reg  [TSYND_W-1:0]          s2_tag_synd;
    output reg  [WAYS-1:0]             s2_tag_fix;
    output reg  [WAYS-1:0]             s2_tag_ce;
    output reg  [WAYS-1:0]             s2_tag_ue;
    output reg                         s2_tag_blocked;
    output reg  [WAYS*TAG_W-1:0]       s2_tags;
    wire [WAYS*TAG_W-1:0]    tag_q;
    wire [WAYS*LINE_W-1:0]   s1_lines;
    genvar sw;
    generate
        for (sw = 0; sw < WAYS; sw = sw + 1) begin : g_split
            assign tag_q[sw*TAG_W +: TAG_W]      = tag_words_q[sw*TWORD_W +: TAG_W];
            assign s1_lines[sw*LINE_W +: LINE_W] = s1_words[sw*DWORD_W +: LINE_W];
        end
    endgenerate
    wire [INDEX_W-1:0] s1_set;
    wire [TAG_W-1:0]   s1_tag;
    wire               s1_cache;
    wire               s1_store;
    wire               s1_amo;
    wire               s1_is_sc;
    wire               s1_pf;
    wire [OFFSET_W-1:0] s1_off;
    wire [MEM_SIZE_BITS-1:0] s1_size;
    wire [WRITE_DATA_WIDTH-1:0] s1_wdata;
    wire               s1_lsu, s1_refill, s1_maint, s1_snp;
    wire               s1_line_op;
    wire               s2_lsu;
    assign s1_set     = s1_line[LA_SET_LSB +: INDEX_W];
    assign s1_tag     = s1_line[LA_TAG_LSB +: TAG_W];
    assign s1_cache   = s1_req[REQ_CACHE_BIT];
    assign s1_store   = (s1_req[REQ_RDWR_BIT] == OP_WRITE);
    assign s1_amo     = s1_req[REQ_AMO_BIT];
    assign s1_is_sc   = s1_amo && !s1_req[REQ_SEQ_BIT] && s1_store;
    assign s1_pf      = s1_req[REQ_PF_BIT];
    assign s1_off     = s1_req[REQ_ADDR_LSB +: OFFSET_W];
    assign s1_size    = s1_req[REQ_SIZE_LSB +: MEM_SIZE_BITS];
    assign s1_wdata   = s1_req[REQ_DATA_LSB +: WRITE_DATA_WIDTH];
    assign s1_lsu     = s1_valid && (s1_kind == K_LSU);
    assign s1_refill  = s1_valid && (s1_kind == K_REFILL);
    assign s1_maint   = s1_valid && (s1_kind == K_MAINT);
    assign s1_snp     = s1_valid && (s1_kind == K_SNOOP);
    assign s1_line_op = s1_req[REQ_LINE_BIT];
    assign s2_lsu     = s2_valid && (s2_kind == K_LSU);
    assign vec_read_slot = s1_req[REQ_DATA_LSB +: VEC_SLOT_W];
    wire [2*WAYS-1:0] m_states;
    wire [WAYS-2:0]   m_plru;
    wire [WAYS-1:0]   m_pf_bits;
    wire              st_we;
    wire [WAY_W-1:0]  st_way;
    wire [1:0]        st_val;
    wire              pl_we;
    wire [WAYS-2:0]   plru_new;
    wire              pf_we;
    wire              pf_val;
    wire [WAY_W-1:0]  s1_way;
    l1d_meta_flops #(.SETS(SETS), .WAYS(WAYS), .INDEX_W(INDEX_W), .WAY_W(WAY_W)) u_meta (
        .clk                  (clk),
        .rst                  (rst),
        .read_set             (s1_set),
        .read_way_states_flat (m_states),
        .read_plru_bits       (m_plru),
        .read_pf_bits         (m_pf_bits),
        .state_write_enable   (st_we),
        .state_write_set      (s1_set),
        .state_write_way      (st_way),
        .state_write_value    (st_val),
        .plru_write_enable    (pl_we),
        .plru_write_set       (s1_set),
        .plru_write_value     (plru_new),
        .pf_write_enable      (pf_we),
        .pf_write_set         (s1_set),
        .pf_write_way         (s1_way),
        .pf_write_value       (pf_val)
    );
    wire [SYND_W-1:0]  data_synd;
    wire [FIX_W-1:0]   data_fix;
    wire [FIX_W-1:0]   data_ue_g;
    wire [WAYS-1:0]    data_ce;
    wire [WAYS-1:0]    data_ue;
    wire [TSYND_W-1:0] tag_synd;
    wire [WAYS-1:0]    tag_fix;
    wire [WAYS-1:0]    tag_ue_raw;
    wire [WAYS-1:0]    way_valid;
    wire [WAYS-1:0]    tag_ce;
    wire [WAYS-1:0]    tag_ue;
    wire               tag_err_any;
    generate
        if (HAS_ECC != 0) begin : g_ecc
            genvar ew, eg;
            for (ew = 0; ew < WAYS; ew = ew + 1) begin : g_ecc_way
                for (eg = 0; eg < GRANULES; eg = eg + 1) begin : g_ecc_gran
                    wire po_unused;
                    l1d_ecc_syn #(.DATA_W(GRAN_BITS), .HAM_W(DATA_HAM_W)) u_syn (
                        .data          (s1_words[ew*DWORD_W + eg*GRAN_BITS +: GRAN_BITS]),
                        .check         (s1_words[ew*DWORD_W + LINE_W + eg*DATA_ECC_W +: DATA_ECC_W]),
                        .syndrome      (data_synd[(ew*GRANULES + eg)*DATA_HAM_W +: DATA_HAM_W]),
                        .parity_odd    (po_unused),
                        .correctable   (data_fix[ew*GRANULES + eg]),
                        .uncorrectable (data_ue_g[ew*GRANULES + eg])
                    );
                end
                assign data_ce[ew] = |data_fix[ew*GRANULES +: GRANULES];
                assign data_ue[ew] = |data_ue_g[ew*GRANULES +: GRANULES];
                wire tpo_unused;
                l1d_ecc_syn #(.DATA_W(TAG_W), .HAM_W(TAG_HAM_W)) u_tag_syn (
                    .data          (tag_words_q[ew*TWORD_W +: TAG_W]),
                    .check         (tag_words_q[ew*TWORD_W + TAG_W +: TAG_ECC_W]),
                    .syndrome      (tag_synd[ew*TAG_HAM_W +: TAG_HAM_W]),
                    .parity_odd    (tpo_unused),
                    .correctable   (tag_fix[ew]),
                    .uncorrectable (tag_ue_raw[ew])
                );
            end
        end else begin : g_no_ecc
            assign data_synd  = {SYND_W{1'b0}};
            assign data_fix   = {FIX_W{1'b0}};
            assign data_ue_g  = {FIX_W{1'b0}};
            assign data_ce    = {WAYS{1'b0}};
            assign data_ue    = {WAYS{1'b0}};
            assign tag_synd   = {TSYND_W{1'b0}};
            assign tag_fix    = {WAYS{1'b0}};
            assign tag_ue_raw = {WAYS{1'b0}};
        end
    endgenerate
    genvar vw;
    generate
        for (vw = 0; vw < WAYS; vw = vw + 1) begin : g_way_valid
            assign way_valid[vw] = (m_states[2*vw +: 2] != ST_I);
            assign tag_ce[vw]    = tag_fix[vw] & way_valid[vw];
            assign tag_ue[vw]    = tag_ue_raw[vw] & way_valid[vw];
        end
    endgenerate
    assign tag_err_any = |(tag_ce | tag_ue);
    wire             hit;
    wire [WAY_W-1:0] hit_way, victim_way, vict_way;
    wire [WAY_W-1:0] acc_way;
    assign acc_way = (s1_kind == K_LSU) ? hit_way : vict_way;
    l1d_s1_lookup #(.WAYS(WAYS), .TAG_W(TAG_W), .WAY_W(WAY_W)) u_lookup (
        .way_tags_flat   (tag_q),
        .way_states_flat (m_states),
        .plru_bits       (m_plru),
        .lookup_tag      (s1_tag),
        .accessed_way    (acc_way),
        .hit             (hit),
        .hit_way         (hit_way),
        .victim_way      (victim_way),
        .plru_bits_next  (plru_new)
    );
    wire [1:0] hit_st;
    assign hit_st = m_states[2*hit_way +: 2];
    wire s2_lrsc;
    wire sc_ok;
    wire s1_live;
    wire s1_scfail;
    wire s1_lsu_th;
    assign s2_lrsc   = s2_lsu && s2_req[REQ_AMO_BIT] && !s2_req[REQ_SEQ_BIT];
    assign sc_ok     = rsv_sc_match && !s2_lrsc;
    assign s1_live   = s1_lsu && !s1_kill && !s1_pf && !tag_err_any;
    assign s1_scfail = s1_live && s1_cache && s1_is_sc && !sc_ok;
    assign s1_lsu_th = s1_live && s1_cache && hit && !s1_scfail;
    wire [LINE_ADDR_W-1:0] v0_line;
    wire                   v_locked;
    wire [1:0]             v_st;
    wire                   v_valid, v_dirty;
    wire [LINE_ADDR_W-1:0] v_line;
    wire [VC_ID_W-1:0]     r_slot;
    assign v0_line  = {tag_q[victim_way*TAG_W +: TAG_W], s1_set, BANK_C};
    assign v_locked = lock_valid && (v0_line == lock_line);
    assign vict_way = v_locked ? (victim_way ^ {{(WAY_W-1){1'b0}}, 1'b1}) : victim_way;
    assign v_st     = m_states[2*vict_way +: 2];
    assign v_valid  = (v_st != ST_I);
    assign v_dirty  = (v_st == ST_M);
    assign v_line   = {tag_q[vict_way*TAG_W +: TAG_W], s1_set, BANK_C};
    assign r_slot   = q1_swap ? q1_slot : vc_al_slot;
    assign r_held   = s1_refill && v_valid && !q1_swap && !vc_al_ok;
    wire [1:0]             mt_st;
    wire                   mt_dirty;
    wire [LINE_ADDR_W-1:0] mt_vline;
    wire                   m_held;
    assign mt_st    = m_states[2*s1_mway +: 2];
    assign mt_dirty = (mt_st == ST_M);
    assign mt_vline = {tag_q[s1_mway*TAG_W +: TAG_W], s1_set, BANK_C};
    assign m_held   = s1_maint && mt_dirty && !vc_al_ok;
    reg  [3:0] m_ev;
    reg  [1:0] m_cur;
    wire [1:0] m_nxt;
    wire       m_we, m_upg, m_hand;
    always @* begin
        m_ev  = EV_NONE;
        m_cur = hit_st;
        if (s1_lsu_th)
            m_ev = s1_store ? EV_WRITE_HIT : (s1_amo ? EV_UNIQ_HIT : EV_LOAD_HIT);
        else if (s1_refill && !r_held)
            m_ev = EV_INSTALL;
        else if (s1_maint && !m_held) begin
            m_ev  = (s1_mop == MAINT_FLUSH) ? EV_FLUSH : EV_CLEAN;
            m_cur = mt_st;
        end else if (s1_snp && hit)
            m_ev = s1_sinv ? EV_SNP_INV : EV_SNP_READ;
    end
    l1d_mesi_next u_mesi (
        .event_code            (m_ev),
        .current_state         (m_cur),
        .install_state         (q1_state),
        .next_state            (m_nxt),
        .state_write_enable    (m_we),
        .upgrade_needed        (m_upg),
        .snoop_hands_over_data (m_hand)
    );
    wire s1_hit;
    assign s1_hit = s1_lsu_th && !m_upg;
    assign s1_way = (s1_kind == K_REFILL) ? vict_way :
                    (s1_kind == K_MAINT)  ? s1_mway : hit_way;
    assign st_we  = m_we;
    assign st_way = s1_way;
    assign st_val = m_nxt;
    assign pl_we  = s1_hit || (s1_refill && !r_held);
    wire pf_demand_hit;
    assign pf_demand_hit = s1_hit && m_pf_bits[hit_way];
    assign pf_we  = pf_demand_hit || (s1_refill && !r_held) || (s1_snp && hit && s1_sinv) ||
                    (s1_maint && !m_held && (s1_mop == MAINT_FLUSH));
    assign pf_val = s1_refill && q1_is_prefetch;
    reg  [LINE_BYTES-1:0] st_be;
    wire [LINE_W-1:0]     st_wext;
    wire [LINE_W-1:0]     st_din;
    integer bi;
    integer nby;
    assign st_wext = {{(LINE_W-WRITE_DATA_WIDTH){1'b0}}, s1_wdata};
    assign st_din  = s1_line_op ? vec_read_line_data : (st_wext << {s1_off, 3'b000});
    always @* begin
        nby = 1 << s1_size;
        for (bi = 0; bi < LINE_BYTES; bi = bi + 1)
            st_be[bi] = s1_line_op || ((bi >= s1_off) && (bi < s1_off + nby));
    end
    wire [WAYS*WRITE_DATA_WIDTH-1:0] s1_words_ld;
    genvar gwd;
    generate
        for (gwd = 0; gwd < WAYS; gwd = gwd + 1) begin : g_word
            l1d_resp_gen #(.IN_BYTES(LINE_BYTES), .WRITE_DATA_WIDTH(WRITE_DATA_WIDTH),
                           .MEM_SIZE_BITS(MEM_SIZE_BITS), .OFF_W(OFFSET_W)) u_word (
                .source_block (s1_lines[gwd*LINE_W +: LINE_W]), .byte_offset (s1_off), .access_size (s1_size),
                .load_data    (s1_words_ld[gwd*WRITE_DATA_WIDTH +: WRITE_DATA_WIDTH])
            );
        end
    endgenerate
    wire s1_evict;
    assign s1_evict        = (RSV_CLR_ON_EVICT != 0) && s1_refill && !r_held && v_valid;
    assign rsv_clear_valid = s1_snp || s1_evict;
    assign rsv_clear_line  = s1_snp ? s1_line : v_line;
    always @(posedge clk) begin : s1_to_s2_proc
        if (rst) begin
            s2_valid <= 1'b0;
        end else begin
            s2_valid       <= s1_valid;
            s2_kind        <= s1_kind;
            s2_seat        <= s1_seat;
            s2_req         <= s1_req;
            s2_mid         <= s1_mid;
            s2_line        <= s1_line;
            s2_sinv        <= s1_sinv;
            s2_sid         <= s1_sid;
            s2_hit         <= s1_hit;
            s2_scfail      <= s1_scfail;
            s2_snp_hit     <= s1_snp && hit;
            s2_hand        <= m_hand;
            s2_way         <= s1_way;
            s2_held        <= r_held || m_held;
            s2_swap        <= q1_swap;
            s2_kill        <= s1_kill;
            s2_words       <= s1_words_ld;
            s2_lines       <= s1_lines;
            s2_st_be       <= st_be;
            s2_st_din      <= st_din;
            s2_wbpend      <= s1_maint;
            s2_raw_hit     <= s1_lsu && s1_cache && hit;
            s2_pf_hit      <= pf_demand_hit;
            s2_data_synd   <= data_synd;
            s2_data_fix    <= data_fix;
            s2_data_ce     <= data_ce;
            s2_data_ue     <= data_ue;
            s2_tag_synd    <= tag_synd;
            s2_tag_fix     <= tag_fix;
            s2_tag_ce      <= tag_ce;
            s2_tag_ue      <= tag_ue;
            s2_tag_blocked <= s1_lsu && !s1_kill && !s1_pf && tag_err_any;
            s2_tags        <= tag_q;
            if (s1_maint) begin
                s2_vvalid  <= mt_dirty;
                s2_vdirty  <= 1'b1;
                s2_vshared <= 1'b0;
                s2_vline   <= mt_vline;
                s2_slot    <= vc_al_slot;
            end else begin
                s2_vvalid  <= v_valid;
                s2_vdirty  <= v_dirty;
                s2_vshared <= (v_st == ST_S);
                s2_vline   <= v_line;
                s2_slot    <= r_slot;
            end
        end
    end
`ifdef L1D_DEBUG
    always @(posedge clk) begin
        if (!rst) begin
            if (s1_lsu)
                $display("[%0t] L1D B%0d S1 %s entry=%0d idx=%0d %s %s addr=%h set=%0d -> %s way=%0d state=%0d%s%s%s%s",
                         $time, BANK_ID, s1_pf ? "PF " : "LSU", s1_seat, s1_req[REQ_IDX_LSB +: IDX_BITS],
                         (s1_store ? "ST" : "LD"), (s1_cache ? "C " : "NC"), s1_req[REQ_ADDR_LSB +: ADDR_W], s1_set,
                         (!s1_cache ? "non-cacheable" : (hit ? "HIT" : "MISS")), hit_way, hit_st,
                         s1_kill ? " (ghost)" : "", m_upg ? " (upgrade)" : "", s1_scfail ? " (SC fail)" : "",
                         tag_err_any ? " (TAG ECC ERROR: blocked)" : "");
            if (s1_refill)
                $display("[%0t] L1D B%0d S1 REFILL mshr=%0d line=%h set=%0d victim way=%0d state=%0d swap=%b slot=%0d install=%0d pf=%b%s",
                         $time, BANK_ID, s1_mid, {s1_line, OFF0}, s1_set, vict_way, v_st, q1_swap, r_slot, q1_state, q1_is_prefetch,
                         r_held ? " -> HELD" : "");
            if (s1_maint)
                $display("[%0t] L1D B%0d S1 MAINT set=%0d way=%0d state=%0d%s", $time, BANK_ID, s1_set, s1_mway, mt_st, m_held ? " -> HELD" : "");
            if (s1_snp)
                $display("[%0t] L1D B%0d S1 SNOOP %s line=%h -> %s way=%0d", $time, BANK_ID, s1_sinv ? "INV" : "READ", {s1_line, OFF0},
                         hit ? "HIT" : "tag miss", hit_way);
            if (s1_valid && (|data_ce || |data_ue || tag_err_any))
                $display("[%0t] L1D B%0d S1 ECC set=%0d data_ce=%b data_ue=%b tag_ce=%b tag_ue=%b", $time, BANK_ID, s1_set, data_ce, data_ue, tag_ce, tag_ue);
        end
    end
`endif
endmodule
`default_nettype wire
`endif
