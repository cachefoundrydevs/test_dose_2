`ifndef L1D_PF_STRIDE_V
`define L1D_PF_STRIDE_V
`default_nettype none
`include "l1d_pf_stride_defines.vh"
module l1d_pf_stride #(
   parameter PC_W       = `L1D_PFS_PC_W,
   parameter PA_W       = `L1D_PFS_PA_W,
   parameter ADDR_W     = `L1D_PFS_ADDR_W,
   parameter LINE_BYTES = `L1D_PFS_LINE_BYTES,
   parameter PAGE_BYTES = `L1D_PFS_PAGE_BYTES,
   parameter RPT_SETS   = `L1D_PFS_RPT_SETS,
   parameter RPT_WAYS   = `L1D_PFS_RPT_WAYS,
   parameter TAG_W      = `L1D_PFS_TAG_W,
   parameter PC_LSB     = `L1D_PFS_PC_LSB,
   parameter DIST       = `L1D_PFS_DIST,
   parameter FILT_DEPTH = `L1D_PFS_FILT_DEPTH,
   parameter KEY_W      = `L1D_PFS_KEY_W
) (
   rst,
   clk,
   clear,
   tr_valid,
   tr_pc,
   tr_pa,
   tr_is_store,
   pf_ready,
   pf_valid,
   pf_addr,
   pf_unique
);
   localparam NS       = RPT_SETS;
   localparam NW       = RPT_WAYS;
   localparam ENTRIES  = NS * NW;
   localparam SET_W    = $clog2(NS);
   localparam OFFSET_W = $clog2(LINE_BYTES);
   localparam PAGE_W   = $clog2(PAGE_BYTES);
   localparam LIP_W    = PAGE_W - OFFSET_W;
   localparam PPN_W    = PA_W - PAGE_W;
   localparam PH_W     = KEY_W - LIP_W;
   localparam STRIDE_W = PAGE_W + 1;
   localparam DSH      = $clog2(DIST);
   localparam TGT_W    = PAGE_W + DSH + 2;
   localparam FOLD_LSB = PC_LSB + SET_W;
   localparam FOLD_W   = PC_W - FOLD_LSB;
   localparam EKEY_W   = SET_W + TAG_W + 1;
   localparam PADA_W   = ADDR_W - PA_W;
   localparam NFW      = 3;
   localparam NEA      = 4;
   localparam ST_W = 2;
   localparam [ST_W-1:0] S_INIT   = 2'd0;
   localparam [ST_W-1:0] S_TRANS  = 2'd1;
   localparam [ST_W-1:0] S_STEADY = 2'd2;
   localparam [ST_W-1:0] S_NOPRED = 2'd3;
   localparam NCLS = 5;
   localparam [NCLS-1:0] C_FREE   = 5'b00001;
   localparam [NCLS-1:0] C_NOPRED = 5'b00010;
   localparam [NCLS-1:0] C_INIT   = 5'b00100;
   localparam [NCLS-1:0] C_TRANS  = 5'b01000;
   localparam [NCLS-1:0] C_STEADY = 5'b10000;
   localparam [NFW-1:0] FW_NONE = 3'b000;
   localparam [NFW-1:0] FW_1    = 3'b001;
   localparam [NFW-1:0] FW_2    = 3'b010;
   localparam [NFW-1:0] FW_3    = 3'b100;
   localparam [STRIDE_W-1:0] STRIDE_ZERO = {STRIDE_W{1'b0}};
   localparam [NW-1:0]       WAY_ZERO    = {NW{1'b0}};
   input  wire                rst;
   input  wire                clk;
   input  wire                clear;
   input  wire                tr_valid;
   input  wire [PC_W-1:0]     tr_pc;
   input  wire [PA_W-1:0]     tr_pa;
   input  wire                tr_is_store;
   input  wire                pf_ready;
   output reg                 pf_valid;
   output reg  [ADDR_W-1:0]   pf_addr;
   output reg                 pf_unique;
   reg  [ENTRIES-1:0]         rpt_valid;
   reg  [ENTRIES-1:0]         rpt_st;
   reg  [TAG_W-1:0]           rpt_tag    [0:ENTRIES-1];
   reg  [ST_W-1:0]            rpt_state  [0:ENTRIES-1];
   reg  [STRIDE_W-1:0]        rpt_stride [0:ENTRIES-1];
   reg  [PAGE_W-1:0]          rpt_lo     [0:ENTRIES-1];
   reg  [PH_W-1:0]            rpt_ph     [0:ENTRIES-1];
   reg  [TAG_W-1:0]           tap_tag;
   reg  [PH_W-1:0]            tap_ph;
   reg  [NS-1:0]              tap_set1h;
   reg  [NEA:1]               tap_ss;
   reg  [NEA:1]               t_ss;
   reg                        t_valid;
   reg  [SET_W-1:0]           t_set;
   reg  [NS-1:0]              t_set1h;
   reg  [TAG_W-1:0]           t_tag;
   reg                        t_st;
   reg  [PAGE_W-1:0]          t_lo;
   reg  [PH_W-1:0]            t_ph;
   reg  [PPN_W-1:0]           t_ppn;
   wire [EKEY_W-1:0]          t_key;
   reg  [ENTRIES-1:0]         l_hit;
   reg  [NW*NCLS-1:0]         l_cls;
   reg  [NCLS-1:0]            e_cls;
   reg  [NW*NCLS-1:0]         l_vcls;
   reg  [NW-1:0]              l_cand;
   reg  [NW-1:0]              l_rpl;
   reg  [ENTRIES-1:0]         l_g4;
   wire [STRIDE_W-1:0]        l_dl1;
   wire [STRIDE_W-1:0]        l_dl2;
   wire [STRIDE_W-1:0]        l_dl3;
   wire [STRIDE_W-1:0]        tap_lo_x;
   wire [STRIDE_W-1:0]        t_lo_x;
   wire [STRIDE_W-1:0]        r_lo_x;
   wire [STRIDE_W-1:0]        d_lo_x;
   reg                        r_valid;
   reg  [SET_W-1:0]           r_set;
   reg  [NS-1:0]              r_set1h;
   reg  [TAG_W-1:0]           r_tag;
   reg                        r_st;
   reg  [PAGE_W-1:0]          r_lo;
   reg  [PH_W-1:0]            r_ph;
   reg  [PPN_W-1:0]           r_ppn;
   reg  [ENTRIES-1:0]         r_hit;
   reg  [ENTRIES-1:0]         r_g4;
   reg  [NW*NCLS-1:0]         r_cls;
   reg  [NW-1:0]              r_cand;
   reg  [NW-1:0]              r_avail;
   reg  [NW-1:0]              r_rpl;
   reg                        r_hitok;
   reg  [NEA:1]               r_m;
   reg                        r_ss1;
   reg  [NFW:1]               r_sp;
   reg  [STRIDE_W-1:0]        r_dl1;
   reg  [STRIDE_W-1:0]        r_dl2;
   reg  [STRIDE_W-1:0]        r_dl3;
   wire [EKEY_W-1:0]          r_key;
   reg  [NW-1:0]              r_hitway;
   reg  [NW-1:0]              r_vict;
   reg  [NW-1:0]              r_way;
   reg                        r_alloc;
   reg  [NFW-1:0]             r_src;
   reg                        r_spm;
   reg  [STRIDE_W-1:0]        r_dlm;
   reg  [STRIDE_W-1:0]        r_rd_stride;
   reg  [ST_W-1:0]            r_rd_state;
   reg  [PAGE_W-1:0]          r_rd_lo;
   reg  [PH_W-1:0]            r_rd_ph;
   reg  [STRIDE_W-1:0]        r_ht_stride;
   reg  [ST_W-1:0]            r_ht_state;
   reg  [PAGE_W-1:0]          r_ht_lo;
   reg  [PH_W-1:0]            r_ht_ph;
   reg  [STRIDE_W-1:0]        r_g4_stride;
   reg  [ST_W-1:0]            r_g4_state;
   reg  [PAGE_W-1:0]          r_g4_lo;
   reg  [PH_W-1:0]            r_g4_ph;
   reg                        d_valid;
   reg  [SET_W-1:0]           d_set;
   reg  [NS-1:0]              d_set1h;
   reg  [TAG_W-1:0]           d_tag;
   reg                        d_st;
   reg  [PAGE_W-1:0]          d_lo;
   reg  [PH_W-1:0]            d_ph;
   reg  [PPN_W-1:0]           d_ppn;
   reg  [NW-1:0]              d_way;
   reg                        d_alloc;
   reg  [NFW-1:0]             d_src;
   reg                        d_spm;
   reg  [STRIDE_W-1:0]        d_dlm;
   reg  [STRIDE_W-1:0]        d_rd_stride;
   reg  [ST_W-1:0]            d_rd_state;
   reg  [PAGE_W-1:0]          d_rd_lo;
   reg  [PH_W-1:0]            d_rd_ph;
   wire [EKEY_W-1:0]          d_key;
   wire [STRIDE_W-1:0]        d_dlt;
   wire [STRIDE_W-1:0]        r_rd_lo_x;
   wire [STRIDE_W-1:0]        d_rd_lo_x;
   wire                       d_eqt;
   reg                        d_c1k;
   reg                        d_c1n;
   reg                        d_c1z;
   reg                        d_c2;
   reg                        d_c3;
   reg                        d_none;
   reg                        d_cf;
   reg                        d_cr;
   reg                        d_cm;
   reg                        d_cd;
   reg                        u_valid;
   reg  [SET_W-1:0]           u_set;
   reg  [NS-1:0]              u_set1h;
   reg  [TAG_W-1:0]           u_tag;
   reg                        u_st;
   reg  [PAGE_W-1:0]          u_lo;
   reg  [PH_W-1:0]            u_ph;
   reg  [PPN_W-1:0]           u_ppn;
   reg  [NW-1:0]              u_way;
   reg                        u_alloc;
   reg  [NFW-1:0]             u_src;
   reg                        u_none;
   reg                        u_spm;
   reg  [STRIDE_W-1:0]        u_dlm;
   reg                        u_spt;
   reg  [STRIDE_W-1:0]        u_dlt;
   reg                        u_ct;
   reg                        u_c1k;
   reg                        u_c1n;
   reg                        u_c1z;
   reg                        u_c2;
   reg                        u_c3;
   reg  [STRIDE_W-1:0]        u_rd_stride;
   reg  [ST_W-1:0]            u_rd_state;
   wire [EKEY_W-1:0]          u_key;
   reg  [STRIDE_W-1:0]        e_stride;
   reg  [ST_W-1:0]            e_state;
   reg                        e_sp;
   reg  [STRIDE_W-1:0]        e_dl;
   reg                        correct;
   reg  [STRIDE_W-1:0]        new_dl;
   reg  [STRIDE_W-1:0]        nx_stride;
   reg  [ST_W-1:0]            nx_state;
   reg  [NCLS-1:0]            nx_cls;
   reg                        issue;
   reg                        keep;
   reg                        w_valid;
   reg  [SET_W-1:0]           w_set;
   reg  [NS-1:0]              w_set1h;
   reg  [TAG_W-1:0]           w_tag;
   reg                        w_st;
   reg  [PAGE_W-1:0]          w_lo;
   reg  [PH_W-1:0]            w_ph;
   reg  [PPN_W-1:0]           w_ppn;
   reg  [NW-1:0]              w_way;
   reg  [NCLS-1:0]            w_cls;
   reg  [STRIDE_W-1:0]        w_nx_stride;
   reg  [ST_W-1:0]            w_nx_state;
   reg                        w_issue;
   reg  [STRIDE_W-1:0]        w_stride;
   reg                        w_keep;
   reg                        w_alloc;
   wire [EKEY_W-1:0]          w_key;
   reg  [NW-1:0]              g_way;
   reg  [STRIDE_W-1:0]        g_nx_stride;
   reg  [ST_W-1:0]            g_nx_state;
   reg                        g_issue;
   reg                        g_st;
   reg  [LIP_W-1:0]           g_cur;
   reg  [PH_W-1:0]            g_ph;
   reg  [PPN_W-1:0]           g_ppn;
   wire [TGT_W-1:0]           w_lo_x;
   wire [TGT_W-1:0]           w_step;
   wire [TGT_W-1:0]           g_tgt;
   reg                        g_in_page;
   reg                        f_valid;
   reg                        f_inp;
   reg  [STRIDE_W-1:0]        f_nx_stride;
   reg  [ST_W-1:0]            f_nx_state;
   reg                        f_st;
   reg  [PPN_W-1:0]           f_ppn;
   reg  [LIP_W-1:0]           f_lip;
   reg  [LIP_W-1:0]           f_cur;
   reg  [PH_W-1:0]            f_ph;
   wire [KEY_W-1:0]           f_key;
   reg                        f_dup;
   reg                        f_pass;
   reg  [FILT_DEPTH-1:0]      filt_v;
   reg  [KEY_W-1:0]           filt_key [0:FILT_DEPTH-1];
   reg                        x_pass;
   reg  [KEY_W-1:0]           x_key;
   reg                        x_st;
   reg  [PPN_W-1:0]           x_ppn;
   reg  [LIP_W-1:0]           x_lip;
   always @* begin : tap_proc
      integer i;
      tap_tag = {TAG_W{1'b0}};
      for (i = 0; i < FOLD_W; i = i + 1) begin
         tap_tag[i % TAG_W] = tap_tag[i % TAG_W] ^ tr_pc[FOLD_LSB + i];
      end
      tap_ph = {PH_W{1'b0}};
      for (i = 0; i < PPN_W; i = i + 1) begin
         tap_ph[i % PH_W] = tap_ph[i % PH_W] ^ tr_pa[PAGE_W + i];
      end
      for (i = 0; i < NS; i = i + 1) begin
         tap_set1h[i] = (tr_pc[PC_LSB +: SET_W] == i[SET_W-1:0]);
      end
      tap_ss[1] = t_valid && (tr_pc[PC_LSB +: SET_W] == t_set);
      tap_ss[2] = r_valid && (tr_pc[PC_LSB +: SET_W] == r_set);
      tap_ss[3] = d_valid && (tr_pc[PC_LSB +: SET_W] == d_set);
      tap_ss[4] = u_valid && (tr_pc[PC_LSB +: SET_W] == u_set);
   end
   always @(posedge clk) begin : t_reg_proc
      if (rst) begin
         t_valid <= 1'b0;
      end
      else begin
         t_valid <= tr_valid && !clear;
      end
      t_set   <= tr_pc[PC_LSB +: SET_W];
      t_set1h <= tap_set1h;
      t_ss    <= tap_ss;
      t_tag   <= tap_tag;
      t_st    <= tr_is_store;
      t_lo    <= tr_pa[PAGE_W-1:0];
      t_ph    <= tap_ph;
      t_ppn   <= tr_pa[PA_W-1:PAGE_W];
   end
   assign t_key = {t_set, t_tag, t_st};
   assign r_key = {r_set, r_tag, r_st};
   assign d_key = {d_set, d_tag, d_st};
   assign u_key = {u_set, u_tag, u_st};
   assign w_key = {w_set, w_tag, w_st};
   always @* begin : lookup_proc
      integer s;
      integer w;
      integer e;
      l_cls = {(NW * NCLS){1'b0}};
      for (s = 0; s < NS; s = s + 1) begin
         for (w = 0; w < NW; w = w + 1) begin
            e = s * NW + w;
            l_hit[e] = t_set1h[s] && rpt_valid[e] &&
                       (rpt_tag[e] == t_tag) && (rpt_st[e] == t_st);
            l_g4[e]  = t_set1h[s] && w_way[w];
            if (!rpt_valid[e]) begin
               e_cls = C_FREE;
            end
            else begin
               case (rpt_state[e])
                  S_NOPRED: e_cls = C_NOPRED;
                  S_INIT:   e_cls = C_INIT;
                  S_TRANS:  e_cls = C_TRANS;
                  default:  e_cls = C_STEADY;
               endcase
            end
            if (t_set1h[s]) begin
               l_cls[w*NCLS +: NCLS] = l_cls[w*NCLS +: NCLS] | e_cls;
            end
         end
      end
      for (w = 0; w < NW; w = w + 1) begin
         if (t_ss[4] && w_way[w]) begin
            l_vcls[w*NCLS +: NCLS] = w_cls;
         end
         else begin
            l_vcls[w*NCLS +: NCLS] = l_cls[w*NCLS +: NCLS];
         end
         l_cand[w] = !(t_ss[2] && d_way[w]) && !(t_ss[3] && u_way[w]);
         l_rpl[w]  = (t_ss[2] && d_way[w]) || (t_ss[3] && u_way[w]) ||
                     (t_ss[4] && w_way[w]);
      end
   end
   assign tap_lo_x = {1'b0, tr_pa[PAGE_W-1:0]};
   assign t_lo_x   = {1'b0, t_lo};
   assign r_lo_x   = {1'b0, r_lo};
   assign d_lo_x   = {1'b0, d_lo};
   l1d_ks_add_q #(.W(STRIDE_W), .SUB(1)) u1_ks_add_q (
      .clk (clk),
      .a_d (tap_lo_x),
      .b_d (t_lo_x),
      .sum (l_dl1)
   );
   l1d_ks_add_q #(.W(STRIDE_W), .SUB(1)) u2_ks_add_q (
      .clk (clk),
      .a_d (tap_lo_x),
      .b_d (r_lo_x),
      .sum (l_dl2)
   );
   l1d_ks_add_q #(.W(STRIDE_W), .SUB(1)) u3_ks_add_q (
      .clk (clk),
      .a_d (tap_lo_x),
      .b_d (d_lo_x),
      .sum (l_dl3)
   );
   always @(posedge clk) begin : l_reg_proc
      if (rst) begin
         r_valid <= 1'b0;
      end
      else begin
         r_valid <= t_valid && !clear;
      end
      r_set   <= t_set;
      r_set1h <= t_set1h;
      r_tag   <= t_tag;
      r_st    <= t_st;
      r_lo    <= t_lo;
      r_ph    <= t_ph;
      r_ppn   <= t_ppn;
      r_hit   <= l_hit;
      r_g4    <= l_g4;
      r_cls   <= l_vcls;
      r_cand  <= l_cand;
      r_rpl   <= l_rpl;
      r_m[1]  <= r_valid && (r_key == t_key);
      r_m[2]  <= d_valid && (d_key == t_key);
      r_m[3]  <= u_valid && (u_key == t_key);
      r_m[4]  <= w_valid && (w_key == t_key);
      r_ss1   <= t_ss[1];
      r_sp[1] <= (r_ph == t_ph);
      r_sp[2] <= (d_ph == t_ph);
      r_sp[3] <= (u_ph == t_ph);
      r_dl1   <= l_dl1;
      r_dl2   <= l_dl2;
      r_dl3   <= l_dl3;
   end
   always @* begin : read_proc
      integer s;
      integer w;
      integer e;
      r_hitway    = WAY_ZERO;
      r_ht_stride = STRIDE_ZERO;
      r_ht_state  = S_INIT;
      r_ht_lo     = {PAGE_W{1'b0}};
      r_ht_ph     = {PH_W{1'b0}};
      r_g4_stride = STRIDE_ZERO;
      r_g4_state  = S_INIT;
      r_g4_lo     = {PAGE_W{1'b0}};
      r_g4_ph     = {PH_W{1'b0}};
      for (s = 0; s < NS; s = s + 1) begin
         for (w = 0; w < NW; w = w + 1) begin
            e = s * NW + w;
            r_hitway[w] = r_hitway[w] | r_hit[e];
            if (r_hit[e]) begin
               r_ht_stride = r_ht_stride | rpt_stride[e];
               r_ht_state  = r_ht_state  | rpt_state[e];
               r_ht_lo     = r_ht_lo     | rpt_lo[e];
               r_ht_ph     = r_ht_ph     | rpt_ph[e];
            end
            if (r_g4[e]) begin
               r_g4_stride = r_g4_stride | rpt_stride[e];
               r_g4_state  = r_g4_state  | rpt_state[e];
               r_g4_lo     = r_g4_lo     | rpt_lo[e];
               r_g4_ph     = r_g4_ph     | rpt_ph[e];
            end
         end
      end
      if (r_m[4]) begin
         r_rd_stride = r_g4_stride;
         r_rd_state  = r_g4_state;
         r_rd_lo     = r_g4_lo;
         r_rd_ph     = r_g4_ph;
      end
      else begin
         r_rd_stride = r_ht_stride;
         r_rd_state  = r_ht_state;
         r_rd_lo     = r_ht_lo;
         r_rd_ph     = r_ht_ph;
      end
   end
   always @* begin : victim_proc
      integer a;
      integer b;
      integer c;
      integer k;
      reg     lower;
      reg     same;
      for (a = 0; a < NW; a = a + 1) begin
         r_avail[a] = r_cand[a] && !(r_ss1 && d_way[a]);
      end
      r_hitok = ((r_hitway & ~r_rpl & ~(d_way & {NW{r_ss1}})) !=
                 WAY_ZERO);
      for (a = 0; a < NW; a = a + 1) begin
         r_vict[a] = r_avail[a];
         for (b = 0; b < NW; b = b + 1) begin
            if (b != a) begin
               lower = 1'b0;
               same  = 1'b0;
               for (c = 0; c < NCLS; c = c + 1) begin
                  same = same | (r_cls[a*NCLS + c] & r_cls[b*NCLS + c]);
                  for (k = 0; k < c; k = k + 1) begin
                     lower = lower | (r_cls[a*NCLS + c] & r_cls[b*NCLS + k]);
                  end
               end
               if (r_avail[b] && (lower || (same && (b < a)))) begin
                  r_vict[a] = 1'b0;
               end
            end
         end
      end
   end
   always @* begin : select_proc
      r_way   = r_vict;
      r_alloc = 1'b1;
      r_src   = FW_NONE;
      r_spm   = 1'b0;
      r_dlm   = STRIDE_ZERO;
      if (r_m[1]) begin
         r_way   = d_way;
         r_alloc = 1'b0;
         r_src   = FW_1;
         r_spm   = r_sp[1];
         r_dlm   = r_dl1;
      end
      else if (r_m[2]) begin
         r_way   = u_way;
         r_alloc = 1'b0;
         r_src   = FW_2;
         r_spm   = r_sp[2];
         r_dlm   = r_dl2;
      end
      else if (r_m[3]) begin
         r_way   = w_way;
         r_alloc = 1'b0;
         r_src   = FW_3;
         r_spm   = r_sp[3];
         r_dlm   = r_dl3;
      end
      else if (r_m[4]) begin
         r_way   = g_way;
         r_alloc = 1'b0;
      end
      else if (r_hitok) begin
         r_way   = r_hitway;
         r_alloc = 1'b0;
      end
      else begin
         r_way   = r_vict;
      end
   end
   always @(posedge clk) begin : r_reg_proc
      if (rst) begin
         d_valid <= 1'b0;
      end
      else begin
         d_valid <= r_valid && !clear;
      end
      d_set       <= r_set;
      d_set1h     <= r_set1h;
      d_tag       <= r_tag;
      d_st        <= r_st;
      d_lo        <= r_lo;
      d_ph        <= r_ph;
      d_ppn       <= r_ppn;
      d_way       <= r_way;
      d_alloc     <= r_alloc;
      d_src       <= r_src;
      d_spm       <= r_spm;
      d_dlm       <= r_dlm;
      d_rd_stride <= r_rd_stride;
      d_rd_state  <= r_rd_state;
      d_rd_lo     <= r_rd_lo;
      d_rd_ph     <= r_rd_ph;
   end
   assign r_rd_lo_x = {1'b0, r_rd_lo};
   assign d_rd_lo_x = {1'b0, d_rd_lo};
   l1d_ks_add_q #(.W(STRIDE_W), .SUB(1)) u4_ks_add_q (
      .clk (clk),
      .a_d (r_lo_x),
      .b_d (r_rd_lo_x),
      .sum (d_dlt)
   );
   l1d_add_eq #(.W(STRIDE_W)) u1_add_eq (
      .a  (d_rd_lo_x),
      .b  (d_rd_stride),
      .c  (d_lo_x),
      .eq (d_eqt)
   );
   always @* begin : fwd_cmp_proc
      d_none = (d_src == FW_NONE);
      d_c1z  = (d_dlm == STRIDE_ZERO);
      d_c2   = (d_dlm == w_nx_stride);
      d_c3   = (d_dlm == g_nx_stride);
      d_cf   = (d_dlm == f_nx_stride);
      d_cr   = (d_dlm == u_rd_stride);
      d_cm   = (d_dlm == u_dlm);
      d_cd   = (d_dlm == u_dlt);
      d_c1k  = (u_src[0] && d_c2) || (u_src[1] && d_c3) ||
               (u_src[2] && d_cf) || (u_none && d_cr);
      d_c1n  = (u_none ? (u_spt ? d_cd : d_c1z) : (u_spm ? d_cm : d_c1z));
   end
   always @(posedge clk) begin : d_reg_proc
      if (rst) begin
         u_valid <= 1'b0;
      end
      else begin
         u_valid <= d_valid && !clear;
      end
      u_set       <= d_set;
      u_set1h     <= d_set1h;
      u_tag       <= d_tag;
      u_st        <= d_st;
      u_lo        <= d_lo;
      u_ph        <= d_ph;
      u_ppn       <= d_ppn;
      u_way       <= d_way;
      u_alloc     <= d_alloc;
      u_src       <= d_src;
      u_none      <= d_none;
      u_spm       <= d_spm;
      u_dlm       <= d_dlm;
      u_spt       <= (d_ph == d_rd_ph);
      u_dlt       <= d_dlt;
      u_ct        <= (d_ph == d_rd_ph) && d_eqt;
      u_c1k       <= d_c1k;
      u_c1n       <= d_c1n;
      u_c1z       <= d_c1z;
      u_c2        <= d_c2;
      u_c3        <= d_c3;
      u_rd_stride <= d_rd_stride;
      u_rd_state  <= d_rd_state;
   end
   always @* begin : update_proc
      e_stride  = ({STRIDE_W{u_src[0]}} & w_nx_stride) |
                  ({STRIDE_W{u_src[1]}} & g_nx_stride) |
                  ({STRIDE_W{u_src[2]}} & f_nx_stride) |
                  ({STRIDE_W{u_none}}   & u_rd_stride);
      e_state   = ({ST_W{u_src[0]}} & w_nx_state) |
                  ({ST_W{u_src[1]}} & g_nx_state) |
                  ({ST_W{u_src[2]}} & f_nx_state) |
                  ({ST_W{u_none}}   & u_rd_state);
      e_sp      = u_none ? u_spt : u_spm;
      e_dl      = u_none ? u_dlt : u_dlm;
      correct   = (u_src[0] && u_spm && ((w_alloc && u_c1z) ||
                                         (w_keep && u_c1k) ||
                                         (!w_alloc && !w_keep && u_c1n))) ||
                  (u_src[1] && u_spm && u_c2) ||
                  (u_src[2] && u_spm && u_c3) ||
                  (u_none && u_ct);
      new_dl    = e_sp ? e_dl : STRIDE_ZERO;
      keep      = !u_alloc && (correct || (e_state == S_STEADY));
      if (u_alloc) begin
         nx_stride = STRIDE_ZERO;
      end
      else if (keep) begin
         nx_stride = e_stride;
      end
      else begin
         nx_stride = new_dl;
      end
      case (e_state)
         S_INIT:   nx_state = correct ? S_STEADY : S_TRANS;
         S_TRANS:  nx_state = correct ? S_STEADY : S_NOPRED;
         S_STEADY: nx_state = correct ? S_STEADY : S_INIT;
         default:  nx_state = correct ? S_TRANS  : S_NOPRED;
      endcase
      if (u_alloc) begin
         nx_state  = S_INIT;
      end
      case (nx_state)
         S_NOPRED: nx_cls = C_NOPRED;
         S_INIT:   nx_cls = C_INIT;
         S_TRANS:  nx_cls = C_TRANS;
         default:  nx_cls = C_STEADY;
      endcase
      issue = !u_alloc && correct && (e_state != S_NOPRED) &&
              (e_stride != STRIDE_ZERO);
   end
   always @(posedge clk) begin : u_reg_proc
      if (rst) begin
         w_valid <= 1'b0;
         w_issue <= 1'b0;
      end
      else begin
         w_valid <= u_valid && !clear;
         w_issue <= u_valid && !clear && issue;
      end
      w_set       <= u_set;
      w_set1h     <= u_set1h;
      w_tag       <= u_tag;
      w_st        <= u_st;
      w_lo        <= u_lo;
      w_ph        <= u_ph;
      w_ppn       <= u_ppn;
      w_way       <= u_way;
      w_cls       <= nx_cls;
      w_nx_stride <= nx_stride;
      w_nx_state  <= nx_state;
      w_stride    <= e_stride;
      w_keep      <= keep;
      w_alloc     <= u_alloc;
   end
   always @(posedge clk) begin : table_ctl_proc
      integer s;
      integer w;
      if (rst || clear) begin
         rpt_valid <= {ENTRIES{1'b0}};
         for (s = 0; s < ENTRIES; s = s + 1) begin
            rpt_state[s] <= S_INIT;
         end
      end
      else begin
         for (s = 0; s < NS; s = s + 1) begin
            for (w = 0; w < NW; w = w + 1) begin
               if (w_valid && w_set1h[s] && w_way[w]) begin
                  rpt_valid[s * NW + w] <= 1'b1;
                  rpt_state[s * NW + w] <= w_nx_state;
               end
            end
         end
      end
   end
   always @(posedge clk) begin : table_data_proc
      integer s;
      integer w;
      for (s = 0; s < NS; s = s + 1) begin
         for (w = 0; w < NW; w = w + 1) begin
            if (w_valid && w_set1h[s] && w_way[w]) begin
               rpt_st[s * NW + w]     <= w_st;
               rpt_tag[s * NW + w]    <= w_tag;
               rpt_stride[s * NW + w] <= w_nx_stride;
               rpt_lo[s * NW + w]     <= w_lo;
               rpt_ph[s * NW + w]     <= w_ph;
            end
         end
      end
   end
   always @(posedge clk) begin : w_reg_proc
      if (rst) begin
         g_issue <= 1'b0;
      end
      else begin
         g_issue <= w_issue && !clear;
      end
      g_way       <= w_way;
      g_nx_stride <= w_nx_stride;
      g_nx_state  <= w_nx_state;
      g_st        <= w_st;
      g_cur       <= w_lo[PAGE_W-1:OFFSET_W];
      g_ph        <= w_ph;
      g_ppn       <= w_ppn;
   end
   assign w_lo_x = {{(TGT_W - PAGE_W){1'b0}}, w_lo};
   assign w_step = {{(TGT_W - STRIDE_W){w_stride[STRIDE_W-1]}}, w_stride}
                   << DSH;
   l1d_ks_add_q #(.W(TGT_W), .SUB(0)) u5_ks_add_q (
      .clk (clk),
      .a_d (w_lo_x),
      .b_d (w_step),
      .sum (g_tgt)
   );
   always @* begin : page_proc
      g_in_page = (g_tgt[TGT_W-1:PAGE_W] == {(TGT_W - PAGE_W){1'b0}});
   end
   always @(posedge clk) begin : g_reg_proc
      if (rst) begin
         f_valid <= 1'b0;
      end
      else begin
         f_valid <= g_issue && !clear;
      end
      f_inp       <= g_in_page;
      f_nx_stride <= g_nx_stride;
      f_nx_state  <= g_nx_state;
      f_st        <= g_st;
      f_ppn       <= g_ppn;
      f_lip       <= g_tgt[PAGE_W-1:OFFSET_W];
      f_cur       <= g_cur;
      f_ph        <= g_ph;
   end
   assign f_key = {f_ph, f_lip};
   always @* begin : filter_proc
      integer i;
      f_dup = x_pass && (x_key == f_key);
      for (i = 0; i < FILT_DEPTH - 1; i = i + 1) begin
         if (filt_v[i] && (filt_key[i] == f_key)) begin
            f_dup = 1'b1;
         end
      end
      if (!x_pass && filt_v[FILT_DEPTH-1] &&
          (filt_key[FILT_DEPTH-1] == f_key)) begin
         f_dup = 1'b1;
      end
      f_pass = f_valid && f_inp && !f_dup && (f_lip != f_cur);
   end
   always @(posedge clk) begin : f_reg_proc
      if (rst) begin
         x_pass <= 1'b0;
      end
      else begin
         x_pass <= f_pass && !clear;
      end
      x_key <= f_key;
      x_st  <= f_st;
      x_ppn <= f_ppn;
      x_lip <= f_lip;
   end
   always @(posedge clk) begin : filt_v_proc
      if (rst || clear) begin
         filt_v <= {FILT_DEPTH{1'b0}};
      end
      else if (x_pass) begin
         filt_v <= {filt_v[FILT_DEPTH-2:0], 1'b1};
      end
   end
   always @(posedge clk) begin : filt_key_proc
      integer i;
      if (x_pass) begin
         filt_key[0] <= x_key;
         for (i = 1; i < FILT_DEPTH; i = i + 1) begin
            filt_key[i] <= filt_key[i-1];
         end
      end
   end
   always @(posedge clk) begin : out_valid_proc
      if (rst || clear) begin
         pf_valid <= 1'b0;
      end
      else if (x_pass) begin
         pf_valid <= 1'b1;
      end
      else if (pf_ready) begin
         pf_valid <= 1'b0;
      end
   end
   always @(posedge clk) begin : out_data_proc
      if (x_pass) begin
         pf_addr   <= {{PADA_W{1'b0}}, x_ppn, x_lip, {OFFSET_W{1'b0}}};
         pf_unique <= x_st;
      end
   end
`ifdef L1D_DEBUG
   initial begin : param_chk_proc
      if ((1 << SET_W) != NS || (1 << $clog2(NW)) != NW ||
          (1 << DSH) != DIST || NW < 4 || FILT_DEPTH < 2)
         $display("L1D PF_STRIDE %m ERROR parameter assumption A2");
      if (PA_W > ADDR_W || PA_W <= PAGE_W || KEY_W <= LIP_W)
         $display("L1D PF_STRIDE %m ERROR parameter assumption A3");
   end
   always @(posedge clk) begin : watch_proc
      if (!rst && r_valid && ((r_way == WAY_ZERO) ||
          ((r_way & (r_way - 1'b1)) != WAY_ZERO)))
         $display("[%0t] L1D PF_STRIDE %m ERROR way not one-hot", $time);
      if (!rst && r_valid && r_m[4] && !r_m[1] && !r_m[2] && !r_m[3] &&
          r_ss1 && ((g_way & d_way) != WAY_ZERO))
         $display("[%0t] L1D PF_STRIDE %m ERROR event 4's way replaced",
                  $time);
   end
`endif
endmodule
`default_nettype wire
`endif
