`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_s0_order;
`ifdef TINY
    localparam SETS = 4, WAYS = 2, LSU_BUF = 4, MSHR = 2, NCE = 1, VCS = 2, RFIFO = 2;
`else
    localparam SETS = `L1D_SETS, WAYS = `L1D_WAYS, LSU_BUF = `L1D_LSU_BUF_DEPTH,
               MSHR = `L1D_MSHR_ENTRIES, NCE = `L1D_MSHR_NC_ENTRIES, VCS = `L1D_VC_SLOTS,
               RFIFO = `L1D_RESP_FIFO_DEPTH;
`endif
`ifdef NCYC
    localparam SCEN_CYCLES = `NCYC;
`else
    localparam SCEN_CYCLES = 400;
`endif
`ifdef SEED
    localparam SEED0 = `SEED;
`else
    localparam SEED0 = 1;
`endif
`include "tb_ports_common.vh"
`include "tb_s0_common.vh"
    initial begin
        init_tb;
        scenario_order(SCEN_CYCLES);
        s0_report;
        check(cov_ring_max >= 4, "coverage: an order ring held 4 or more requests");
        check(cov_from_ring > 0, "coverage: requests were granted from an order ring");
        finish_tb("tb_s0_order");
    end
endmodule
