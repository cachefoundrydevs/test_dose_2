`ifndef L1D_KS_ADD_V
`define L1D_KS_ADD_V
`default_nettype none
module l1d_ks_add #(
   parameter W = 13
) (
   cin,
   a,
   b,
   sum
);
   localparam LV = (W > 1) ? $clog2(W) : 1;
   input  wire          cin;
   input  wire [W-1:0]  a;
   input  wire [W-1:0]  b;
   output reg  [W-1:0]  sum;
   reg  [W-1:0]         p0;
   reg  [W-1:0]         gen;
   reg  [W-1:0]         prp;
   reg  [W-1:0]         gen_n;
   reg  [W-1:0]         prp_n;
   always @* begin : add_proc
      integer i;
      integer k;
      p0  = a ^ b;
      gen = a & b;
      gen[0] = gen[0] | (p0[0] & cin);
      prp = p0;
      for (k = 0; k < LV; k = k + 1) begin
         gen_n = gen;
         prp_n = prp;
         for (i = 0; i < W; i = i + 1) begin
            if (i >= (1 << k)) begin
               gen_n[i] = gen[i] | (prp[i] & gen[i - (1 << k)]);
               prp_n[i] = prp[i] & prp[i - (1 << k)];
            end
         end
         gen = gen_n;
         prp = prp_n;
      end
      sum[0] = p0[0] ^ cin;
      for (i = 1; i < W; i = i + 1) begin
         sum[i] = p0[i] ^ gen[i - 1];
      end
   end
endmodule
`default_nettype wire
`endif
