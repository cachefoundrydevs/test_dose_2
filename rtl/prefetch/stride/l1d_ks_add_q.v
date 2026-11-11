`ifndef L1D_KS_ADD_Q_V
`define L1D_KS_ADD_Q_V
`default_nettype none
(* keep_hierarchy *)
module l1d_ks_add_q #(
   parameter W   = 13,
   parameter SUB = 1
) (
   clk,
   a_d,
   b_d,
   sum
);
   input  wire          clk;
   input  wire [W-1:0]  a_d;
   input  wire [W-1:0]  b_d;
   output wire [W-1:0]  sum;
   reg  [W-1:0]         a_q;
   reg  [W-1:0]         b_q;
   wire [W-1:0]         b_x;
   wire                 cin;
   always @(posedge clk) begin : op_reg_proc
      a_q <= a_d;
      b_q <= b_d;
   end
   assign b_x = (SUB != 0) ? ~b_q : b_q;
   assign cin = (SUB != 0) ? 1'b1 : 1'b0;
   l1d_ks_add #(.W(W)) u_ks_add (
      .cin (cin),
      .a   (a_q),
      .b   (b_x),
      .sum (sum)
   );
endmodule
`default_nettype wire
`endif
