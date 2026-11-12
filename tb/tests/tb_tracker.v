`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_tracker;
    localparam SETS = `L1D_SETS, WAYS = `L1D_WAYS, LSU_BUF = `L1D_LSU_BUF_DEPTH,
               MSHR = `L1D_MSHR_ENTRIES, NCE = `L1D_MSHR_NC_ENTRIES, VCS = `L1D_VC_SLOTS,
               RFIFO = `L1D_RESP_FIFO_DEPTH;
`ifdef SEED
    localparam SEED0 = `SEED;
`else
    localparam SEED0 = 1;
`endif
`ifdef NOPS
    localparam N_RANDOM = `NOPS;
`else
    localparam N_RANDOM = 3000;
`endif
`include "tb_ports_common.vh"
    integer cov_skid_push = 0;
    integer cov_trk_full  = 0;
    integer cov_multi_alloc = 0;
    integer cv_b, cv_n;
    always @(posedge clk) if (!rst) begin
        if (|dut.u_dcache.u_front.skid_push) cov_skid_push = cov_skid_push + 1;
        for (cv_b = 0; cv_b < NB; cv_b = cv_b + 1) begin
            cv_n = dut.u_dcache.u_front.alloc_pred[cv_b*4 + 0] + dut.u_dcache.u_front.alloc_pred[cv_b*4 + 1] +
                   dut.u_dcache.u_front.alloc_pred[cv_b*4 + 2] + dut.u_dcache.u_front.alloc_pred[cv_b*4 + 3];
            if (cv_n >= 2) cov_multi_alloc = cov_multi_alloc + 1;
        end
        if (dut.u_dcache.g_bank[2].u_bank.u_s0.u_tracker.free_count_q == 0) cov_trk_full = cov_trk_full + 1;
    end
    integer e0, e1, e2, e3, lat0, lat1, lat2, n, pt, push_before;
    reg [ADDR_W-1:0] ra;
    initial begin
        init_tb;
        for (n = 0; n < 3; n = n + 1) begin
            send(0, K_LD, 1'b0, 2'd3, line_addr(0, n, 1), 0, OP_ADD, e0); tick; wait_entry(e0);
        end
        repeat (10) tick;
        $display("=== A: three ports, three sets of bank 1, one cycle ===");
        push_before = cov_skid_push;
        send(0, K_LD, 1'b0, 2'd3, line_addr(0, 0, 1) + 8, 0, OP_ADD, e0);
        send(1, K_LD, 1'b0, 2'd3, line_addr(0, 1, 1) + 8, 0, OP_ADD, e1);
        send(2, K_ST, 1'b0, 2'd3, line_addr(0, 2, 1) + 8, 64'h1111_2222_3333_4444, OP_ADD, e2);
        tick; wait_entry(e0); wait_entry(e1); wait_entry(e2);
        lat0 = got_t[e0] - out_t[e0]; lat1 = got_t[e1] - out_t[e1]; lat2 = got_t[e2] - out_t[e2];
        $display("  latencies: P0 %0d, P1 %0d, P2 (store) %0d", lat0, lat1, lat2);
        check(lat0 == 4 && lat1 == 5 && lat2 == 6, "A: three requests to one bank in one cycle answer at 4, 5, 6 (port order)");
        check(cov_skid_push == push_before, "A: all three got a tracker entry in the arrival cycle (no skid push)");
        repeat (10) tick;
        $display("=== B: three ports, ONE set of bank 1 (P0 load line X, P1 load line Y, P2 store line Z) ===");
        send(0, K_LD, 1'b0, 2'd3, line_addr(0, 0, 1) + 16, 0, OP_ADD, e0);
        send(1, K_LD, 1'b0, 2'd3, line_addr(1, 0, 1) + 16, 0, OP_ADD, e1);
        send(2, K_ST, 1'b0, 2'd3, line_addr(2, 0, 1) + 16, 64'h5555_6666_7777_8888, OP_ADD, e2);
        tick; wait_entry(e0); wait_entry(e1); wait_entry(e2);
        $display("  latencies: P0 %0d, P1 %0d, P2 (store) %0d", got_t[e0] - out_t[e0], got_t[e1] - out_t[e1], got_t[e2] - out_t[e2]);
        check(got_t[e2] > got_t[e0] && got_t[e2] > got_t[e1], "B: the store answers after both older loads of its set (deps at allocation)");
        repeat (10) tick;
        $display("=== C: misses flood bank 2 from three ports until the tracker is full ===");
        push_before = cov_skid_push;
        for (n = 0; n < 60; n = n + 1) begin
            for (pt = 0; pt < 3; pt = pt + 1) begin
                ra = line_addr(10 + n * 3 + pt, (n + pt) % SETS, 2) + 8 * pt;
                if (can_send(pt))
                    send(pt, (pt == 2) ? K_ST : K_LD, 1'b0, 2'd3, ra, {32'hC0DE_0000 | n, 32'h0 | pt}, OP_ADD, e0);
            end
            tick;
        end
        wait_drained(0);
        $display("  skid pushes %0d, cycles with bank 2's tracker full %0d", cov_skid_push - push_before, cov_trk_full);
        check(cov_trk_full > 0, "C: coverage: bank 2's tracker reached 8 entries");
        check(cov_skid_push > push_before, "C: coverage: requests spilled into the port skids and drained in order");
        $display("=== D: P2 store, then P0 and P1 load the same bytes one cycle later ===");
        send(0, K_LD, 1'b0, 2'd3, line_addr(0, 3, 3), 0, OP_ADD, e0); tick; wait_entry(e0);
        repeat (6) tick;
        send(2, K_ST, 1'b0, 2'd3, line_addr(0, 3, 3) + 24, 64'hDEAD_BEEF_0123_4567, OP_ADD, e2); tick;
        send(0, K_LD, 1'b0, 2'd3, line_addr(0, 3, 3) + 24, 0, OP_ADD, e0);
        send(1, K_LD, 1'b0, 2'd3, line_addr(0, 3, 3) + 24, 0, OP_ADD, e1); tick;
        wait_entry(e2); wait_entry(e0); wait_entry(e1);
        $display("  store %0d cycles, loads %0d and %0d cycles (data checked by the reference model: %h)",
                 got_t[e2] - out_t[e2], got_t[e0] - out_t[e0], got_t[e1] - out_t[e1], got_d[e0]);
        check(got_d[e0] == 64'hDEAD_BEEF_0123_4567 && got_d[e1] == 64'hDEAD_BEEF_0123_4567, "D: both loads return the stored value");
        $display("=== E: random traffic to two hot banks (%0d requests) ===", N_RANDOM);
        for (n = 0; n < N_RANDOM; ) begin
            for (pt = 0; pt < 3; pt = pt + 1) begin
                ra = line_addr({$random(seed)} % 6, {$random(seed)} % 4, ({$random(seed)} % 2) ? 0 : 3) + ({$random(seed)} % 8) * 8;
                if (n < N_RANDOM && can_send(pt) && !rule_r3_clash(ra, pt == ST_PORT) && ({$random(seed)} % 100) < 60) begin
                    send(pt, (pt == 2) ? K_ST : K_LD, 1'b0, 2'd3, ra, {$random(seed), $random(seed)}, OP_ADD, e0);
                    n = n + 1;
                end
            end
            tick;
        end
        wait_drained(20);
        check(cov_multi_alloc > 0, "E: coverage: a tracker allocated 2 or more arrivals in one cycle");
        pulse_and_wait(1);
        check_memory("E: memory equal to the reference after the flush");
        finish_tb("tb_tracker");
    end
endmodule
