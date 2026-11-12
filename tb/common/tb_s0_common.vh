    localparam SCALAR_PORTS = 3;
    localparam ORDER_LIMIT  = 8;
    localparam REPLAY_LIMIT = 8;
    integer cov_skid_full_port [0:SCALAR_PORTS-1];
    integer cov_late_send, cov_ring_max, cov_from_ring, cov_replay_max;
    integer cov_pipe_conflict, cov_replay_conflict, cov_replay_held, cov_replay_credit_stall;
    integer mon_skid_errors, mon_order_errors, mon_replay_errors, mon_cancel_errors;
    integer mon_port;
    initial begin
        for (mon_port = 0; mon_port < SCALAR_PORTS; mon_port = mon_port + 1) cov_skid_full_port[mon_port] = 0;
        cov_late_send = 0; cov_ring_max = 0; cov_from_ring = 0; cov_replay_max = 0;
        cov_pipe_conflict = 0; cov_replay_conflict = 0; cov_replay_held = 0; cov_replay_credit_stall = 0;
        mon_skid_errors = 0; mon_order_errors = 0; mon_replay_errors = 0; mon_cancel_errors = 0;
    end
    integer late_port;
    always @(posedge clk) if (!rst) begin
        for (late_port = 0; late_port < SCALAR_PORTS; late_port = late_port + 1)
            if (req_valid[late_port] && port_stop[late_port]) cov_late_send = cov_late_send + 1;
    end
    genvar mon_gport;
    generate
        for (mon_gport = 0; mon_gport < SCALAR_PORTS; mon_gport = mon_gport + 1) begin : g_mon_port
            wire       mon_push = dut.u_dcache.u_front.skid_push[mon_gport];
            wire       mon_full = dut.u_dcache.u_front.skid_full[mon_gport];
            wire [1:0] mon_used = dut.u_dcache.u_front.skid_used[mon_gport*2 +: 2];
            always @(posedge clk) if (!rst) begin
                if (mon_push && mon_full) begin
                    mon_skid_errors = mon_skid_errors + 1; errors = errors + 1;
                    $display("ERROR %0t: monitor: port %0d pushed a request into its full skid", $time, mon_gport);
                end
                if (mon_used == 2'd2)
                    cov_skid_full_port[mon_gport] = cov_skid_full_port[mon_gport] + 1;
            end
        end
    endgenerate
    localparam MON_TRK_READY_B = 0;
    genvar mon_gbank;
    generate
        for (mon_gbank = 0; mon_gbank < NB; mon_gbank = mon_gbank + 1) begin : g_mon_bank
            integer mon_src;
            integer mon_entry;
            always @(posedge clk) if (!rst) begin
                if (dut.u_dcache.u_front.g_bank[mon_gbank].u_order.order_count
                    + dut.u_dcache.u_front.g_bank[mon_gbank].u_order.join_cnt > ORDER_LIMIT) begin
                    mon_order_errors = mon_order_errors + 1; errors = errors + 1;
                    $display("ERROR %0t: monitor: order ring of bank %0d overflows", $time, mon_gbank);
                end
                if (dut.u_dcache.u_front.g_bank[mon_gbank].u_order.order_count > cov_ring_max)
                    cov_ring_max = dut.u_dcache.u_front.g_bank[mon_gbank].u_order.order_count;
                if (dut.u_dcache.u_front.g_bank[mon_gbank].u_order.pop)
                    cov_from_ring = cov_from_ring + 1;
                if (dut.u_dcache.g_bank[mon_gbank].u_bank.u_s0.u_tracker.free_count_q == 0
                    && (|dut.u_dcache.g_bank[mon_gbank].u_bank.u_s0.u_tracker.alloc)) begin
                    mon_replay_errors = mon_replay_errors + 1; errors = errors + 1;
                    $display("ERROR %0t: monitor: tracker of bank %0d allocated with no free entry", $time, mon_gbank);
                end
                if (REPLAY_LIMIT - dut.u_dcache.g_bank[mon_gbank].u_bank.u_s0.u_tracker.free_count_q > cov_replay_max)
                    cov_replay_max = REPLAY_LIMIT - dut.u_dcache.g_bank[mon_gbank].u_bank.u_s0.u_tracker.free_count_q;
                if (dut.u_dcache.g_bank[mon_gbank].u_bank.u_r.r_lsu && !dut.u_dcache.g_bank[mon_gbank].u_bank.u_r.r_fast
                    && !dut.u_dcache.g_bank[mon_gbank].u_bank.u_r.r_req[dut.u_dcache.g_bank[mon_gbank].u_bank.u_r.REQ_PF_BIT]
                    && (dut.u_dcache.g_bank[mon_gbank].u_bank.u_r.deps_hit || dut.u_dcache.g_bank[mon_gbank].u_bank.u_r.wl_hit
                        || dut.u_dcache.g_bank[mon_gbank].u_bank.u_r.amo_hit)) begin
                    mon_cancel_errors = mon_cancel_errors + 1; errors = errors + 1;
                    $display("ERROR %0t: monitor: bank %0d: a booked request sees a same-set hazard in stage R", $time, mon_gbank);
                end
                if (dut.u_dcache.g_bank[mon_gbank].u_bank.u_r.r_kill)
                    cov_pipe_conflict = cov_pipe_conflict + 1;
                for (mon_src = 0; mon_src < 5; mon_src = mon_src + 1)
                    if (dut.u_dcache.g_bank[mon_gbank].u_bank.u_s0.u_tracker.alloc[mon_src]
                        && (|dut.u_dcache.g_bank[mon_gbank].u_bank.u_s0.u_tracker.deps_new[mon_src]))
                        cov_replay_conflict = cov_replay_conflict + 1;
                for (mon_entry = 0; mon_entry < REPLAY_LIMIT; mon_entry = mon_entry + 1)
                    if (dut.u_dcache.g_bank[mon_gbank].u_bank.u_s0.u_tracker.valid_q[mon_entry]
                        && dut.u_dcache.g_bank[mon_gbank].u_bank.u_s0.u_tracker.state_q[mon_entry][MON_TRK_READY_B]
                        && (|dut.u_dcache.g_bank[mon_gbank].u_bank.u_s0.u_tracker.deps_q[mon_entry]))
                        cov_replay_held = cov_replay_held + 1;
                if ((|dut.u_dcache.g_bank[mon_gbank].u_bank.u_s0.u_tracker.lowest_req)
                    && !dut.u_dcache.g_bank[mon_gbank].u_bank.u_s0.u_tracker.lowest_credit)
                    cov_replay_credit_stall = cov_replay_credit_stall + 1;
            end
        end
    endgenerate
    integer s0_entry;
    task send_typed;
        input integer      port_num;
        input [ADDR_W-1:0] addr;
        input integer      amo_pct;
        begin
            if (can_send(port_num) && !rule_r3_clash(addr, port_num == ST_PORT)) begin
                if (port_num != ST_PORT)
                    send(port_num, K_LD, 1'b0, 2'd3, addr, 64'd0, OP_ADD, s0_entry);
                else if (({$random(seed)} % 100) < amo_pct)
                    send(port_num, K_AMO, 1'b0, 2'd3, addr, {$random(seed), $random(seed)}, {$random(seed)} % 9, s0_entry);
                else
                    send(port_num, K_ST, 1'b0, 2'd3, addr, {$random(seed), $random(seed)}, OP_ADD, s0_entry);
            end
        end
    endtask
    task send_when_free;
        input integer      port_num;
        input [2:0]        kind;
        input [ADDR_W-1:0] addr;
        input [WDW-1:0]    data;
        integer            waited;
        begin
            waited = 0;
            while ((!can_send(port_num) || rule_r3_clash(addr, kind != K_LD)) && waited < 20000) begin tick; waited = waited + 1; end
            send(port_num, kind, 1'b0, 2'd3, addr, data, OP_ADD, s0_entry);
        end
    endtask
    function [ADDR_W-1:0] word_in_line;
        input integer tag_num, set_num, bank_num;
        begin
            word_in_line = line_addr(tag_num, set_num, bank_num) + 8 * ({$random(seed)} % 8);
        end
    endfunction
    task release_and_drain;
        begin
            stop_lag    = 0;
            read_enable = {PORTS{1'b1}};
            tick;
            wait_drained(0);
        end
    endtask
    integer scen_step, scen_port, scen_pair;
    task scenario_skid;
        input integer cycles_n;
        begin
            $display("=== scenario SKID: late stop, answers stalled, %0d cycles ===", cycles_n);
            stop_lag    = 1;
            read_enable = {PORTS{1'b0}};
            for (scen_step = 0; scen_step < cycles_n; scen_step = scen_step + 1) begin
                tick;
                for (scen_port = 0; scen_port < SCALAR_PORTS; scen_port = scen_port + 1)
                    send_typed(scen_port, word_in_line(0, scen_port, 0), 0);
                if (scen_step % 50 == 49) read_enable = {PORTS{1'b1}};
                if (scen_step % 50 == 3)  read_enable = {PORTS{1'b0}};
            end
            release_and_drain;
            $display("  skid full (port-cycles): P0 %0d P1 %0d P2 %0d; late sends %0d",
                     cov_skid_full_port[0], cov_skid_full_port[1], cov_skid_full_port[2], cov_late_send);
        end
    endtask
    task scenario_order;
        input integer cycles_n;
        begin
            $display("=== scenario ORDER: three ports on bank 1, late stop, %0d cycles ===", cycles_n);
            stop_lag    = 1;
            read_enable = {PORTS{1'b0}};
            for (scen_step = 0; scen_step < cycles_n; scen_step = scen_step + 1) begin
                tick;
                for (scen_port = 0; scen_port < SCALAR_PORTS; scen_port = scen_port + 1)
                    send_typed(scen_port, word_in_line(scen_port % 2, {$random(seed)} % NS, 1), 0);
                if (scen_step % 40 == 39) read_enable = {PORTS{1'b1}};
                if (scen_step % 40 == 5)  read_enable = {PORTS{1'b0}};
            end
            release_and_drain;
            $display("  largest order ring fill %0d, %0d grants taken from a ring", cov_ring_max, cov_from_ring);
        end
    endtask
    task scenario_replay;
        input integer cycles_n;
        begin
            $display("=== scenario REPLAY: miss flood on bank 2, %0d cycles ===", cycles_n);
            for (scen_step = 0; scen_step < cycles_n; scen_step = scen_step + 1) begin
                tick;
                for (scen_port = 0; scen_port < ST_PORT; scen_port = scen_port + 1)
                    send_typed(scen_port, word_in_line({$random(seed)} % NT, {$random(seed)} % NS, 2), 0);
                if (({$random(seed)} % 100) < 40)
                    send_typed(ST_PORT, word_in_line({$random(seed)} % NT, {$random(seed)} % NS, 2), 10);
                for (scen_port = 0; scen_port < PORTS; scen_port = scen_port + 1)
                    read_enable[scen_port] = (({$random(seed)} % 100) < 85);
            end
            release_and_drain;
            $display("  replay queue fill up to %0d; held by a waiting entry %0d; replay entry held %0d; no credit %0d",
                     cov_replay_max, cov_replay_conflict, cov_replay_held, cov_replay_credit_stall);
        end
    endtask
    task scenario_sameset;
        input integer pairs_n;
        reg [ADDR_W-1:0] pair_addr;
        reg [WDW-1:0]    pair_data;
        begin
            $display("=== scenario SAME-SET: %0d directed pairs on bank 3 ===", pairs_n);
            for (scen_pair = 0; scen_pair < pairs_n; scen_pair = scen_pair + 1) begin
                pair_addr = line_addr(scen_pair % NT, scen_pair % NS, 3) + 8 * (scen_pair % 8);
                pair_data[WDW-1:32] = 32'h5E75_0000 | scen_pair;
                pair_data[31:0]     = scen_pair * 7;
                case (scen_pair % 4)
                    0: begin
                           tick; send_when_free(ST_PORT, K_ST, pair_addr, pair_data);
                           tick; send_when_free(0, K_LD, pair_addr, 64'd0);
                       end
                    1: begin
                           tick; send_when_free(ST_PORT, K_AMO, pair_addr, 64'd3);
                           tick; send_when_free(1, K_LD, pair_addr, 64'd0);
                       end
                    2: begin
                           tick; send_when_free(0, K_LD, line_addr((scen_pair + 5) % NT, scen_pair % NS, 3), 64'd0);
                           tick; send_when_free(ST_PORT, K_ST, line_addr((scen_pair + 5) % NT, scen_pair % NS, 3), pair_data);
                       end
                    default: begin
                           tick; send_when_free(ST_PORT, K_ST, pair_addr, pair_data);
                           tick; send_when_free(ST_PORT, K_ST, pair_addr, ~pair_data);
                           tick; send_when_free(1, K_LD, pair_addr, 64'd0);
                       end
                endcase
            end
            release_and_drain;
            $display("  port requests held against the pipeline %0d times", cov_pipe_conflict);
        end
    endtask
    task scenario_random;
        input integer requests_n;
        integer start_issued, random_cycles;
        begin
            $display("=== scenario RANDOM: %0d requests on two banks ===", requests_n);
            start_issued  = issued;
            random_cycles = 0;
            while (issued < start_issued + requests_n && random_cycles < 400000) begin
                tick;
                random_cycles = random_cycles + 1;
                if (random_cycles % 97 == 0) stop_lag = ({$random(seed)} % 2);
                for (scen_port = 0; scen_port < SCALAR_PORTS; scen_port = scen_port + 1)
                    if (({$random(seed)} % 100) < 60)
                        send_typed(scen_port, word_in_line({$random(seed)} % NT, {$random(seed)} % NS, 1 + ({$random(seed)} % 2)), 10);
                for (scen_port = 0; scen_port < PORTS; scen_port = scen_port + 1)
                    read_enable[scen_port] = (({$random(seed)} % 100) < 70);
            end
            release_and_drain;
        end
    endtask
    task s0_report;
        begin
            pulse_and_wait(1'b1);
            check_memory("flush");
            $display("coverage: skid full P0 %0d P1 %0d P2 %0d, late sends %0d, ring max %0d, from ring %0d, replay max %0d",
                     cov_skid_full_port[0], cov_skid_full_port[1], cov_skid_full_port[2], cov_late_send,
                     cov_ring_max, cov_from_ring, cov_replay_max);
            $display("coverage: pipe conflicts %0d, replay conflicts %0d, replay entries held %0d, replay credit stalls %0d",
                     cov_pipe_conflict, cov_replay_conflict, cov_replay_held, cov_replay_credit_stall);
            $display("monitor errors: skid %0d, order %0d, replay %0d, stage R cancel %0d",
                     mon_skid_errors, mon_order_errors, mon_replay_errors, mon_cancel_errors);
        end
    endtask
