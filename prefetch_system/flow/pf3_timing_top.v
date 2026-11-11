`default_nettype none
`include "l1d_defines.vh"
module pf3_timing_top #(
    `L1D_PARAMS
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
    output reg  [NB-1:0]             pf_req_valid;
    output reg  [NB*LINE_ADDR_W-1:0] pf_req_line_addr;
    output reg  [NB-1:0]             pf_req_unique;
    reg                      rst_q;
    reg                      pf_enable_q;
    reg  [NB-1:0]            train_valid_q;
    reg  [NB*PC_W-1:0]       train_pc_q;
    reg  [NB*ADDR_W-1:0]     train_addr_q;
    reg  [NB-1:0]            train_is_store_q;
    reg  [NB-1:0]            train_miss_q;
    reg  [NB-1:0]            train_pf_hit_q;
    reg  [NB-1:0]            train_no_train_q;
    reg  [NB-1:0]            evict_valid_q;
    reg  [NB*LINE_ADDR_W-1:0] evict_line_addr_q;
    reg  [NB-1:0]            pf_fb_valid_q;
    reg  [NB*LINE_ADDR_W-1:0] pf_fb_line_addr_q;
    reg  [NB*2-1:0]          pf_fb_result_q;
    reg  [NB-1:0]            pf_req_ready_q;
    wire [NB-1:0]            unit_valid;
    wire [NB*LINE_ADDR_W-1:0] unit_line;
    wire [NB-1:0]            unit_unique;
    always @(posedge clk) begin : in_proc
        rst_q             <= rst;
        pf_enable_q       <= pf_enable;
        train_valid_q     <= train_valid;
        train_pc_q        <= train_pc;
        train_addr_q      <= train_addr;
        train_is_store_q  <= train_is_store;
        train_miss_q      <= train_miss;
        train_pf_hit_q    <= train_pf_hit;
        train_no_train_q  <= train_no_train;
        evict_valid_q     <= evict_valid;
        evict_line_addr_q <= evict_line_addr;
        pf_fb_valid_q     <= pf_fb_valid;
        pf_fb_line_addr_q <= pf_fb_line_addr;
        pf_fb_result_q    <= pf_fb_result;
        pf_req_ready_q    <= pf_req_ready;
    end
    l1d_prefetch_unit u_prefetch (
        .clk              (clk),
        .rst              (rst_q),
        .pf_enable        (pf_enable_q),
        .train_valid      (train_valid_q),
        .train_pc         (train_pc_q),
        .train_addr       (train_addr_q),
        .train_is_store   (train_is_store_q),
        .train_miss       (train_miss_q),
        .train_pf_hit     (train_pf_hit_q),
        .train_no_train   (train_no_train_q),
        .evict_valid      (evict_valid_q),
        .evict_line_addr  (evict_line_addr_q),
        .pf_fb_valid      (pf_fb_valid_q),
        .pf_fb_line_addr  (pf_fb_line_addr_q),
        .pf_fb_result     (pf_fb_result_q),
        .pf_req_ready     (pf_req_ready_q),
        .pf_req_valid     (unit_valid),
        .pf_req_line_addr (unit_line),
        .pf_req_unique    (unit_unique)
    );
    always @(posedge clk) begin : out_proc
        pf_req_valid     <= unit_valid;
        pf_req_line_addr <= unit_line;
        pf_req_unique    <= unit_unique;
    end
endmodule
`default_nettype wire
