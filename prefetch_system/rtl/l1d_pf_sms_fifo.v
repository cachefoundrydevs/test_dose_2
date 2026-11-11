`ifndef L1D_PF_SMS_FIFO_V
`define L1D_PF_SMS_FIFO_V
`default_nettype none
module l1d_pf_sms_fifo #(
    parameter WIDTH = 62,
    parameter DEPTH = 4
) (
    input  wire             clk,
    input  wire             rst,
    input  wire             push_valid,
    input  wire [WIDTH-1:0] push_data,
    input  wire             pop_en,
    output wire             head_valid,
    output wire [WIDTH-1:0] head_data
);
    localparam PTR_W = $clog2(DEPTH);
    localparam CNT_W = $clog2(DEPTH + 1);
    localparam [CNT_W-1:0] DEPTH_V = DEPTH;
    reg  [DEPTH*WIDTH-1:0] mem_q;
    reg  [PTR_W-1:0]       wr_ptr_q;
    reg  [PTR_W-1:0]       rd_ptr_q;
    reg  [CNT_W-1:0]       count_q;
    wire                   full;
    wire                   push_ok;
    wire                   pop_ok;
    assign full       = (count_q == DEPTH_V);
    assign push_ok    = push_valid & ~full;
    assign head_valid = (count_q != {CNT_W{1'b0}});
    assign pop_ok     = pop_en & head_valid;
    assign head_data  = mem_q[rd_ptr_q*WIDTH +: WIDTH];
    always @(posedge clk) begin : fifo_proc
        if (rst) begin
            wr_ptr_q <= {PTR_W{1'b0}};
            rd_ptr_q <= {PTR_W{1'b0}};
            count_q  <= {CNT_W{1'b0}};
        end
        else begin
            if (push_ok) begin
                mem_q[wr_ptr_q*WIDTH +: WIDTH] <= push_data;
                wr_ptr_q <= wr_ptr_q + 1'b1;
            end
            if (pop_ok) begin
                rd_ptr_q <= rd_ptr_q + 1'b1;
            end
            if (push_ok && !pop_ok) begin
                count_q <= count_q + 1'b1;
            end
            else if (!push_ok && pop_ok) begin
                count_q <= count_q - 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
`endif
