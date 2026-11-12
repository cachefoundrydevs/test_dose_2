`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_s0_stress;
`ifdef TINY
    localparam SETS = 4, WAYS = 2, LSU_BUF = 4, MSHR = 2, NCE = 1, VCS = 2, RFIFO = 2;
`else
    localparam SETS = `L1D_SETS, WAYS = `L1D_WAYS, LSU_BUF = `L1D_LSU_BUF_DEPTH,
               MSHR = `L1D_MSHR_ENTRIES, NCE = `L1D_MSHR_NC_ENTRIES, VCS = `L1D_VC_SLOTS,
               RFIFO = `L1D_RESP_FIFO_DEPTH;
`endif
`ifdef NOPS
    localparam N_OPS = `NOPS;
`else
    localparam N_OPS = 3000;
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
        scenario_skid(200);
        scenario_order(200);
        scenario_replay(600);
        scenario_sameset(24);
        scenario_random(N_OPS);
        s0_report;
        check(cov_skid_full_port[0] > 0 && cov_skid_full_port[1] > 0 && cov_skid_full_port[2] > 0,
                                       "coverage: the skid of every scalar port held 2 requests");
        check(cov_late_send > 0,       "coverage: requests were sent while their stop was 1 (late LSU)");
        check(cov_ring_max >= 4,       "coverage: an order ring held 4 or more requests");
        check(cov_from_ring > 0,       "coverage: requests were granted from an order ring");
        check(cov_replay_max >= 2,     "coverage: a request tracker held 2 or more entries (was the replay queue)");
        check(cov_pipe_conflict > 0,   "coverage: a fresh request was cancelled in stage R by a same-set hazard (ghost, re-issued)");
        check(cov_replay_conflict > 0, "coverage: an arriving request got a dependency on an older same-set tracker entry");
        finish_tb("tb_s0_stress");
    end
endmodule
