`ifndef L1D_PREFETCH_UNIT_V
`define L1D_PREFETCH_UNIT_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_prefetch_unit #(
    `L1D_PARAMS,
    parameter PF_HOLD_MAX = `L1D_PF_HOLD_MAX,
    parameter PF_PA_W     = 56
) (
    clk, rst, pf_enable,
    train_valid, train_pc, train_addr, train_is_store, train_miss, train_pf_hit, train_no_train,
    evict_valid, evict_line_addr,
    pf_fb_valid, pf_fb_line_addr, pf_fb_result,
    pf_req_ready, pf_req_valid, pf_req_line_addr, pf_req_unique
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam NB        = NUM_BANKS;
    localparam PF_LINE_W = PF_PA_W - OFFSET_W;
    localparam LINE_PAD  = LINE_ADDR_W - PF_LINE_W;
    localparam NPF       = 3;
    localparam PF_STRIDE = 0;
    localparam PF_STREAM = 1;
    localparam PF_SMS    = 2;
    localparam HOLD_W    = $clog2(PF_HOLD_MAX + 1);
    localparam [HOLD_W-1:0] HOLD_LAST = PF_HOLD_MAX - 1;
    input  wire                      clk;
    input  wire                      rst;
    input  wire                      pf_enable;
    input  wire [NB-1:0]             train_valid;
    input  wire [NB*PC_W-1:0]        train_pc;
    input  wire [NB*ADDR_W-1:0]      train_addr;
    input  wire [NB-1:0]             train_is_store;
    input  wire [NB-1:0]             train_miss;
    input  wire [NB-1:0]             train_pf_hit;
    input  wire [NB-1:0]             train_no_train;
    input  wire [NB-1:0]             evict_valid;
    input  wire [NB*LINE_ADDR_W-1:0] evict_line_addr;
    input  wire [NB-1:0]             pf_fb_valid;
    input  wire [NB*LINE_ADDR_W-1:0] pf_fb_line_addr;
    input  wire [NB*2-1:0]           pf_fb_result;
    input  wire [NB-1:0]             pf_req_ready;
    output reg  [NB-1:0]             pf_req_valid;
    output reg  [NB*LINE_ADDR_W-1:0] pf_req_line_addr;
    output reg  [NB-1:0]             pf_req_unique;
    reg  [NB-1:0]      rec_pick_onehot;
    reg                rec_pick_seen;
    reg                rec_valid;
    reg  [PC_W-1:0]    rec_pc;
    reg  [ADDR_W-1:0]  rec_addr;
    reg                rec_is_store;
    reg                rec_miss;
    reg                rec_pf_hit;
    integer rec_bank;
    always @* begin
        rec_pick_seen = 1'b0;
        rec_valid     = 1'b0;
        rec_pc        = {PC_W{1'b0}};
        rec_addr      = {ADDR_W{1'b0}};
        rec_is_store  = 1'b0;
        rec_miss      = 1'b0;
        rec_pf_hit    = 1'b0;
        for (rec_bank = 0; rec_bank < NB; rec_bank = rec_bank + 1) begin
            rec_pick_onehot[rec_bank] = train_valid[rec_bank] & ~train_no_train[rec_bank] & ~rec_pick_seen;
            rec_pick_seen = rec_pick_seen | (train_valid[rec_bank] & ~train_no_train[rec_bank]);
            rec_valid     = rec_valid    | rec_pick_onehot[rec_bank];
            rec_pc        = rec_pc       | ({PC_W{rec_pick_onehot[rec_bank]}}   & train_pc[rec_bank*PC_W +: PC_W]);
            rec_addr      = rec_addr     | ({ADDR_W{rec_pick_onehot[rec_bank]}} & train_addr[rec_bank*ADDR_W +: ADDR_W]);
            rec_is_store  = rec_is_store | (rec_pick_onehot[rec_bank] & train_is_store[rec_bank]);
            rec_miss      = rec_miss     | (rec_pick_onehot[rec_bank] & train_miss[rec_bank]);
            rec_pf_hit    = rec_pf_hit   | (rec_pick_onehot[rec_bank] & train_pf_hit[rec_bank]);
        end
    end
    wire                rec_train_on;
    wire [PF_PA_W-1:0]  rec_pa;
    wire                no_train_zero;
    assign rec_train_on  = rec_valid & pf_enable;
    assign rec_pa        = rec_addr[PF_PA_W-1:0];
    assign no_train_zero = 1'b0;
    reg  [NB-1:0]           fb_pick_onehot;
    reg                     fb_pick_seen;
    reg                     fb_valid;
    reg  [LINE_ADDR_W-1:0]  fb_line;
    reg  [1:0]              fb_result;
    integer fb_bank;
    always @* begin
        fb_pick_seen = 1'b0;
        fb_valid     = 1'b0;
        fb_line      = {LINE_ADDR_W{1'b0}};
        fb_result    = 2'b00;
        for (fb_bank = 0; fb_bank < NB; fb_bank = fb_bank + 1) begin
            fb_pick_onehot[fb_bank] = pf_fb_valid[fb_bank] & ~fb_pick_seen;
            fb_pick_seen = fb_pick_seen | pf_fb_valid[fb_bank];
            fb_valid     = fb_valid  | fb_pick_onehot[fb_bank];
            fb_line      = fb_line   | ({LINE_ADDR_W{fb_pick_onehot[fb_bank]}} & pf_fb_line_addr[fb_bank*LINE_ADDR_W +: LINE_ADDR_W]);
            fb_result    = fb_result | ({2{fb_pick_onehot[fb_bank]}} & pf_fb_result[fb_bank*2 +: 2]);
        end
    end
    wire [PF_LINE_W-1:0] fb_line_pf;
    assign fb_line_pf = fb_line[PF_LINE_W-1:0];
    wire [NB*PF_LINE_W-1:0] sms_train_line;
    wire [NB*PF_LINE_W-1:0] sms_evict_line;
    wire [NB-1:0]           sms_train_valid;
    genvar lane;
    generate
        for (lane = 0; lane < NB; lane = lane + 1) begin : g_sms_lane
            assign sms_train_line[lane*PF_LINE_W +: PF_LINE_W] = train_addr[lane*ADDR_W + OFFSET_W +: PF_LINE_W];
            assign sms_evict_line[lane*PF_LINE_W +: PF_LINE_W] = evict_line_addr[lane*LINE_ADDR_W +: PF_LINE_W];
            assign sms_train_valid[lane] = train_valid[lane] & pf_enable;
        end
    endgenerate
    wire [NPF-1:0]       src_valid;
    wire [NPF-1:0]       src_unique;
    wire [NPF-1:0]       src_ready;
    wire [ADDR_W-1:0]    stride_addr;
    wire [PF_LINE_W-1:0] stream_line;
    wire [PF_LINE_W-1:0] sms_line;
    wire                 stream_flag_unused;
    wire                 stride_clear;
    assign stride_clear = 1'b0;
    l1d_pf_stride #(.PC_W(PC_W), .PA_W(PF_PA_W), .ADDR_W(ADDR_W), .LINE_BYTES(LINE_BYTES)) u_pf_stride (
        .rst         (rst),
        .clk         (clk),
        .clear       (stride_clear),
        .tr_valid    (rec_train_on),
        .tr_pc       (rec_pc),
        .tr_pa       (rec_pa),
        .tr_is_store (rec_is_store),
        .pf_ready    (src_ready[PF_STRIDE]),
        .pf_valid    (src_valid[PF_STRIDE]),
        .pf_addr     (stride_addr),
        .pf_unique   (src_unique[PF_STRIDE])
    );
    l1d_pf_stream #(.PA_W(PF_PA_W), .LINE_BYTES(LINE_BYTES)) u_pf_stream (
        .clk          (clk),
        .rst          (rst),
        .pf_enable    (pf_enable),
        .tr_valid     (rec_train_on),
        .tr_addr      (rec_pa),
        .tr_is_store  (rec_is_store),
        .tr_no_train  (no_train_zero),
        .tr_miss      (rec_miss),
        .tr_pf_hit    (rec_pf_hit),
        .pf_ready     (src_ready[PF_STREAM]),
        .pf_valid     (src_valid[PF_STREAM]),
        .pf_line_addr (stream_line),
        .pf_unique    (src_unique[PF_STREAM]),
        .pf_flag      (stream_flag_unused)
    );
    l1d_pf_sms #(.PA_W(PF_PA_W), .LINE_BYTES(LINE_BYTES), .PC_W(PC_W), .N_PORTS(NB), .N_BANKS(NB)) u_pf_sms (
        .clk          (clk),
        .rst          (rst),
        .pf_enable    (pf_enable),
        .tr_valid     (sms_train_valid),
        .tr_no_train  (train_no_train),
        .tr_pc        (train_pc),
        .tr_line_addr (sms_train_line),
        .tr_is_store  (train_is_store),
        .tr_miss      (train_miss),
        .tr_pf_hit    (train_pf_hit),
        .ev_valid     (evict_valid),
        .ev_line_addr (sms_evict_line),
        .pf_fb_valid  (fb_valid),
        .pf_fb_addr   (fb_line_pf),
        .pf_fb_result (fb_result),
        .pf_ready     (src_ready[PF_SMS]),
        .pf_valid     (src_valid[PF_SMS]),
        .pf_line_addr (sms_line)
    );
    assign src_unique[PF_SMS] = 1'b0;
    wire [LINE_ADDR_W-1:0] src_line [0:NPF-1];
    assign src_line[PF_STRIDE] = stride_addr[ADDR_W-1:OFFSET_W];
    assign src_line[PF_STREAM] = {{LINE_PAD{1'b0}}, stream_line};
    assign src_line[PF_SMS]    = {{LINE_PAD{1'b0}}, sms_line};
    reg  [NPF-1:0]         a_busy_q;
    reg  [LINE_ADDR_W-1:0] a_line_q [0:NPF-1];
    reg  [NPF-1:0]         a_unique_q;
    reg  [HOLD_W-1:0]      a_hold_q [0:NPF-1];
    reg  [NPF-1:0]         a_hold_last_q;
    reg                    eq_stride_stream_q;
    reg                    eq_stride_sms_q;
    reg                    eq_stream_sms_q;
    wire [NPF-1:0]         a_load;
    wire [NPF-1:0]         a_done;
    wire [LINE_ADDR_W-1:0] a_line_next [0:NPF-1];
    reg  [HOLD_W-1:0]      a_hold_next [0:NPF-1];
    genvar ax;
    generate
        for (ax = 0; ax < NPF; ax = ax + 1) begin : g_stage_a
            assign a_load[ax]      = ~a_busy_q[ax] & src_valid[ax] & pf_enable;
            assign a_line_next[ax] = a_load[ax] ? src_line[ax] : a_line_q[ax];
        end
    endgenerate
    integer hx;
    always @* begin
        for (hx = 0; hx < NPF; hx = hx + 1) begin
            if (a_load[hx])          a_hold_next[hx] = {HOLD_W{1'b0}};
            else if (a_busy_q[hx])   a_hold_next[hx] = a_hold_q[hx] + {{(HOLD_W-1){1'b0}}, 1'b1};
            else                     a_hold_next[hx] = {HOLD_W{1'b0}};
        end
    end
    integer sx;
    always @(posedge clk) begin : stage_a_proc
        if (rst) begin
            a_busy_q           <= {NPF{1'b0}};
            a_unique_q         <= {NPF{1'b0}};
            a_hold_last_q      <= {NPF{1'b0}};
            eq_stride_stream_q <= 1'b0;
            eq_stride_sms_q    <= 1'b0;
            eq_stream_sms_q    <= 1'b0;
            for (sx = 0; sx < NPF; sx = sx + 1) begin
                a_line_q[sx] <= {LINE_ADDR_W{1'b0}};
                a_hold_q[sx] <= {HOLD_W{1'b0}};
            end
        end else begin
            for (sx = 0; sx < NPF; sx = sx + 1) begin
                a_busy_q[sx]      <= (a_busy_q[sx] & ~a_done[sx]) | a_load[sx];
                a_line_q[sx]      <= a_line_next[sx];
                a_hold_q[sx]      <= a_hold_next[sx];
                a_hold_last_q[sx] <= (a_hold_next[sx] == HOLD_LAST);
                if (a_load[sx]) a_unique_q[sx] <= src_unique[sx];
            end
            eq_stride_stream_q <= (a_line_next[PF_STRIDE] == a_line_next[PF_STREAM]);
            eq_stride_sms_q    <= (a_line_next[PF_STRIDE] == a_line_next[PF_SMS]);
            eq_stream_sms_q    <= (a_line_next[PF_STREAM] == a_line_next[PF_SMS]);
        end
    end
    wire [NPF-1:0] dup;
    wire [NPF-1:0] cand;
    assign dup[PF_STRIDE] = 1'b0;
    assign dup[PF_STREAM] = a_busy_q[PF_STRIDE] & eq_stride_stream_q;
    assign dup[PF_SMS]    = (a_busy_q[PF_STRIDE] & eq_stride_sms_q) | (a_busy_q[PF_STREAM] & eq_stream_sms_q);
    assign cand = a_busy_q & ~dup & {NPF{pf_enable}};
    reg  [NB*NPF-1:0]      win;
    reg  [NPF-1:0]         taken;
    reg  [NB-1:0]          req_valid_next;
    reg  [NB*LINE_ADDR_W-1:0] req_line_next;
    reg  [NB-1:0]          req_unique_next;
    reg  [NPF-1:0]         for_bank;
    integer bb;
    integer bx;
    always @* begin
        taken = {NPF{1'b0}};
        for (bb = 0; bb < NB; bb = bb + 1) begin
            for (bx = 0; bx < NPF; bx = bx + 1)
                for_bank[bx] = cand[bx] & (a_line_q[bx][LA_BANK_LSB +: BANK_W] == bb) & pf_req_ready[bb];
            win[bb*NPF + PF_STRIDE] = for_bank[PF_STRIDE];
            win[bb*NPF + PF_STREAM] = for_bank[PF_STREAM] & ~for_bank[PF_STRIDE];
            win[bb*NPF + PF_SMS]    = for_bank[PF_SMS] & ~for_bank[PF_STREAM] & ~for_bank[PF_STRIDE];
            req_valid_next[bb]  = |win[bb*NPF +: NPF];
            req_unique_next[bb] = |(win[bb*NPF +: NPF] & a_unique_q);
            req_line_next[bb*LINE_ADDR_W +: LINE_ADDR_W] = {LINE_ADDR_W{1'b0}};
            for (bx = 0; bx < NPF; bx = bx + 1) begin
                req_line_next[bb*LINE_ADDR_W +: LINE_ADDR_W] = req_line_next[bb*LINE_ADDR_W +: LINE_ADDR_W] |
                                                               ({LINE_ADDR_W{win[bb*NPF + bx]}} & a_line_q[bx]);
                taken[bx] = taken[bx] | win[bb*NPF + bx];
            end
        end
    end
    wire [NPF-1:0] dropped;
    assign dropped   = a_busy_q & (dup | a_hold_last_q | {NPF{~pf_enable}});
    assign a_done    = taken | dropped;
    assign src_ready = a_done | {NPF{~pf_enable}};
    always @(posedge clk) begin : stage_b_proc
        if (rst) begin
            pf_req_valid  <= {NB{1'b0}};
            pf_req_unique <= {NB{1'b0}};
        end else begin
            pf_req_valid  <= req_valid_next;
            pf_req_unique <= req_unique_next;
        end
        pf_req_line_addr <= req_line_next;
    end
`ifdef L1D_DEBUG
    integer dbg_x;
    integer dbg_b;
    always @(posedge clk) begin
        if (!rst) begin
            for (dbg_x = 0; dbg_x < NPF; dbg_x = dbg_x + 1) begin
                if (a_load[dbg_x])
                    $display("[%0t] L1D PF   %s request line=%h unique=%b captured", $time,
                             (dbg_x == PF_STRIDE) ? "stride" : (dbg_x == PF_STREAM) ? "stream" : "SMS   ",
                             {src_line[dbg_x], {OFFSET_W{1'b0}}}, src_unique[dbg_x]);
                if (dropped[dbg_x])
                    $display("[%0t] L1D PF   %s request line=%h DROPPED (%s)", $time,
                             (dbg_x == PF_STRIDE) ? "stride" : (dbg_x == PF_STREAM) ? "stream" : "SMS   ",
                             {a_line_q[dbg_x], {OFFSET_W{1'b0}}},
                             dup[dbg_x] ? "duplicate" : (a_hold_last_q[dbg_x] ? "hold limit" : "disabled"));
            end
            for (dbg_b = 0; dbg_b < NB; dbg_b = dbg_b + 1)
                if (req_valid_next[dbg_b])
                    $display("[%0t] L1D PF   hint to bank %0d line=%h unique=%b", $time, dbg_b,
                             {req_line_next[dbg_b*LINE_ADDR_W +: LINE_ADDR_W], {OFFSET_W{1'b0}}}, req_unique_next[dbg_b]);
        end
    end
`endif
endmodule
`default_nettype wire
`endif
