`ifndef L1D_BOOK_SELECT_V
`define L1D_BOOK_SELECT_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_book_select #(
    parameter REFILL_SKIP = 3,
    parameter SNP_STARVE  = 8,
    parameter BOOK_KIND_W = 5
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   snoop_offer_valid,
    input  wire                   snoop_credit_ok,
    input  wire                   refill_token_valid,
    input  wire                   maint_token_valid,
    input  wire                   entry_ready_valid,
    input  wire                   entry_credit_ok,
    input  wire                   arrival_ready_valid,
    input  wire                   arrival_credit_ok,
    input  wire                   prefetch_valid,
    input  wire                   amo_issued_now,
    input  wire                   store_in_flight_next,
    input  wire                   amo_write_next,
    output reg                    book_valid_q,
    output reg  [BOOK_KIND_W-1:0] book_kind_q,
    output reg                    fresh_allowed_q,
    output wire                   book_now_snoop,
    output wire                   book_now_refill,
    output wire                   book_now_maint,
    output wire                   book_now_entry,
    output wire                   book_now_arrival,
    output wire                   book_now_prefetch
);
    localparam SKIP_W   = (REFILL_SKIP > 0) ? $clog2(REFILL_SKIP + 1) : 1;
    localparam STARVE_W = $clog2(SNP_STARVE + 1);
    localparam [SKIP_W-1:0]   SKIP_C   = REFILL_SKIP;
    localparam [STARVE_W-1:0] STARVE_C = SNP_STARVE;
    localparam BOOK_SNOOP_B  = 0;
    localparam BOOK_REFILL_B = 1;
    localparam BOOK_MAINT_B  = 2;
    localparam BOOK_ENTRY_B  = 3;
    localparam BOOK_PF_B     = 4;
    reg  [SKIP_W-1:0]   skip_q;
    reg                 skip_open_q;
    reg  [STARVE_W-1:0] starve_cnt_q;
    reg                 starve_q;
    wire door_open_next;
    wire snoop_request;
    wire snoop_ok;
    wire snoop_waits;
    wire refill_ok;
    wire maint_ok;
    wire cpu_go;
    assign door_open_next = skip_open_q && !amo_issued_now;
    assign snoop_request  = snoop_offer_valid && snoop_credit_ok && !(starve_q && refill_token_valid);
    assign snoop_ok       = snoop_request && !store_in_flight_next;
    assign snoop_waits    = snoop_request && store_in_flight_next;
    assign refill_ok      = refill_token_valid && !snoop_ok && !store_in_flight_next;
    assign maint_ok       = maint_token_valid && !snoop_ok && !refill_token_valid && !store_in_flight_next;
    assign cpu_go         = door_open_next && !snoop_ok && !snoop_waits && !refill_token_valid && !maint_token_valid &&
                            !amo_write_next;
    assign book_now_snoop    = door_open_next && snoop_ok;
    assign book_now_refill   = door_open_next && refill_ok;
    assign book_now_maint    = door_open_next && maint_ok;
    assign book_now_entry    = cpu_go && entry_ready_valid && entry_credit_ok;
    assign book_now_arrival  = cpu_go && !book_now_entry && arrival_ready_valid && arrival_credit_ok;
    assign book_now_prefetch = cpu_go && !book_now_entry && !book_now_arrival && prefetch_valid;
    wire book_now_any;
    assign book_now_any = book_now_snoop || book_now_refill || book_now_maint || book_now_entry || book_now_arrival || book_now_prefetch;
    always @(posedge clk) begin : book_proc
        if (rst) begin
            book_valid_q    <= 1'b0;
            book_kind_q     <= {BOOK_KIND_W{1'b0}};
            fresh_allowed_q <= 1'b1;
        end else begin
            book_valid_q                <= book_now_any;
            book_kind_q[BOOK_SNOOP_B]   <= book_now_snoop;
            book_kind_q[BOOK_REFILL_B]  <= book_now_refill;
            book_kind_q[BOOK_MAINT_B]   <= book_now_maint;
            book_kind_q[BOOK_ENTRY_B]   <= book_now_entry || book_now_arrival;
            book_kind_q[BOOK_PF_B]      <= book_now_prefetch;
            fresh_allowed_q             <= cpu_go && !book_now_any;
        end
    end
    always @(posedge clk) begin : skip_proc
        if (rst) begin
            skip_q      <= {SKIP_W{1'b0}};
            skip_open_q <= 1'b1;
        end else if (book_now_refill) begin
            skip_q      <= SKIP_C;
            skip_open_q <= (REFILL_SKIP == 0);
        end else if (!skip_open_q) begin
            skip_q      <= skip_q - 1'b1;
            skip_open_q <= (skip_q == {{(SKIP_W-1){1'b0}}, 1'b1});
        end
    end
    always @(posedge clk) begin : starve_proc
        if (rst || book_now_refill || !refill_token_valid) begin
            starve_cnt_q <= {STARVE_W{1'b0}};
            starve_q     <= 1'b0;
        end else if (book_now_snoop && !starve_q) begin
            starve_cnt_q <= starve_cnt_q + 1'b1;
            starve_q     <= (starve_cnt_q == STARVE_C - 1'b1);
        end
    end
endmodule
`default_nettype wire
`endif
