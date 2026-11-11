`ifndef L1D_PF3_ADD_EQ_V
`define L1D_PF3_ADD_EQ_V
`default_nettype none
module l1d_pf3_add_eq #(
    parameter W = 13
) (
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    input  wire [W-1:0] c,
    output wire         eq
);
    wire [W-1:0] sum_bit;
    wire [W-1:0] carry_out;
    wire [W-1:0] carry_need;
    assign sum_bit    = a ^ b ^ c;
    assign carry_out  = (a & b) | ((a | b) & ~c);
    assign carry_need = {carry_out[W-2:0], 1'b0};
    assign eq         = (sum_bit == carry_need);
endmodule
`default_nettype wire
`endif
