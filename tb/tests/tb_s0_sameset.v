`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_s0_sameset;
`ifdef TINY
    localparam SETS = 4, WAYS = 2, LSU_BUF = 4, MSHR = 2, NCE = 1, VCS = 2, RFIFO = 2;
`else
    localparam SETS = `L1D_SETS, WAYS = `L1D_WAYS, LSU_BUF = `L1D_LSU_BUF_DEPTH,
               MSHR = `L1D_MSHR_ENTRIES, NCE = `L1D_MSHR_NC_ENTRIES, VCS = `L1D_VC_SLOTS,
               RFIFO = `L1D_RESP_FIFO_DEPTH;
`endif
`ifdef NPAIRS
    localparam SCEN_PAIRS = `NPAIRS;
`else
    localparam SCEN_PAIRS = 64;
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
        scenario_sameset(SCEN_PAIRS);
        s0_report;
        check(cov_pipe_conflict > 0,  "coverage: a fresh request was cancelled in stage R by a same-set hazard (ghost, re-issued)");
        check(mon_cancel_errors == 0, "stage R never saw a hazard on a BOOKED request");
        finish_tb("tb_s0_sameset");
    end
endmodule
