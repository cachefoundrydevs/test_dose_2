`ifndef L1D_PF3_STRIDE_V
`define L1D_PF3_STRIDE_V
`default_nettype none
module l1d_pf3_stride #(
    parameter NB         = 4,
    parameter PC_W       = 64,
    parameter ADDR_W     = 64,
    parameter PA_W       = 56,
    parameter LINE_BYTES = 64,
    parameter PAGE_BYTES = 4096,
    parameter RPT_SETS   = 16,
    parameter RPT_WAYS   = 4,
    parameter TAG_W      = 12,
    parameter PC_LSB     = 1,
    parameter DIST       = 2,
    parameter FILT_DEPTH = 4,
    parameter PH_W       = 10
) (
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      pf_enable,
    input  wire                      clear,
    input  wire [NB-1:0]             train_valid,
    input  wire [NB-1:0]             train_no_train,
    input  wire [NB-1:0]             train_is_store,
    input  wire [NB*PC_W-1:0]        train_pc,
    input  wire [NB*ADDR_W-1:0]      train_addr,
    output wire                      cand_valid,
    output wire [ADDR_W-$clog2(LINE_BYTES)-1:0] cand_line,
    output wire [NB-1:0]             cand_bank,
    output wire                      cand_unique
);
    localparam NS       = RPT_SETS;
    localparam NW       = RPT_WAYS;
    localparam ENTRIES  = NS * NW;
    localparam SET_W    = $clog2(NS);
    localparam OFFSET_W = $clog2(LINE_BYTES);
    localparam PAGE_W   = $clog2(PAGE_BYTES);
    localparam LIP_W    = PAGE_W - OFFSET_W;
    localparam PPN_W    = PA_W - PAGE_W;
    localparam LINE_W   = ADDR_W - OFFSET_W;
    localparam PAD_W    = ADDR_W - PA_W;
    localparam STRIDE_W = PAGE_W + 1;
    localparam TGT_W    = PAGE_W + 3;
    localparam LO3_W    = PAGE_W + 2;
    localparam DSH      = $clog2(DIST);
    localparam FOLD_LSB = PC_LSB + SET_W;
    localparam FOLD_W   = PC_W - FOLD_LSB;
    localparam KEY_W    = SET_W + TAG_W + 1;
    localparam [1:0] S_INIT   = 2'd0;
    localparam [1:0] S_TRANS  = 2'd1;
    localparam [1:0] S_STEADY = 2'd2;
    localparam [2:0] RANK_INIT = 3'd2;
    reg  [NB-1:0]        lane_pick;
    reg                  lane_seen;
    reg  [NB*TAG_W-1:0]  lane_tag;
    reg  [NB*PH_W-1:0]   lane_ph;
    wire [NB*LO3_W-1:0]  lane_lo3;
    reg                  pick_any;
    reg  [SET_W-1:0]     pick_set;
    reg  [TAG_W-1:0]     pick_tag;
    reg                  pick_st;
    reg  [PAGE_W-1:0]    pick_lo;
    reg  [LO3_W-1:0]     pick_lo3;
    reg  [PH_W-1:0]      pick_ph;
    reg  [PPN_W-1:0]     pick_ppn;
    reg  [NS-1:0]        pick_set1h;
    integer              lane_idx;
    integer              bit_idx;
    integer              set_idx;
    reg                  e1_vld;
    reg  [SET_W-1:0]     e1_set;
    reg  [NS-1:0]        e1_set1h;
    reg  [TAG_W-1:0]     e1_tag;
    reg                  e1_st;
    reg  [PAGE_W-1:0]    e1_lo;
    reg  [LO3_W-1:0]     e1_lo3;
    reg  [PH_W-1:0]      e1_ph;
    reg  [PPN_W-1:0]     e1_ppn;
    reg                  e2_vld;
    reg                  e2_alloc;
    reg  [SET_W-1:0]     e2_set;
    reg  [NS-1:0]        e2_set1h;
    reg  [NW-1:0]        e2_way;
    reg  [TAG_W-1:0]     e2_tag;
    reg                  e2_st;
    reg  [PAGE_W-1:0]    e2_lo;
    reg  [LO3_W-1:0]     e2_lo3;
    reg  [PH_W-1:0]      e2_ph;
    reg  [PPN_W-1:0]     e2_ppn;
    wire [ENTRIES-1:0]   ent_set_on;
    wire [ENTRIES-1:0]   ent_mask;
    wire [ENTRIES-1:0]   ent_hit;
    wire [ENTRIES*3-1:0] ent_class;
    wire [ENTRIES-1:0]   ent_fire_q;
    wire [ENTRIES-1:0]   ent_dup_prev_q;
    wire [ENTRIES-1:0]   ent_filt_last_q;
    wire [ENTRIES*LIP_W-1:0] ent_tgt_lip_q;
    wire [ENTRIES*NB-1:0]    ent_tgt_bank_q;
    wire [ENTRIES-1:0]   ent_aw_en;
    wire                 any_hit;
    wire                 fwd_alloc;
    wire                 alloc_next;
    reg  [NW*3-1:0]      way_class;
    reg  [NW-1:0]        victim_way;
    reg                  way_beaten;
    integer              way_idx;
    integer              other_idx;
    wire                 virt_same_page;
    wire                 virt_correct;
    wire [STRIDE_W-1:0]  virt_delta;
    wire [TGT_W-1:0]     virt_s3;
    wire [TGT_W-1:0]     virt_tgt;
    wire [STRIDE_W-1:0]  e1_lo_ext;
    wire [STRIDE_W-1:0]  e2_lo_ext;
    wire [TGT_W-1:0]     e1_lo4_t;
    wire [TGT_W-1:0]     e1_lo3_t;
    wire [TGT_W-1:0]     e2_lo3_t;
    reg  [1:0]           aw_state;
    reg  [STRIDE_W-1:0]  aw_stride;
    reg  [TGT_W-1:0]     aw_s3;
    reg  [TGT_W-1:0]     aw_tgt;
    reg  [PAGE_W-1:0]    aw_lo;
    reg  [LO3_W-1:0]     aw_lo3;
    reg  [PH_W-1:0]      aw_ph;
    reg  [FILT_DEPTH-1:0]       filt_vld;
    reg  [FILT_DEPTH*PH_W-1:0]  filt_ph;
    reg  [FILT_DEPTH*LIP_W-1:0] filt_lip;
    wire [FILT_DEPTH-1:0]       filt_pm;
    wire                        prev_pm;
    reg                         prev_ins_q;
    wire [ENTRIES-1:0]   fire_eff;
    reg  [LIP_W-1:0]     cand_lip;
    reg  [NB-1:0]        cand_bank_or;
    integer              ent_idx;
    always @* begin : lane_fold_proc
        lane_tag = {(NB*TAG_W){1'b0}};
        lane_ph  = {(NB*PH_W){1'b0}};
        for (lane_idx = 0; lane_idx < NB; lane_idx = lane_idx + 1) begin
            for (bit_idx = 0; bit_idx < FOLD_W; bit_idx = bit_idx + 1) begin
                lane_tag[lane_idx*TAG_W + (bit_idx % TAG_W)] =
                    lane_tag[lane_idx*TAG_W + (bit_idx % TAG_W)]
                    ^ train_pc[lane_idx*PC_W + FOLD_LSB + bit_idx];
            end
            for (bit_idx = 0; bit_idx < PPN_W; bit_idx = bit_idx + 1) begin
                lane_ph[lane_idx*PH_W + (bit_idx % PH_W)] =
                    lane_ph[lane_idx*PH_W + (bit_idx % PH_W)]
                    ^ train_addr[lane_idx*ADDR_W + PAGE_W + bit_idx];
            end
        end
    end
    genvar lane_g;
    generate
        for (lane_g = 0; lane_g < NB; lane_g = lane_g + 1) begin : g_lo3
            wire [LO3_W-1:0] lo_x1;
            wire [LO3_W-1:0] lo_x2;
            assign lo_x1 = {2'b00, train_addr[lane_g*ADDR_W +: PAGE_W]};
            assign lo_x2 = {1'b0, train_addr[lane_g*ADDR_W +: PAGE_W], 1'b0};
            l1d_pf3_ks_add #(.W(LO3_W), .SUB(0)) u_lo3 (
                .a   (lo_x1),
                .b   (lo_x2),
                .sum (lane_lo3[lane_g*LO3_W +: LO3_W])
            );
        end
    endgenerate
    always @* begin : lane_pick_proc
        lane_seen = 1'b0;
        pick_any  = 1'b0;
        pick_set  = {SET_W{1'b0}};
        pick_tag  = {TAG_W{1'b0}};
        pick_st   = 1'b0;
        pick_lo   = {PAGE_W{1'b0}};
        pick_lo3  = {LO3_W{1'b0}};
        pick_ph   = {PH_W{1'b0}};
        pick_ppn  = {PPN_W{1'b0}};
        for (lane_idx = 0; lane_idx < NB; lane_idx = lane_idx + 1) begin
            lane_pick[lane_idx] = train_valid[lane_idx]
                                  & ~train_no_train[lane_idx] & ~lane_seen;
            lane_seen = lane_seen
                        | (train_valid[lane_idx] & ~train_no_train[lane_idx]);
        end
        for (lane_idx = 0; lane_idx < NB; lane_idx = lane_idx + 1) begin
            pick_any = pick_any | lane_pick[lane_idx];
            pick_set = pick_set | ({SET_W{lane_pick[lane_idx]}}
                       & train_pc[lane_idx*PC_W + PC_LSB +: SET_W]);
            pick_tag = pick_tag | ({TAG_W{lane_pick[lane_idx]}}
                       & lane_tag[lane_idx*TAG_W +: TAG_W]);
            pick_st  = pick_st | (lane_pick[lane_idx]
                       & train_is_store[lane_idx]);
            pick_lo  = pick_lo | ({PAGE_W{lane_pick[lane_idx]}}
                       & train_addr[lane_idx*ADDR_W +: PAGE_W]);
            pick_lo3 = pick_lo3 | ({LO3_W{lane_pick[lane_idx]}}
                       & lane_lo3[lane_idx*LO3_W +: LO3_W]);
            pick_ph  = pick_ph | ({PH_W{lane_pick[lane_idx]}}
                       & lane_ph[lane_idx*PH_W +: PH_W]);
            pick_ppn = pick_ppn | ({PPN_W{lane_pick[lane_idx]}}
                       & train_addr[lane_idx*ADDR_W + PAGE_W +: PPN_W]);
        end
        for (set_idx = 0; set_idx < NS; set_idx = set_idx + 1) begin
            pick_set1h[set_idx] = (pick_set == set_idx[SET_W-1:0]);
        end
    end
    always @(posedge clk) begin : s1_reg_proc
        if (rst) begin
            e1_vld <= 1'b0;
        end
        else begin
            e1_vld <= pick_any & pf_enable & ~clear;
        end
        e1_set   <= pick_set;
        e1_set1h <= pick_set1h;
        e1_tag   <= pick_tag;
        e1_st    <= pick_st;
        e1_lo    <= pick_lo;
        e1_lo3   <= pick_lo3;
        e1_ph    <= pick_ph;
        e1_ppn   <= pick_ppn;
    end
    assign filt_pm[0] = filt_vld[0] & (filt_ph[0 +: PH_W] == e1_ph);
    genvar slot_g;
    generate
        for (slot_g = 1; slot_g < FILT_DEPTH; slot_g = slot_g + 1) begin : g_filt_pm
            assign filt_pm[slot_g] = filt_vld[slot_g]
                                     & (filt_ph[slot_g*PH_W +: PH_W] == e1_ph);
        end
    endgenerate
    assign prev_pm = e2_vld & (e2_ph == e1_ph);
    genvar ent_g;
    generate
        for (ent_g = 0; ent_g < ENTRIES; ent_g = ent_g + 1) begin : g_entry
            assign ent_set_on[ent_g] = e1_vld & e1_set1h[ent_g / NW];
            assign ent_mask[ent_g]   = e2_vld & e2_alloc
                                       & e2_set1h[ent_g / NW] & e2_way[ent_g % NW];
            assign ent_aw_en[ent_g]  = ent_mask[ent_g];
            l1d_pf3_stride_entry #(
                .TAG_W      (TAG_W),
                .PAGE_W     (PAGE_W),
                .OFFSET_W   (OFFSET_W),
                .PH_W       (PH_W),
                .DSH        (DSH),
                .FILT_DEPTH (FILT_DEPTH),
                .NB         (NB)
            ) u_entry (
                .clk             (clk),
                .rst             (rst),
                .clear           (clear),
                .ev_set_on       (ent_set_on[ent_g]),
                .ev_tag          (e1_tag),
                .ev_st           (e1_st),
                .ev_lo           (e1_lo),
                .ev_lo3          (e1_lo3),
                .ev_ph           (e1_ph),
                .ev_mask         (ent_mask[ent_g]),
                .filt_main_pm    (filt_pm[FILT_DEPTH-2:0]),
                .filt_main_lip   (filt_lip[(FILT_DEPTH-1)*LIP_W-1:0]),
                .filt_last_pm    (filt_pm[FILT_DEPTH-1]),
                .filt_last_lip   (filt_lip[(FILT_DEPTH-1)*LIP_W +: LIP_W]),
                .prev_pm         (prev_pm),
                .prev_lip        (cand_lip),
                .aw_en           (ent_aw_en[ent_g]),
                .aw_tag          (e2_tag),
                .aw_st           (e2_st),
                .aw_state        (aw_state),
                .aw_stride       (aw_stride),
                .aw_s3           (aw_s3),
                .aw_tgt          (aw_tgt),
                .aw_lo           (aw_lo),
                .aw_lo3          (aw_lo3),
                .aw_ph           (aw_ph),
                .hit             (ent_hit[ent_g]),
                .class_rank      (ent_class[ent_g*3 +: 3]),
                .fire_q          (ent_fire_q[ent_g]),
                .dup_prev_q      (ent_dup_prev_q[ent_g]),
                .filt_last_q     (ent_filt_last_q[ent_g]),
                .tgt_prev_lip_q  (ent_tgt_lip_q[ent_g*LIP_W +: LIP_W]),
                .tgt_prev_bank_q (ent_tgt_bank_q[ent_g*NB +: NB])
            );
        end
    endgenerate
    assign any_hit    = |ent_hit;
    assign fwd_alloc  = e1_vld & e2_vld & e2_alloc & (e1_set == e2_set)
                        & (e1_tag == e2_tag) & (e1_st == e2_st);
    assign alloc_next = e1_vld & ~any_hit & ~fwd_alloc;
    always @* begin : victim_proc
        way_class = {(NW*3){1'b0}};
        for (way_idx = 0; way_idx < NW; way_idx = way_idx + 1) begin
            for (set_idx = 0; set_idx < NS; set_idx = set_idx + 1) begin
                way_class[way_idx*3 +: 3] = way_class[way_idx*3 +: 3]
                    | ({3{e1_set1h[set_idx]}}
                       & ent_class[(set_idx*NW + way_idx)*3 +: 3]);
            end
            if (e2_vld && e2_alloc && (e2_set == e1_set) && e2_way[way_idx]) begin
                way_class[way_idx*3 +: 3] = RANK_INIT;
            end
        end
        for (way_idx = 0; way_idx < NW; way_idx = way_idx + 1) begin
            way_beaten = 1'b0;
            for (other_idx = 0; other_idx < NW; other_idx = other_idx + 1) begin
                if (other_idx != way_idx) begin
                    if ((way_class[other_idx*3 +: 3] < way_class[way_idx*3 +: 3])
                        || ((way_class[other_idx*3 +: 3] == way_class[way_idx*3 +: 3])
                            && (other_idx < way_idx))) begin
                        way_beaten = 1'b1;
                    end
                end
            end
            victim_way[way_idx] = ~way_beaten;
        end
    end
    assign e1_lo_ext = {1'b0, e1_lo};
    assign e2_lo_ext = {1'b0, e2_lo};
    assign e1_lo4_t  = {1'b0, e1_lo, 2'b00};
    assign e1_lo3_t  = {1'b0, e1_lo3};
    assign e2_lo3_t  = {1'b0, e2_lo3};
    assign virt_same_page = (e1_ph == e2_ph);
    assign virt_correct   = virt_same_page & (e1_lo == e2_lo);
    l1d_pf3_ks_add #(.W(STRIDE_W), .SUB(1)) u_virt_delta (
        .a   (e1_lo_ext),
        .b   (e2_lo_ext),
        .sum (virt_delta)
    );
    l1d_pf3_ks_add #(.W(TGT_W), .SUB(1)) u_virt_s3 (
        .a   (e1_lo3_t),
        .b   (e2_lo3_t),
        .sum (virt_s3)
    );
    l1d_pf3_ks_add #(.W(TGT_W), .SUB(1)) u_virt_tgt (
        .a   (e1_lo4_t),
        .b   (e2_lo3_t),
        .sum (virt_tgt)
    );
    always @* begin : alloc_write_proc
        if (fwd_alloc) begin
            aw_state = virt_correct ? S_STEADY : S_TRANS;
            aw_lo    = e1_lo;
            aw_lo3   = e1_lo3;
            aw_ph    = e1_ph;
            if (!virt_correct && virt_same_page) begin
                aw_stride = virt_delta;
                aw_s3     = virt_s3;
                aw_tgt    = virt_tgt;
            end
            else begin
                aw_stride = {STRIDE_W{1'b0}};
                aw_s3     = {TGT_W{1'b0}};
                aw_tgt    = {{(TGT_W-PAGE_W){1'b0}}, e1_lo};
            end
        end
        else begin
            aw_state  = S_INIT;
            aw_stride = {STRIDE_W{1'b0}};
            aw_s3     = {TGT_W{1'b0}};
            aw_tgt    = {{(TGT_W-PAGE_W){1'b0}}, e2_lo};
            aw_lo     = e2_lo;
            aw_lo3    = e2_lo3;
            aw_ph     = e2_ph;
        end
    end
    always @(posedge clk) begin : s2_reg_proc
        if (rst) begin
            e2_vld   <= 1'b0;
            e2_alloc <= 1'b0;
        end
        else begin
            e2_vld   <= e1_vld & ~clear;
            e2_alloc <= alloc_next & ~clear;
        end
        e2_set   <= e1_set;
        e2_set1h <= e1_set1h;
        e2_way   <= victim_way;
        e2_tag   <= e1_tag;
        e2_st    <= e1_st;
        e2_lo    <= e1_lo;
        e2_lo3   <= e1_lo3;
        e2_ph    <= e1_ph;
        e2_ppn   <= e1_ppn;
    end
    assign fire_eff = ent_fire_q
                      & ~(ent_filt_last_q & {ENTRIES{~prev_ins_q}})
                      & ~(ent_dup_prev_q & {ENTRIES{prev_ins_q}});
    always @* begin : cand_read_proc
        cand_lip     = {LIP_W{1'b0}};
        cand_bank_or = {NB{1'b0}};
        for (ent_idx = 0; ent_idx < ENTRIES; ent_idx = ent_idx + 1) begin
            cand_lip     = cand_lip | ({LIP_W{ent_fire_q[ent_idx]}}
                           & ent_tgt_lip_q[ent_idx*LIP_W +: LIP_W]);
            cand_bank_or = cand_bank_or | ({NB{ent_fire_q[ent_idx]}}
                           & ent_tgt_bank_q[ent_idx*NB +: NB]);
        end
    end
    assign cand_valid   = (|fire_eff) & pf_enable & ~clear;
    assign cand_line    = {{PAD_W{1'b0}}, e2_ppn, cand_lip};
    assign cand_bank    = cand_bank_or;
    assign cand_unique  = e2_st;
    always @(posedge clk) begin : filter_proc
        if (rst || clear) begin
            filt_vld   <= {FILT_DEPTH{1'b0}};
            prev_ins_q <= 1'b0;
        end
        else begin
            prev_ins_q <= cand_valid;
            if (cand_valid) begin
                filt_vld <= {filt_vld[FILT_DEPTH-2:0], 1'b1};
            end
        end
        if (cand_valid) begin
            filt_ph  <= {filt_ph[(FILT_DEPTH-1)*PH_W-1:0], e2_ph};
            filt_lip <= {filt_lip[(FILT_DEPTH-1)*LIP_W-1:0], cand_lip};
        end
    end
`ifdef L1D_DEBUG
    always @(posedge clk) begin : debug_proc
        if (!rst) begin
            if ((ent_hit & (ent_hit - 1'b1)) != {ENTRIES{1'b0}}) begin
                $display("[%0t] L1D PF3_STRIDE ERROR two entries hit", $time);
            end
            if ((ent_fire_q & (ent_fire_q - 1'b1)) != {ENTRIES{1'b0}}) begin
                $display("[%0t] L1D PF3_STRIDE ERROR two entries fired", $time);
            end
            if (e1_vld && fwd_alloc && any_hit) begin
                $display("[%0t] L1D PF3_STRIDE ERROR hit beside the new entry",
                         $time);
            end
        end
    end
`endif
endmodule
`default_nettype wire
`endif
