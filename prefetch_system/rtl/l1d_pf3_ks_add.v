`ifndef L1D_PF3_KS_ADD_V
`define L1D_PF3_KS_ADD_V
`default_nettype none
module l1d_pf3_ks_add #(
    parameter W   = 13,
    parameter SUB = 0
) (
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    output wire [W-1:0] sum
);
    localparam LEVELS = $clog2(W);
    wire [W-1:0] b_eff;
    wire         carry_in;
    reg  [W-1:0] gen;
    reg  [W-1:0] prop;
    reg  [W-1:0] gen_level;
    reg  [W-1:0] prop_level;
    reg  [W-1:0] gen_next;
    reg  [W-1:0] prop_next;
    reg  [W-1:0] carry;
    reg  [W-1:0] sum_bits;
    assign b_eff    = (SUB != 0) ? ~b : b;
    assign carry_in = (SUB != 0) ? 1'b1 : 1'b0;
    always @* begin : prefix_proc
        integer level_idx;
        integer bit_idx;
        integer span;
        gen  = a & b_eff;
        prop = a ^ b_eff;
        gen_level  = gen;
        prop_level = prop;
        gen_level[0] = gen[0] | (prop[0] & carry_in);
        span = 1;
        for (level_idx = 0; level_idx < LEVELS; level_idx = level_idx + 1) begin
            for (bit_idx = 0; bit_idx < W; bit_idx = bit_idx + 1) begin
                if (bit_idx >= span) begin
                    gen_next[bit_idx]  = gen_level[bit_idx]
                        | (prop_level[bit_idx] & gen_level[bit_idx - span]);
                    prop_next[bit_idx] = prop_level[bit_idx]
                        & prop_level[bit_idx - span];
                end
                else begin
                    gen_next[bit_idx]  = gen_level[bit_idx];
                    prop_next[bit_idx] = prop_level[bit_idx];
                end
            end
            gen_level  = gen_next;
            prop_level = prop_next;
            span       = span * 2;
        end
        carry[0] = carry_in;
        for (bit_idx = 1; bit_idx < W; bit_idx = bit_idx + 1) begin
            carry[bit_idx] = gen_level[bit_idx - 1];
        end
        sum_bits = prop ^ carry;
    end
    assign sum = sum_bits;
endmodule
`default_nettype wire
`endif
