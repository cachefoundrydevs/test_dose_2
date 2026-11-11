`ifndef L1D_PF_SMS_V
`define L1D_PF_SMS_V
`default_nettype none
module l1d_pf_sms #(
    parameter PA_W             = 56,
    parameter LINE_BYTES       = 64,
    parameter REGION_BYTES     = 2048,
    parameter PC_W             = 32,
    parameter N_PORTS          = 4,
    parameter N_BANKS          = 4,
    parameter FT_ENTRIES       = 16,
    parameter AT_ENTRIES       = 32,
    parameter PHT_SETS         = 32,
    parameter PHT_WAYS         = 4,
    parameter REGION_TAG_W     = 16,
    parameter PC_HASH_W        = 12,
    parameter PHT_TAG_W        = 8,
    parameter EXPAND_SLOTS     = 4,
    parameter CREDIT_PER_BANK  = 2,
    parameter CREDIT_WAIT_MAX  = 64,
    parameter TRAIN_FIFO_DEPTH = 4,
    parameter EVT_FIFO_DEPTH   = 4
) (
    input  wire                                     clk,
    input  wire                                     rst,
    input  wire                                     pf_enable,
    input  wire [N_PORTS-1:0]                       tr_valid,
    input  wire [N_PORTS-1:0]                       tr_no_train,
    input  wire [N_PORTS*PC_W-1:0]                  tr_pc,
    input  wire [N_PORTS*(PA_W-$clog2(LINE_BYTES))-1:0] tr_line_addr,
    input  wire [N_PORTS-1:0]                       tr_is_store,
    input  wire [N_PORTS-1:0]                       tr_miss,
    input  wire [N_PORTS-1:0]                       tr_pf_hit,
    input  wire [N_BANKS-1:0]                       ev_valid,
    input  wire [N_BANKS*(PA_W-$clog2(LINE_BYTES))-1:0] ev_line_addr,
    input  wire                                     pf_fb_valid,
    input  wire [PA_W-$clog2(LINE_BYTES)-1:0]       pf_fb_addr,
    input  wire [1:0]                               pf_fb_result,
    input  wire                                     pf_ready,
    output wire                                     pf_valid,
    output wire [PA_W-$clog2(LINE_BYTES)-1:0]       pf_line_addr
);
    localparam LINE_ADDR_W = PA_W - $clog2(LINE_BYTES);
    localparam LIR_W       = $clog2(REGION_BYTES / LINE_BYTES);
    localparam REGION_NUM_W = LINE_ADDR_W - LIR_W;
    localparam PATTERN_W   = (1 << LIR_W);
    wire                     train_pop;
    wire                     evt_pop;
    wire                     train_head_valid;
    wire [PC_HASH_W-1:0]     train_head_pc_hash;
    wire [LINE_ADDR_W-1:0]   train_head_line_addr;
    wire                     evt_head_valid;
    wire [LINE_ADDR_W-1:0]   evt_head_line_addr;
    wire                     load_valid;
    wire [REGION_NUM_W-1:0]  load_region;
    wire [PATTERN_W-1:0]     load_mask;
    wire [LIR_W-1:0]         load_line;
    wire unused_ok;
    assign unused_ok = &{1'b0, tr_is_store, tr_miss, tr_pf_hit};
    l1d_pf_sms_front #(
        .N_PORTS          (N_PORTS),
        .N_BANKS          (N_BANKS),
        .PC_W             (PC_W),
        .LINE_ADDR_W      (LINE_ADDR_W),
        .PC_HASH_W        (PC_HASH_W),
        .TRAIN_FIFO_DEPTH (TRAIN_FIFO_DEPTH),
        .EVT_FIFO_DEPTH   (EVT_FIFO_DEPTH)
    ) u_front (
        .clk                  (clk),
        .rst                  (rst),
        .pf_enable            (pf_enable),
        .tr_valid             (tr_valid),
        .tr_no_train          (tr_no_train),
        .tr_pc                (tr_pc),
        .tr_line_addr         (tr_line_addr),
        .ev_valid             (ev_valid),
        .ev_line_addr         (ev_line_addr),
        .train_pop            (train_pop),
        .evt_pop              (evt_pop),
        .train_head_valid     (train_head_valid),
        .train_head_pc_hash   (train_head_pc_hash),
        .train_head_line_addr (train_head_line_addr),
        .evt_head_valid       (evt_head_valid),
        .evt_head_line_addr   (evt_head_line_addr)
    );
    l1d_pf_sms_core #(
        .LINE_ADDR_W  (LINE_ADDR_W),
        .LIR_W        (LIR_W),
        .PC_HASH_W    (PC_HASH_W),
        .REGION_TAG_W (REGION_TAG_W),
        .FT_ENTRIES   (FT_ENTRIES),
        .AT_ENTRIES   (AT_ENTRIES),
        .PHT_SETS     (PHT_SETS),
        .PHT_WAYS     (PHT_WAYS),
        .PHT_TAG_W    (PHT_TAG_W)
    ) u_core (
        .clk                  (clk),
        .rst                  (rst),
        .train_head_valid     (train_head_valid),
        .train_head_pc_hash   (train_head_pc_hash),
        .train_head_line_addr (train_head_line_addr),
        .evt_head_valid       (evt_head_valid),
        .evt_head_line_addr   (evt_head_line_addr),
        .train_pop            (train_pop),
        .evt_pop              (evt_pop),
        .load_valid           (load_valid),
        .load_region          (load_region),
        .load_mask            (load_mask),
        .load_line            (load_line)
    );
    l1d_pf_sms_expand #(
        .LINE_ADDR_W     (LINE_ADDR_W),
        .LIR_W           (LIR_W),
        .N_BANKS         (N_BANKS),
        .EXPAND_SLOTS    (EXPAND_SLOTS),
        .CREDIT_PER_BANK (CREDIT_PER_BANK),
        .CREDIT_WAIT_MAX (CREDIT_WAIT_MAX)
    ) u_expand (
        .clk          (clk),
        .rst          (rst),
        .pf_enable    (pf_enable),
        .load_valid   (load_valid),
        .load_region  (load_region),
        .load_mask    (load_mask),
        .load_line    (load_line),
        .pf_ready     (pf_ready),
        .pf_valid     (pf_valid),
        .pf_line_addr (pf_line_addr),
        .fb_valid     (pf_fb_valid),
        .fb_addr      (pf_fb_addr),
        .fb_result    (pf_fb_result)
    );
endmodule
`default_nettype wire
`endif
