`ifndef L1D_PF3_SMS_EXPAND_V
`define L1D_PF3_SMS_EXPAND_V
`default_nettype none
module l1d_pf3_sms_expand #(
    parameter NB           = 4,
    parameter LINE_W       = 58,
    parameter REGION_NUM_W = 45,
    parameter LIR_W        = 5,
    parameter EXPAND_SLOTS = 4
) (
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      pf_enable,
    input  wire                      load_valid,
    input  wire [REGION_NUM_W-1:0]   load_region,
    input  wire [LIR_W-1:0]          load_line,
    input  wire [LIR_W-1:0]          load_first,
    input  wire [NB-1:0]             load_first_bank,
    input  wire [(1<<LIR_W)-1:0]     load_rest,
    input  wire                      held,
    output reg                       cand_valid,
    output reg  [LINE_W-1:0]         cand_line,
    output reg  [NB-1:0]             cand_bank
);
    localparam PATTERN_W = (1 << LIR_W);
    localparam NS        = EXPAND_SLOTS;
    localparam PAD_W     = LINE_W - REGION_NUM_W - LIR_W;
    localparam BANK_W    = $clog2(NB);
    reg  [NS-1:0]              slot_vld;
    reg  [NS*REGION_NUM_W-1:0] slot_region;
    reg  [NS*PATTERN_W-1:0]    slot_mask;
    reg  [NS*PATTERN_W-1:0]    slot_high;
    reg  [NS-1:0]              slot_fpend;
    reg  [NS*LIR_W-1:0]        slot_first;
    reg  [NS-1:0]              free_one;
    reg                        free_seen;
    reg  [PATTERN_W-1:0]       load_high;
    reg  [LIR_W-1:0]           bit_number;
    wire                       direct_ok;
    wire                       direct_go;
    wire                       load_slot;
    integer                    slot_idx;
    integer                    bit_idx;
    reg  [NS-1:0]              rr_mask_q;
    reg  [NS-1:0]              sel_q;
    reg                        sel_vld_q;
    reg  [NS-1:0]              pick_high;
    reg  [NS-1:0]              pick_base;
    reg  [NS-1:0]              pick_one;
    reg  [NS-1:0]              pick_above;
    reg                        pick_seen;
    reg                        rd_vld;
    reg  [REGION_NUM_W-1:0]    rd_region;
    reg  [PATTERN_W-1:0]       rd_mask;
    reg  [PATTERN_W-1:0]       rd_high;
    reg                        rd_fpend;
    reg  [LIR_W-1:0]           rd_first;
    reg  [PATTERN_W-1:0]       ffs_in;
    reg  [PATTERN_W-1:0]       ffs_one;
    reg  [LIR_W-1:0]           ffs_idx;
    reg                        ffs_seen;
    wire                       slot_free;
    wire                       scan_take;
    reg  [LIR_W-1:0]           scan_line;
    reg  [PATTERN_W-1:0]       mask_after;
    reg                        fpend_after;
    integer                    bank_idx;
    assign slot_free = ~cand_valid & ~held;
    assign direct_ok = slot_free & pf_enable & ~sel_vld_q;
    assign direct_go = load_valid & direct_ok;
    always @* begin : load_proc
        free_one  = {NS{1'b0}};
        free_seen = 1'b0;
        for (slot_idx = 0; slot_idx < NS; slot_idx = slot_idx + 1) begin
            if (!slot_vld[slot_idx] && !free_seen) begin
                free_one[slot_idx] = 1'b1;
                free_seen          = 1'b1;
            end
        end
        for (bit_idx = 0; bit_idx < PATTERN_W; bit_idx = bit_idx + 1) begin
            bit_number         = bit_idx;
            load_high[bit_idx] = (bit_number > load_line);
        end
    end
    assign load_slot = load_valid & pf_enable & free_seen
                       & ((|load_rest) | ~direct_ok);
    always @* begin : pick_proc
        pick_high = slot_vld & rr_mask_q;
        pick_base = (|pick_high) ? pick_high : slot_vld;
        pick_one  = {NS{1'b0}};
        pick_seen = 1'b0;
        for (slot_idx = 0; slot_idx < NS; slot_idx = slot_idx + 1) begin
            if (pick_base[slot_idx] && !pick_seen) begin
                pick_one[slot_idx] = 1'b1;
                pick_seen          = 1'b1;
            end
        end
        pick_above = {NS{1'b0}};
        pick_seen  = 1'b0;
        for (slot_idx = 0; slot_idx < NS; slot_idx = slot_idx + 1) begin
            pick_above[slot_idx] = pick_seen;
            pick_seen            = pick_seen | pick_one[slot_idx];
        end
    end
    always @* begin : scan_proc
        rd_vld    = 1'b0;
        rd_region = {REGION_NUM_W{1'b0}};
        rd_mask   = {PATTERN_W{1'b0}};
        rd_high   = {PATTERN_W{1'b0}};
        rd_fpend  = 1'b0;
        rd_first  = {LIR_W{1'b0}};
        for (slot_idx = 0; slot_idx < NS; slot_idx = slot_idx + 1) begin
            rd_vld    = rd_vld | (slot_vld[slot_idx] & sel_q[slot_idx]);
            rd_region = rd_region | ({REGION_NUM_W{sel_q[slot_idx]}}
                        & slot_region[slot_idx*REGION_NUM_W +: REGION_NUM_W]);
            rd_mask   = rd_mask | ({PATTERN_W{sel_q[slot_idx]}}
                        & slot_mask[slot_idx*PATTERN_W +: PATTERN_W]);
            rd_high   = rd_high | ({PATTERN_W{sel_q[slot_idx]}}
                        & slot_high[slot_idx*PATTERN_W +: PATTERN_W]);
            rd_fpend  = rd_fpend | (sel_q[slot_idx] & slot_fpend[slot_idx]);
            rd_first  = rd_first | ({LIR_W{sel_q[slot_idx]}}
                        & slot_first[slot_idx*LIR_W +: LIR_W]);
        end
        ffs_in   = (|(rd_mask & rd_high)) ? (rd_mask & rd_high) : rd_mask;
        ffs_one  = {PATTERN_W{1'b0}};
        ffs_idx  = {LIR_W{1'b0}};
        ffs_seen = 1'b0;
        for (bit_idx = 0; bit_idx < PATTERN_W; bit_idx = bit_idx + 1) begin
            bit_number = bit_idx;
            if (ffs_in[bit_idx] && !ffs_seen) begin
                ffs_one[bit_idx] = 1'b1;
                ffs_idx          = bit_number;
                ffs_seen         = 1'b1;
            end
        end
        if (rd_fpend) begin
            scan_line   = rd_first;
            mask_after  = rd_mask;
            fpend_after = 1'b0;
        end
        else begin
            scan_line   = ffs_idx;
            mask_after  = rd_mask & ~ffs_one;
            fpend_after = 1'b0;
        end
    end
    assign scan_take = sel_vld_q & rd_vld & slot_free & pf_enable;
    always @(posedge clk) begin : state_proc
        if (rst || !pf_enable) begin
            slot_vld   <= {NS{1'b0}};
            sel_vld_q  <= 1'b0;
            sel_q      <= {NS{1'b0}};
            rr_mask_q  <= {NS{1'b1}};
            cand_valid <= 1'b0;
        end
        else begin
            for (slot_idx = 0; slot_idx < NS; slot_idx = slot_idx + 1) begin
                if (load_slot && free_one[slot_idx]) begin
                    slot_vld[slot_idx] <= 1'b1;
                end
            end
            for (slot_idx = 0; slot_idx < NS; slot_idx = slot_idx + 1) begin
                if (scan_take && sel_q[slot_idx]
                    && (mask_after == {PATTERN_W{1'b0}}) && !fpend_after) begin
                    slot_vld[slot_idx] <= 1'b0;
                end
            end
            if (!sel_vld_q || scan_take) begin
                sel_vld_q <= |slot_vld;
                sel_q     <= pick_one;
                if (|slot_vld) begin
                    rr_mask_q <= pick_above;
                end
            end
            cand_valid <= scan_take | direct_go;
        end
        for (slot_idx = 0; slot_idx < NS; slot_idx = slot_idx + 1) begin
            if (load_slot && free_one[slot_idx]) begin
                slot_region[slot_idx*REGION_NUM_W +: REGION_NUM_W] <= load_region;
                slot_mask[slot_idx*PATTERN_W +: PATTERN_W]         <= load_rest;
                slot_high[slot_idx*PATTERN_W +: PATTERN_W]         <= load_high;
                slot_fpend[slot_idx]                               <= ~direct_go;
                slot_first[slot_idx*LIR_W +: LIR_W]                <= load_first;
            end
            else if (scan_take && sel_q[slot_idx]) begin
                slot_mask[slot_idx*PATTERN_W +: PATTERN_W] <= mask_after;
                slot_fpend[slot_idx]                       <= fpend_after;
            end
        end
        if (scan_take) begin
            cand_line <= {{PAD_W{1'b0}}, rd_region, scan_line};
            for (bank_idx = 0; bank_idx < NB; bank_idx = bank_idx + 1) begin
                cand_bank[bank_idx] <=
                    (scan_line[BANK_W-1:0] == bank_idx[BANK_W-1:0]);
            end
        end
        else begin
            cand_line <= {{PAD_W{1'b0}}, load_region, load_first};
            cand_bank <= load_first_bank;
        end
    end
`ifdef L1D_DEBUG
    always @(posedge clk) begin : debug_proc
        if (!rst && scan_take && direct_go) begin
            $display("[%0t] L1D PF3_SMS_EXPAND ERROR scan and direct together",
                     $time);
        end
    end
`endif
endmodule
`default_nettype wire
`endif
