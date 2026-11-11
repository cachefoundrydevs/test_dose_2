`ifndef L1D_ADD_EQ_V
`define L1D_ADD_EQ_V
`default_nettype none
(* keep_hierarchy *)
module l1d_add_eq #(
   parameter W = 13
) (
   a,
   b,
   c,
   eq
);
   input  wire [W-1:0]  a;
   input  wire [W-1:0]  b;
   input  wire [W-1:0]  c;
   output reg           eq;
   reg  [W-1:0]         csa_s;
   reg  [W-2:0]         csa_c;
   always @* begin : eq_proc
      csa_s = ~(a ^ b ^ c);
      csa_c = (a[W-2:0] & b[W-2:0]) | (a[W-2:0] & ~c[W-2:0]) |
              (b[W-2:0] & ~c[W-2:0]);
      eq    = &(csa_s ^ {csa_c, 1'b0});
   end
endmodule
`default_nettype wire
`endif
