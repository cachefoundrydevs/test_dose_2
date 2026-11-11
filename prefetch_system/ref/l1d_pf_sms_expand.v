`ifndef L1D_PF_SMS_EXPAND_V
`define L1D_PF_SMS_EXPAND_V
`default_nettype none
module l1d_pf_sms_expand #(
    parameter LINE_ADDR_W    = 50,
    parameter LIR_W          = 5,
    parameter N_BANKS        = 4,
    parameter EXPAND_SLOTS   = 4,
    parameter CREDIT_PER_BANK = 2,
    parameter CREDIT_WAIT_MAX = 64
) (
    input  wire                                 clk,
    input  wire                                 rst,
    input  wire                                 pf_enable,
    input  wire                                 load_valid,
    input  wire [LINE_ADDR_W-LIR_W-1:0]         load_region,
    input  wire [(1<<LIR_W)-1:0]                load_mask,
    input  wire [LIR_W-1:0]                     load_line,
    input  wire                                 pf_ready,
    output wire                                 pf_valid,
    output wire [LINE_ADDR_W-1:0]               pf_line_addr,
    input  wire                                 fb_valid,
    input  wire [LINE_ADDR_W-1:0]               fb_addr,
    input  wire [1:0]                           fb_result
);
    localparam REGION_NUM_W = LINE_ADDR_W - LIR_W;
    localparam PATTERN_W    = (1 << LIR_W);
    localparam BANK_W       = $clog2(N_BANKS);
    localparam CRED_W       = $clog2(CREDIT_PER_BANK + 1);
    localparam WAIT_W       = $clog2(CREDIT_WAIT_MAX + 1);
    localparam [CRED_W-1:0] CREDIT_V  = CREDIT_PER_BANK;
    localparam [WAIT_W-1:0] WAIT_MAX_V = CREDIT_WAIT_MAX;
    reg  [EXPAND_SLOTS-1:0]               slot_vld_q;
    reg  [EXPAND_SLOTS*REGION_NUM_W-1:0]  slot_region_q;
    reg  [EXPAND_SLOTS*PATTERN_W-1:0]     slot_mask_q;
    reg  [EXPAND_SLOTS*PATTERN_W-1:0]     slot_high_q;
    reg  [EXPAND_SLOTS-1:0]               free_one;
    reg                                   free_seen;
    reg  [PATTERN_W-1:0]                  load_high;
    wire                                  load_ok;
    reg  [EXPAND_SLOTS-1:0]               rr_mask_q;
    reg  [EXPAND_SLOTS-1:0]               sel_q;
    reg                                   sel_vld_q;
    reg  [EXPAND_SLOTS-1:0]               pick_high;
    reg  [EXPAND_SLOTS-1:0]               pick_base;
    reg  [EXPAND_SLOTS-1:0]               pick_one;
    reg  [EXPAND_SLOTS-1:0]               pick_above;
    reg                                   pick_seen;
    reg                                   rd_vld;
    reg  [REGION_NUM_W-1:0]               rd_region;
    reg  [PATTERN_W-1:0]                  rd_mask;
    reg  [PATTERN_W-1:0]                  rd_high;
    reg  [PATTERN_W-1:0]                  ffs_in;
    reg  [PATTERN_W-1:0]                  ffs_one;
    reg  [LIR_W-1:0]                      ffs_idx;
    reg                                   ffs_seen;
    wire                                  x1_take;
    wire                                  allow_x1;
    reg                                   x1_vld_q;
    reg  [REGION_NUM_W-1:0]               x1_region_q;
    reg  [LIR_W-1:0]                      x1_line_q;
    reg  [N_BANKS*CRED_W-1:0]             credit_q;
    reg  [WAIT_W-1:0]                     wait_q;
    reg                                   credit_ok;
    wire [BANK_W-1:0]                     x1_bank;
    wire                                  go;
    reg                                   out_vld_q;
    reg  [LINE_ADDR_W-1:0]                out_addr_q;
    integer                               slot_idx;
    integer                               bank_idx;
    always @* begin : load_proc
        reg [LIR_W-1:0] bit_number;
        integer bit_idx;
        integer slot_idx;
        free_one  = {EXPAND_SLOTS{1'b0}};
        free_seen = 1'b0;
        for (slot_idx = 0; slot_idx < EXPAND_SLOTS; slot_idx = slot_idx + 1) begin
            if (!slot_vld_q[slot_idx] && !free_seen) begin
                free_one[slot_idx] = 1'b1;
                free_seen          = 1'b1;
            end
        end
        load_high = {PATTERN_W{1'b0}};
        for (bit_idx = 0; bit_idx < PATTERN_W; bit_idx = bit_idx + 1) begin
            bit_number = bit_idx;
            load_high[bit_idx] = (bit_number > load_line);
        end
    end
    assign load_ok = load_valid & pf_enable & free_seen
                     & (|load_mask);
    always @* begin : pick_proc
        integer slot_idx;
        pick_high = slot_vld_q & rr_mask_q;
        pick_base = (|pick_high) ? pick_high : slot_vld_q;
        pick_one  = {EXPAND_SLOTS{1'b0}};
        pick_seen = 1'b0;
        for (slot_idx = 0; slot_idx < EXPAND_SLOTS; slot_idx = slot_idx + 1) begin
            if (pick_base[slot_idx] && !pick_seen) begin
                pick_one[slot_idx] = 1'b1;
                pick_seen          = 1'b1;
            end
        end
        pick_above = {EXPAND_SLOTS{1'b0}};
        pick_seen  = 1'b0;
        for (slot_idx = 0; slot_idx < EXPAND_SLOTS; slot_idx = slot_idx + 1) begin
            pick_above[slot_idx] = pick_seen;
            pick_seen            = pick_seen | pick_one[slot_idx];
        end
    end
    always @* begin : read_proc
        reg [LIR_W-1:0] bit_number;
        integer bit_idx;
        integer slot_idx;
        rd_vld    = 1'b0;
        rd_region = {REGION_NUM_W{1'b0}};
        rd_mask   = {PATTERN_W{1'b0}};
        rd_high   = {PATTERN_W{1'b0}};
        for (slot_idx = 0; slot_idx < EXPAND_SLOTS; slot_idx = slot_idx + 1) begin
            rd_vld    = rd_vld | (slot_vld_q[slot_idx] & sel_q[slot_idx]);
            rd_region = rd_region | (slot_region_q[slot_idx*REGION_NUM_W +: REGION_NUM_W]
                                     & {REGION_NUM_W{sel_q[slot_idx]}});
            rd_mask   = rd_mask | (slot_mask_q[slot_idx*PATTERN_W +: PATTERN_W]
                                   & {PATTERN_W{sel_q[slot_idx]}});
            rd_high   = rd_high | (slot_high_q[slot_idx*PATTERN_W +: PATTERN_W]
                                   & {PATTERN_W{sel_q[slot_idx]}});
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
    end
    assign allow_x1 = ~x1_vld_q | go;
    assign x1_take  = sel_vld_q & rd_vld & (|rd_mask) & allow_x1;
    assign x1_bank = x1_line_q[BANK_W-1:0];
    always @* begin : credit_ok_proc
        integer bank_idx;
        credit_ok = 1'b0;
        for (bank_idx = 0; bank_idx < N_BANKS; bank_idx = bank_idx + 1) begin
            if (x1_bank == bank_idx) begin
                credit_ok = (credit_q[bank_idx*CRED_W +: CRED_W] < CREDIT_V);
            end
        end
    end
    assign go = x1_vld_q & credit_ok & (~out_vld_q | pf_ready) & pf_enable;
    always @(posedge clk) begin : state_proc
        if (rst || !pf_enable) begin
            slot_vld_q <= {EXPAND_SLOTS{1'b0}};
            sel_vld_q  <= 1'b0;
            sel_q      <= {EXPAND_SLOTS{1'b0}};
            x1_vld_q   <= 1'b0;
            out_vld_q  <= 1'b0;
            rr_mask_q  <= {EXPAND_SLOTS{1'b1}};
            wait_q     <= {WAIT_W{1'b0}};
            if (rst) begin
                credit_q <= {(N_BANKS*CRED_W){1'b0}};
            end
            else begin
                for (bank_idx = 0; bank_idx < N_BANKS; bank_idx = bank_idx + 1) begin
                    if (out_vld_q && !pf_ready
                        && (out_addr_q[BANK_W-1:0] == bank_idx)
                        && (credit_q[bank_idx*CRED_W +: CRED_W] != {CRED_W{1'b0}})) begin
                        credit_q[bank_idx*CRED_W +: CRED_W] <=
                            credit_q[bank_idx*CRED_W +: CRED_W] - 1'b1;
                    end
                end
            end
        end
        else begin
            for (slot_idx = 0; slot_idx < EXPAND_SLOTS; slot_idx = slot_idx + 1) begin
                if (load_ok && free_one[slot_idx]) begin
                    slot_vld_q[slot_idx] <= 1'b1;
                    slot_region_q[slot_idx*REGION_NUM_W +: REGION_NUM_W] <= load_region;
                    slot_mask_q[slot_idx*PATTERN_W +: PATTERN_W]         <= load_mask;
                    slot_high_q[slot_idx*PATTERN_W +: PATTERN_W]         <= load_high;
                end
            end
            if (!sel_vld_q || allow_x1) begin
                sel_vld_q <= |slot_vld_q;
                sel_q     <= pick_one;
                if (|slot_vld_q) begin
                    rr_mask_q <= pick_above;
                end
            end
            if (allow_x1) begin
                x1_vld_q    <= x1_take;
                x1_region_q <= rd_region;
                x1_line_q   <= ffs_idx;
            end
            for (slot_idx = 0; slot_idx < EXPAND_SLOTS; slot_idx = slot_idx + 1) begin
                if (x1_take && sel_q[slot_idx]) begin
                    slot_mask_q[slot_idx*PATTERN_W +: PATTERN_W] <= rd_mask & ~ffs_one;
                    if ((rd_mask & ~ffs_one) == {PATTERN_W{1'b0}}) begin
                        slot_vld_q[slot_idx] <= 1'b0;
                    end
                end
            end
            if (go) begin
                out_vld_q  <= 1'b1;
                out_addr_q <= {x1_region_q, x1_line_q};
            end
            else if (out_vld_q && pf_ready) begin
                out_vld_q <= 1'b0;
            end
            for (bank_idx = 0; bank_idx < N_BANKS; bank_idx = bank_idx + 1) begin
                if ((go && (x1_bank == bank_idx))
                    && !(fb_valid && (fb_addr[BANK_W-1:0] == bank_idx)
                         && (credit_q[bank_idx*CRED_W +: CRED_W] != {CRED_W{1'b0}}))) begin
                    credit_q[bank_idx*CRED_W +: CRED_W] <=
                        credit_q[bank_idx*CRED_W +: CRED_W] + 1'b1;
                end
                else if (!(go && (x1_bank == bank_idx))
                         && fb_valid && (fb_addr[BANK_W-1:0] == bank_idx)
                         && (credit_q[bank_idx*CRED_W +: CRED_W] != {CRED_W{1'b0}})) begin
                    credit_q[bank_idx*CRED_W +: CRED_W] <=
                        credit_q[bank_idx*CRED_W +: CRED_W] - 1'b1;
                end
            end
            if (x1_vld_q && !credit_ok) begin
                if (wait_q == WAIT_MAX_V) begin
                    credit_q <= {(N_BANKS*CRED_W){1'b0}};
                    wait_q   <= {WAIT_W{1'b0}};
                end
                else begin
                    wait_q <= wait_q + 1'b1;
                end
            end
            else begin
                wait_q <= {WAIT_W{1'b0}};
            end
        end
    end
    assign pf_valid     = out_vld_q;
    assign pf_line_addr = out_addr_q;
    wire unused_ok;
    assign unused_ok = &{1'b0, fb_result};
endmodule
`default_nettype wire
`endif
