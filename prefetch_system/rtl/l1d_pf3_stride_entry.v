`ifndef L1D_PF3_STRIDE_ENTRY_V
`define L1D_PF3_STRIDE_ENTRY_V
`default_nettype none
module l1d_pf3_stride_entry #(
    parameter TAG_W      = 12,
    parameter PAGE_W     = 12,
    parameter OFFSET_W   = 6,
    parameter PH_W       = 10,
    parameter DSH        = 1,
    parameter FILT_DEPTH = 4,
    parameter NB         = 4
) (
    input  wire                                clk,
    input  wire                                rst,
    input  wire                                clear,
    input  wire                                ev_set_on,
    input  wire [TAG_W-1:0]                    ev_tag,
    input  wire                                ev_st,
    input  wire [PAGE_W-1:0]                   ev_lo,
    input  wire [PAGE_W+1:0]                   ev_lo3,
    input  wire [PH_W-1:0]                     ev_ph,
    input  wire                                ev_mask,
    input  wire [FILT_DEPTH-2:0]               filt_main_pm,
    input  wire [(FILT_DEPTH-1)*(PAGE_W-OFFSET_W)-1:0] filt_main_lip,
    input  wire                                filt_last_pm,
    input  wire [PAGE_W-OFFSET_W-1:0]          filt_last_lip,
    input  wire                                prev_pm,
    input  wire [PAGE_W-OFFSET_W-1:0]          prev_lip,
    input  wire                                aw_en,
    input  wire [TAG_W-1:0]                    aw_tag,
    input  wire                                aw_st,
    input  wire [1:0]                          aw_state,
    input  wire [PAGE_W:0]                     aw_stride,
    input  wire [PAGE_W+2:0]                   aw_s3,
    input  wire [PAGE_W+2:0]                   aw_tgt,
    input  wire [PAGE_W-1:0]                   aw_lo,
    input  wire [PAGE_W+1:0]                   aw_lo3,
    input  wire [PH_W-1:0]                     aw_ph,
    output wire                                hit,
    output reg  [2:0]                          class_rank,
    output reg                                 fire_q,
    output reg                                 dup_prev_q,
    output reg                                 filt_last_q,
    output reg  [PAGE_W-OFFSET_W-1:0]          tgt_prev_lip_q,
    output reg  [NB-1:0]                       tgt_prev_bank_q
);
    localparam STRIDE_W = PAGE_W + 1;
    localparam TGT_W    = PAGE_W + 3;
    localparam LO3_W    = PAGE_W + 2;
    localparam LIP_W    = PAGE_W - OFFSET_W;
    localparam BANK_W   = $clog2(NB);
    localparam [1:0] S_INIT   = 2'd0;
    localparam [1:0] S_TRANS  = 2'd1;
    localparam [1:0] S_STEADY = 2'd2;
    localparam [1:0] S_NOPRED = 2'd3;
    reg                  valid_q;
    reg                  st_q;
    reg  [TAG_W-1:0]     tag_q;
    reg  [1:0]           state_q;
    reg  [STRIDE_W-1:0]  stride_q;
    reg  [TGT_W-1:0]     s3_q;
    reg  [TGT_W-1:0]     tgt_q;
    reg  [PAGE_W-1:0]    lo_q;
    reg  [LO3_W-1:0]     lo3_q;
    reg  [PH_W-1:0]      ph_q;
    wire                 key_match;
    wire                 same_page;
    wire                 stride_ok;
    wire                 correct;
    wire                 keep;
    wire                 armed;
    wire                 in_page;
    wire                 own_line;
    wire [LIP_W-1:0]     tgt_lip;
    reg                  filt_main;
    wire [STRIDE_W-1:0]  lo_ext;
    wire [STRIDE_W-1:0]  ev_lo_ext;
    wire [STRIDE_W-1:0]  delta;
    wire [TGT_W-1:0]     ev_lo_t;
    wire [TGT_W-1:0]     ev_lo4_t;
    wire [TGT_W-1:0]     ev_lo3_t;
    wire [TGT_W-1:0]     lo3_t;
    wire [TGT_W-1:0]     tgt_keep;
    wire [TGT_W-1:0]     tgt_new;
    wire [TGT_W-1:0]     s3_new;
    reg  [1:0]           state_next;
    reg  [STRIDE_W-1:0]  stride_next;
    reg  [TGT_W-1:0]     s3_next;
    reg  [TGT_W-1:0]     tgt_next;
    wire                 update;
    assign key_match = ev_set_on & valid_q & (tag_q == ev_tag) & (st_q == ev_st);
    assign hit       = key_match & ~ev_mask;
    assign update    = hit;
    assign same_page = (ph_q == ev_ph);
    assign lo_ext    = {1'b0, lo_q};
    assign ev_lo_ext = {1'b0, ev_lo};
    l1d_pf3_add_eq #(.W(STRIDE_W)) u_stride_check (
        .a  (lo_ext),
        .b  (stride_q),
        .c  (ev_lo_ext),
        .eq (stride_ok)
    );
    assign correct  = same_page & stride_ok;
    assign keep     = correct | (state_q == S_STEADY);
    assign armed    = (state_q != S_NOPRED) & (stride_q != {STRIDE_W{1'b0}});
    assign tgt_lip  = tgt_q[PAGE_W-1:OFFSET_W];
    assign in_page  = (tgt_q[TGT_W-1:PAGE_W] == {(TGT_W-PAGE_W){1'b0}});
    assign own_line = (tgt_lip == ev_lo[PAGE_W-1:OFFSET_W]);
    always @* begin : filter_proc
        integer slot_idx;
        filt_main = 1'b0;
        for (slot_idx = 0; slot_idx < FILT_DEPTH - 1; slot_idx = slot_idx + 1) begin
            if (filt_main_pm[slot_idx]
                && (filt_main_lip[slot_idx*LIP_W +: LIP_W] == tgt_lip)) begin
                filt_main = 1'b1;
            end
        end
    end
    assign ev_lo_t  = {{(TGT_W-PAGE_W){1'b0}}, ev_lo};
    assign ev_lo4_t = {1'b0, ev_lo, 2'b00};
    assign ev_lo3_t = {1'b0, ev_lo3};
    assign lo3_t    = {1'b0, lo3_q};
    l1d_pf3_ks_add #(.W(STRIDE_W), .SUB(1)) u_delta (
        .a   (ev_lo_ext),
        .b   (lo_ext),
        .sum (delta)
    );
    l1d_pf3_ks_add #(.W(TGT_W), .SUB(0)) u_tgt_keep (
        .a   (ev_lo_t),
        .b   (s3_q),
        .sum (tgt_keep)
    );
    l1d_pf3_ks_add #(.W(TGT_W), .SUB(1)) u_tgt_new (
        .a   (ev_lo4_t),
        .b   (lo3_t),
        .sum (tgt_new)
    );
    l1d_pf3_ks_add #(.W(TGT_W), .SUB(1)) u_s3_new (
        .a   (ev_lo3_t),
        .b   (lo3_t),
        .sum (s3_new)
    );
    always @* begin : next_proc
        case (state_q)
            S_INIT:   state_next = correct ? S_STEADY : S_TRANS;
            S_TRANS:  state_next = correct ? S_STEADY : S_NOPRED;
            S_STEADY: state_next = correct ? S_STEADY : S_INIT;
            default:  state_next = correct ? S_TRANS  : S_NOPRED;
        endcase
        if (keep) begin
            stride_next = stride_q;
            s3_next     = s3_q;
            tgt_next    = tgt_keep;
        end
        else if (same_page) begin
            stride_next = delta;
            s3_next     = s3_new;
            tgt_next    = tgt_new;
        end
        else begin
            stride_next = {STRIDE_W{1'b0}};
            s3_next     = {TGT_W{1'b0}};
            tgt_next    = ev_lo_t;
        end
    end
    always @(posedge clk) begin : card_ctl_proc
        if (rst || clear) begin
            valid_q <= 1'b0;
            state_q <= S_INIT;
        end
        else if (aw_en) begin
            valid_q <= 1'b1;
            state_q <= aw_state;
        end
        else if (update) begin
            state_q <= state_next;
        end
    end
    always @(posedge clk) begin : card_data_proc
        if (aw_en) begin
            st_q     <= aw_st;
            tag_q    <= aw_tag;
            stride_q <= aw_stride;
            s3_q     <= aw_s3;
            tgt_q    <= aw_tgt;
            lo_q     <= aw_lo;
            lo3_q    <= aw_lo3;
            ph_q     <= aw_ph;
        end
        else if (update) begin
            stride_q <= stride_next;
            s3_q     <= s3_next;
            tgt_q    <= tgt_next;
            lo_q     <= ev_lo;
            lo3_q    <= ev_lo3;
            ph_q     <= ev_ph;
        end
        if (update) begin
            tgt_prev_lip_q <= tgt_lip;
        end
    end
    always @(posedge clk) begin : bank_proc
        integer bank_idx;
        if (update) begin
            for (bank_idx = 0; bank_idx < NB; bank_idx = bank_idx + 1) begin
                tgt_prev_bank_q[bank_idx] <=
                    (tgt_lip[BANK_W-1:0] == bank_idx[BANK_W-1:0]);
            end
        end
    end
    always @(posedge clk) begin : flag_proc
        if (rst || clear) begin
            fire_q      <= 1'b0;
            dup_prev_q  <= 1'b0;
            filt_last_q <= 1'b0;
        end
        else begin
            fire_q      <= hit & correct & armed & in_page & ~own_line
                           & ~filt_main;
            dup_prev_q  <= prev_pm & (tgt_lip == prev_lip);
            filt_last_q <= filt_last_pm & (tgt_lip == filt_last_lip);
        end
    end
    always @* begin : class_proc
        if (!valid_q) begin
            class_rank = 3'd0;
        end
        else begin
            case (state_q)
                S_NOPRED: class_rank = 3'd1;
                S_INIT:   class_rank = 3'd2;
                S_TRANS:  class_rank = 3'd3;
                default:  class_rank = 3'd4;
            endcase
        end
    end
endmodule
`default_nettype wire
`endif
