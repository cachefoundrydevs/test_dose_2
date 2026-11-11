`ifndef L1D_PF_SMS_FRONT_V
`define L1D_PF_SMS_FRONT_V
`default_nettype none
module l1d_pf_sms_front #(
    parameter N_PORTS          = 4,
    parameter N_BANKS          = 4,
    parameter PC_W             = 32,
    parameter LINE_ADDR_W      = 50,
    parameter PC_HASH_W        = 12,
    parameter TRAIN_FIFO_DEPTH = 4,
    parameter EVT_FIFO_DEPTH   = 4
) (
    input  wire                           clk,
    input  wire                           rst,
    input  wire                           pf_enable,
    input  wire [N_PORTS-1:0]             tr_valid,
    input  wire [N_PORTS-1:0]             tr_no_train,
    input  wire [N_PORTS*PC_W-1:0]        tr_pc,
    input  wire [N_PORTS*LINE_ADDR_W-1:0] tr_line_addr,
    input  wire [N_BANKS-1:0]             ev_valid,
    input  wire [N_BANKS*LINE_ADDR_W-1:0] ev_line_addr,
    input  wire                           train_pop,
    input  wire                           evt_pop,
    output wire                           train_head_valid,
    output wire [PC_HASH_W-1:0]           train_head_pc_hash,
    output wire [LINE_ADDR_W-1:0]         train_head_line_addr,
    output wire                           evt_head_valid,
    output wire [LINE_ADDR_W-1:0]         evt_head_line_addr
);
    localparam TRAIN_W = PC_HASH_W + LINE_ADDR_W;
    localparam PORT_W  = $clog2(N_PORTS);
    localparam BANK_W  = $clog2(N_BANKS);
    localparam [PORT_W-1:0] PORT_LAST = N_PORTS - 1;
    localparam [BANK_W-1:0] BANK_LAST = N_BANKS - 1;
    reg  [PORT_W-1:0]        train_rot_q;
    reg  [BANK_W-1:0]        evt_rot_q;
    reg  [N_PORTS-1:0]       train_ok;
    reg                      train_found;
    reg  [PC_W-1:0]          train_sel_pc;
    reg  [LINE_ADDR_W-1:0]   train_sel_line;
    reg                      evt_found;
    reg  [LINE_ADDR_W-1:0]   evt_sel_line;
    wire [PC_HASH_W-1:0]     train_sel_hash;
    wire [TRAIN_W-1:0]       train_push_word;
    wire [TRAIN_W-1:0]       train_head_word;
    function [PC_HASH_W-1:0] fold_pc;
        input [PC_W-1:0] pc_value;
        integer bit_idx;
        reg [PC_HASH_W-1:0] folded;
        begin
            folded = {PC_HASH_W{1'b0}};
            for (bit_idx = 0; bit_idx < PC_W; bit_idx = bit_idx + 1) begin
                folded[bit_idx % PC_HASH_W] = folded[bit_idx % PC_HASH_W]
                                              ^ pc_value[bit_idx];
            end
            fold_pc = folded;
        end
    endfunction
    always @* begin : train_pick_proc
        integer rot_idx;
        integer scan_idx;
        train_ok       = tr_valid & ~tr_no_train & {N_PORTS{pf_enable}};
        train_found    = 1'b0;
        train_sel_pc   = {PC_W{1'b0}};
        train_sel_line = {LINE_ADDR_W{1'b0}};
        for (scan_idx = 0; scan_idx < N_PORTS; scan_idx = scan_idx + 1) begin
            rot_idx = (scan_idx + train_rot_q) % N_PORTS;
            if (train_ok[rot_idx] && !train_found) begin
                train_found    = 1'b1;
                train_sel_pc   = tr_pc[rot_idx*PC_W +: PC_W];
                train_sel_line = tr_line_addr[rot_idx*LINE_ADDR_W +: LINE_ADDR_W];
            end
        end
    end
    always @* begin : evt_pick_proc
        integer rot_idx;
        integer scan_idx;
        evt_found    = 1'b0;
        evt_sel_line = {LINE_ADDR_W{1'b0}};
        for (scan_idx = 0; scan_idx < N_BANKS; scan_idx = scan_idx + 1) begin
            rot_idx = (scan_idx + evt_rot_q) % N_BANKS;
            if (ev_valid[rot_idx] && pf_enable && !evt_found) begin
                evt_found    = 1'b1;
                evt_sel_line = ev_line_addr[rot_idx*LINE_ADDR_W +: LINE_ADDR_W];
            end
        end
    end
    always @(posedge clk) begin : rotation_proc
        if (rst) begin
            train_rot_q <= {PORT_W{1'b0}};
            evt_rot_q   <= {BANK_W{1'b0}};
        end
        else begin
            train_rot_q <= (train_rot_q == PORT_LAST) ? {PORT_W{1'b0}}
                                                      : train_rot_q + 1'b1;
            evt_rot_q   <= (evt_rot_q == BANK_LAST) ? {BANK_W{1'b0}}
                                                    : evt_rot_q + 1'b1;
        end
    end
    assign train_sel_hash  = fold_pc(train_sel_pc);
    assign train_push_word = {train_sel_hash, train_sel_line};
    l1d_pf_sms_fifo #(
        .WIDTH (TRAIN_W),
        .DEPTH (TRAIN_FIFO_DEPTH)
    ) u_train_fifo (
        .clk        (clk),
        .rst        (rst),
        .push_valid (train_found),
        .push_data  (train_push_word),
        .pop_en     (train_pop),
        .head_valid (train_head_valid),
        .head_data  (train_head_word)
    );
    assign train_head_pc_hash   = train_head_word[TRAIN_W-1:LINE_ADDR_W];
    assign train_head_line_addr = train_head_word[LINE_ADDR_W-1:0];
    l1d_pf_sms_fifo #(
        .WIDTH (LINE_ADDR_W),
        .DEPTH (EVT_FIFO_DEPTH)
    ) u_evict_fifo (
        .clk        (clk),
        .rst        (rst),
        .push_valid (evt_found),
        .push_data  (evt_sel_line),
        .pop_en     (evt_pop),
        .head_valid (evt_head_valid),
        .head_data  (evt_head_line_addr)
    );
endmodule
`default_nettype wire
`endif
