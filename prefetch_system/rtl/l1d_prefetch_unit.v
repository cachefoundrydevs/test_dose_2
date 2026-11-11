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
    train_valid, train_pc, train_addr, train_is_store, train_miss,
    train_pf_hit, train_no_train,
    evict_valid, evict_line_addr,
    pf_fb_valid, pf_fb_line_addr, pf_fb_result,
    pf_req_ready, pf_req_valid, pf_req_line_addr, pf_req_unique
);
    `include "l1d_fields.vh"
    localparam NB = NUM_BANKS;
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
    output wire [NB-1:0]             pf_req_valid;
    output wire [NB*LINE_ADDR_W-1:0] pf_req_line_addr;
    output wire [NB-1:0]             pf_req_unique;
    wire                   stride_clear;
    wire                   s_valid;
    wire [LINE_ADDR_W-1:0] s_line;
    wire [NB-1:0]          s_bank;
    wire                   s_unique;
    wire                   t_valid;
    wire [LINE_ADDR_W-1:0] t_line;
    wire [NB-1:0]          t_bank;
    wire                   t_unique;
    wire                   t_held;
    wire                   m_valid;
    wire [LINE_ADDR_W-1:0] m_line;
    wire [NB-1:0]          m_bank;
    wire                   m_held;
    wire                   load_valid;
    wire [PF_PA_W-OFFSET_W-5-1:0] load_region;
    wire [4:0]             load_line;
    wire [4:0]             load_first;
    wire [NB-1:0]          load_first_bank;
    wire [31:0]            load_rest;
    wire                   fb_unused;
    assign stride_clear = 1'b0;
    assign fb_unused    = &{1'b0, pf_fb_line_addr, pf_fb_result};
    l1d_pf3_stride #(
        .NB         (NB),
        .PC_W       (PC_W),
        .ADDR_W     (ADDR_W),
        .PA_W       (PF_PA_W),
        .LINE_BYTES (LINE_BYTES)
    ) u_stride (
        .clk            (clk),
        .rst            (rst),
        .pf_enable      (pf_enable),
        .clear          (stride_clear),
        .train_valid    (train_valid),
        .train_no_train (train_no_train),
        .train_is_store (train_is_store),
        .train_pc       (train_pc),
        .train_addr     (train_addr),
        .cand_valid     (s_valid),
        .cand_line      (s_line),
        .cand_bank      (s_bank),
        .cand_unique    (s_unique)
    );
    l1d_pf3_stream #(
        .NB         (NB),
        .ADDR_W     (ADDR_W),
        .PA_W       (PF_PA_W),
        .LINE_BYTES (LINE_BYTES)
    ) u_stream (
        .clk            (clk),
        .rst            (rst),
        .pf_enable      (pf_enable),
        .train_valid    (train_valid),
        .train_no_train (train_no_train),
        .train_addr     (train_addr),
        .train_is_store (train_is_store),
        .train_miss     (train_miss),
        .train_pf_hit   (train_pf_hit),
        .held           (t_held),
        .cand_valid     (t_valid),
        .cand_line      (t_line),
        .cand_bank      (t_bank),
        .cand_unique    (t_unique)
    );
    l1d_pf3_sms_core #(
        .NB         (NB),
        .PC_W       (PC_W),
        .ADDR_W     (ADDR_W),
        .PA_W       (PF_PA_W),
        .LINE_BYTES (LINE_BYTES),
        .LINE_W     (LINE_ADDR_W)
    ) u_sms_core (
        .clk             (clk),
        .rst             (rst),
        .pf_enable       (pf_enable),
        .train_valid     (train_valid),
        .train_no_train  (train_no_train),
        .train_pc        (train_pc),
        .train_addr      (train_addr),
        .evict_valid     (evict_valid),
        .evict_line_addr (evict_line_addr),
        .load_valid      (load_valid),
        .load_region     (load_region),
        .load_line       (load_line),
        .load_first      (load_first),
        .load_first_bank (load_first_bank),
        .load_rest       (load_rest)
    );
    l1d_pf3_sms_expand #(
        .NB           (NB),
        .LINE_W       (LINE_ADDR_W),
        .REGION_NUM_W (PF_PA_W - OFFSET_W - 5),
        .LIR_W        (5)
    ) u_sms_expand (
        .clk             (clk),
        .rst             (rst),
        .pf_enable       (pf_enable),
        .load_valid      (load_valid),
        .load_region     (load_region),
        .load_line       (load_line),
        .load_first      (load_first),
        .load_first_bank (load_first_bank),
        .load_rest       (load_rest),
        .held            (m_held),
        .cand_valid      (m_valid),
        .cand_line       (m_line),
        .cand_bank       (m_bank)
    );
    l1d_pf3_rank #(
        .NB       (NB),
        .LINE_W   (LINE_ADDR_W),
        .HOLD_MAX (PF_HOLD_MAX)
    ) u_rank (
        .clk           (clk),
        .rst           (rst),
        .pf_enable     (pf_enable),
        .pf_req_ready  (pf_req_ready),
        .s_valid       (s_valid),
        .s_line        (s_line),
        .s_bank        (s_bank),
        .s_unique      (s_unique),
        .t_valid       (t_valid),
        .t_line        (t_line),
        .t_bank        (t_bank),
        .t_unique      (t_unique),
        .m_valid       (m_valid),
        .m_line        (m_line),
        .m_bank        (m_bank),
        .fb_valid      (pf_fb_valid),
        .t_held        (t_held),
        .m_held        (m_held),
        .pf_req_valid  (pf_req_valid),
        .pf_req_line   (pf_req_line_addr),
        .pf_req_unique (pf_req_unique)
    );
endmodule
`default_nettype wire
`endif
