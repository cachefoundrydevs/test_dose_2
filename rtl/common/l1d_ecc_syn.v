`ifndef L1D_ECC_SYN_V
`define L1D_ECC_SYN_V
`default_nettype none
module l1d_ecc_syn #(
    parameter DATA_W = 64,
    parameter HAM_W  = 7
) (
    input  wire [DATA_W-1:0] data,
    input  wire [HAM_W:0]    check,
    output wire [HAM_W-1:0]  syndrome,
    output wire              parity_odd,
    output wire              correctable,
    output wire              uncorrectable
);
    wire [HAM_W:0] recomputed;
    l1d_ecc_enc #(.DATA_W(DATA_W), .HAM_W(HAM_W)) u_enc (
        .data  (data),
        .check (recomputed)
    );
    wire syndrome_nonzero;
    assign syndrome         = recomputed[HAM_W-1:0] ^ check[HAM_W-1:0];
    assign syndrome_nonzero = |syndrome;
    assign parity_odd    = recomputed[HAM_W] ^ check[HAM_W] ^ (^syndrome);
    assign correctable   = parity_odd;
    assign uncorrectable = syndrome_nonzero & ~parity_odd;
endmodule
`default_nettype wire
`endif
