`timescale 1ns/1ps
`include "l1d_defines.vh"
`include "tb_top_select.vh"
module tb_prefetch;
`ifdef RLAT
    localparam RLAT = `RLAT;
`else
    localparam RLAT = 10;
`endif
`ifdef BLAT
    localparam BLAT = `BLAT;
`else
    localparam BLAT = 6;
`endif
    localparam ADDR_W   = `L1D_ADDR_W;
    localparam WDW      = `L1D_WRITE_DATA_WIDTH;
    localparam IDX_BITS = `L1D_IDX_BITS;
    localparam NB       = `L1D_NUM_BANKS;
    localparam LINE     = `L1D_LINE_BYTES;
    localparam SETS     = `L1D_SETS;
    localparam VCS      = `L1D_VC_SLOTS;
    localparam AXI_DW   = `L1D_AXI_DATA_W;
    localparam AXI_AW   = `L1D_AXI_ADDR_W;
    localparam AXI_IDW  = 6;
    localparam BEATS    = LINE * 8 / AXI_DW;
    localparam PKT_LINE_EXTRA = 2 + BEATS;
    localparam PKT_NC_EXTRA   = 3;
    localparam OFF_W    = $clog2(LINE);
    localparam BANK_W   = $clog2(NB);
    localparam SET_W    = $clog2(SETS);
    localparam TAG_LSB  = OFF_W + BANK_W + SET_W;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;
    reg                 flush = 0, clean = 0;
    wire                flush_complete, clean_complete, mem_err;
    reg                 valid_cpu = 0, cacheable = 1, rd_wr_cpu = 0;
    reg  [1:0]          mem_size_cpu = 3;
    reg  [1:0]          master_id_from_cpu = 0;
    reg  [IDX_BITS-1:0] idx_from_cpu = 0;
    reg  [ADDR_W-1:0]   PC_from_cpu = 0;
    reg  [WDW-1:0]      data_from_cpu = 0;
    reg                 read_enable_from_lsu = 1;
    wire                r_valid, r_rdwr;
    wire [1:0]          r_size, r_mid;
    wire [IDX_BITS-1:0] r_idx;
    wire [WDW-1:0]      r_data;
    wire [AXI_IDW-1:0]  awid, arid;
    reg  [AXI_IDW-1:0]  bid, rid;
    wire [AXI_AW-1:0]   awaddr, araddr;
    wire [7:0]          awlen, arlen;
    wire [2:0]          awsize, arsize, awprot, arprot;
    wire [1:0]          awburst, arburst;
    wire [3:0]          awcache, arcache;
    wire                awvalid, wvalid, wlast, bready, arvalid, rready;
    reg                 bvalid = 0, rvalid = 0, rlast = 0;
    wire [AXI_DW-1:0]   wdata;
    reg  [AXI_DW-1:0]   rdata;
    wire [AXI_DW/8-1:0] wstrb;
    `L1D_TB_TOP #(.AXI_ID_W(AXI_IDW)) dut (
        .clk(clk), .rst(rst),
        .flush_request(flush), .clean_request(clean), .flush_complete(flush_complete), .clean_complete(clean_complete),
        .cpu_request_valid(valid_cpu), .cpu_request_cacheable(cacheable), .cpu_request_is_write(rd_wr_cpu), .cpu_request_size(mem_size_cpu),
        .cpu_request_master_id(master_id_from_cpu), .cpu_request_rob_index(idx_from_cpu),
        .cpu_request_addr(PC_from_cpu), .cpu_request_store_data(data_from_cpu),
        .cpu_request_is_atomic(1'b0), .cpu_request_atomic_is_amo(1'b0), .cpu_request_amo_op(4'd0),
        .snoop_request_valid(1'b0), .snoop_request_ready(), .snoop_request_addr({ADDR_W{1'b0}}), .snoop_request_invalidate(1'b0),
        .snoop_response_valid(), .snoop_response_ready(1'b1), .snoop_response_addr(), .snoop_response_present(), .snoop_response_dirty(), .snoop_response_data(),
        .amo_lock_timeout_sticky(),
        .lsu_response_read_enable(read_enable_from_lsu),
        .lsu_response_valid(r_valid), .lsu_response_is_write_ack(r_rdwr),
        .lsu_response_size(r_size), .lsu_response_master_id(r_mid),
        .lsu_response_rob_index(r_idx), .lsu_response_data(r_data),
        .axi_error_sticky(mem_err),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awcache(awcache), .m_axi_awprot(awprot),
        .m_axi_awvalid(awvalid), .m_axi_awready(1'b1),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(1'b1),
        .m_axi_bid(bid), .m_axi_bresp(2'b00), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arcache(arcache), .m_axi_arprot(arprot),
        .m_axi_arvalid(arvalid), .m_axi_arready(1'b1), .m_axi_aruser(), .m_axi_ruser(1'b0),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(2'b00), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );
    localparam QD = 16;
    reg [AXI_IDW-1:0] rq_id  [0:QD-1];
    reg [AXI_AW-1:0]  rq_ad  [0:QD-1];
    reg [7:0]         rq_len [0:QD-1];
    integer           rq_t   [0:QD-1];
    integer           rq_n = 0;
    integer           r_beat = 0;
    reg [AXI_IDW-1:0] bq_id  [0:QD-1];
    integer           bq_t   [0:QD-1];
    integer           bq_n = 0;
    reg [AXI_IDW-1:0] aw_id_r;
    integer k;
    always @(posedge clk) begin
        if (rst) begin
            rq_n <= 0; r_beat <= 0; bq_n <= 0;
            rvalid <= 1'b0; bvalid <= 1'b0;
        end else begin : mem_step
            integer n_r, n_b, beat;
            reg [63:0] rd_word;
            n_r  = rq_n;
            n_b  = bq_n;
            beat = r_beat;
            if (rvalid) begin
                if (rlast) begin
                    for (k = 0; k < QD - 1; k = k + 1) begin
                        rq_id[k] = rq_id[k+1]; rq_ad[k] = rq_ad[k+1];
                        rq_len[k] = rq_len[k+1]; rq_t[k] = rq_t[k+1];
                    end
                    n_r  = n_r - 1;
                    beat = 0;
                end else begin
                    beat = beat + 1;
                end
            end
            if (arvalid) begin
                rq_id[n_r] = arid; rq_ad[n_r] = araddr; rq_len[n_r] = arlen; rq_t[n_r] = cyc;
                n_r = n_r + 1;
            end
            rd_word = rq_ad[0] + beat * (AXI_DW / 8);
            if (n_r > 0 && (cyc + 1 >= rq_t[0] + RLAT)) begin
                rvalid <= 1'b1;
                rid    <= rq_id[0];
                rlast  <= (beat == rq_len[0]);
                rdata  <= {(AXI_DW/64){rd_word}};
            end else begin
                rvalid <= 1'b0;
            end
            if (bvalid) begin
                for (k = 0; k < QD - 1; k = k + 1) begin
                    bq_id[k] = bq_id[k+1]; bq_t[k] = bq_t[k+1];
                end
                n_b = n_b - 1;
            end
            if (awvalid) aw_id_r <= awid;
            if (wvalid && wlast) begin
                bq_id[n_b] = awvalid ? awid : aw_id_r;
                bq_t[n_b]  = cyc;
                n_b = n_b + 1;
            end
            if (n_b > 0 && (cyc + 1 >= bq_t[0] + BLAT)) begin
                bvalid <= 1'b1;
                bid    <= bq_id[0];
            end else begin
                bvalid <= 1'b0;
            end
            rq_n   <= n_r;
            bq_n   <= n_b;
            r_beat <= beat;
        end
    end
    integer c0 = 0;
    reg     trace = 0;
    integer t_issue [0:(1<<IDX_BITS)-1];
    integer t_resp  [0:(1<<IDX_BITS)-1];
    reg [WDW-1:0] d_resp [0:(1<<IDX_BITS)-1];
    reg     pend    [0:(1<<IDX_BITS)-1];
    integer errors = 0;
    integer next_idx = 0;
    always @(posedge clk) begin
        if (!rst && r_valid && read_enable_from_lsu) begin
            if (!pend[r_idx]) begin
                $display("ERROR: response for idle idx %0d", r_idx);
                errors = errors + 1;
            end
            pend[r_idx]   <= 1'b0;
            t_resp[r_idx] <= cyc;
            d_resp[r_idx] <= r_data;
        end
    end
    function [ADDR_W-1:0] mk;
        input integer tag, set, bank, off;
        begin
            mk = ({{(ADDR_W-32){1'b0}}, tag[31:0]} << TAG_LSB) | (set << (OFF_W + BANK_W)) |
                 (bank << OFF_W) | off;
        end
    endfunction
    task issue;
        input        wr;
        input        cach;
        input [ADDR_W-1:0] a;
        output integer id;
        begin
            id = next_idx;
            next_idx = (next_idx + 1) % (1 << IDX_BITS);
            valid_cpu    = 1'b1;
            rd_wr_cpu    = wr;
            cacheable    = cach;
            mem_size_cpu = 2'd3;
            idx_from_cpu = id;
            PC_from_cpu  = a;
            data_from_cpu = {a[31:0], 32'h5a5a_0000 | id};
            pend[id]     = 1'b1;
            t_issue[id]  = cyc;
            @(negedge clk);
        end
    endtask
    task idle;
        begin
            valid_cpu = 1'b0;
        end
    endtask
    task wait_done;
        input integer id;
        begin
            while (pend[id]) @(posedge clk);
            @(negedge clk);
        end
    endtask
    task settle;
        begin
            repeat (40) @(negedge clk);
        end
    endtask
    task check;
        input [8*40-1:0] name;
        input integer id;
        input integer want;
        integer got;
        begin
            got = t_resp[id] - t_issue[id];
            if (got == want)
                $display("  RESULT %0s: latency %0d cycles (expected %0d) OK", name, got, want);
            else begin
                $display("  RESULT %0s: latency %0d cycles, EXPECTED %0d  <-- MISMATCH", name, got, want);
                errors = errors + 1;
            end
        end
    endtask
    task begin_scn;
        input [8*100-1:0] title;
        begin
            $display("");
            $display("=== %0s ===", title);
            c0 = cyc;
            next_idx = 0;
            trace = 1;
        end
    endtask
    task vc_valid_line;
        output [ADDR_W-1:0] a;
        output integer      found;
        integer s;
        begin
            found = 0;
            a = 0;
            for (s = 0; s < VCS; s = s + 1)
                if (!found && dut.u_ports.u_dcache.g_bank[0].u_bank.u_vc.st[s] == 3'd1) begin
                    a = {dut.u_ports.u_dcache.g_bank[0].u_bank.u_vc.la[s], {OFF_W{1'b0}}};
                    found = 1;
                end
        end
    endtask
    integer fb_issued = 0, fb_in_cache = 0, fb_in_flight = 0, fb_dropped = 0, pf_hits = 0;
    integer cnt_bank;
    always @(posedge clk) if (!rst) begin
        if (dut.u_ports.u_dcache.g_bank[0].u_bank.pf_fb_valid) count_fb(dut.u_ports.u_dcache.g_bank[0].u_bank.pf_fb_result);
        if (dut.u_ports.u_dcache.g_bank[1].u_bank.pf_fb_valid) count_fb(dut.u_ports.u_dcache.g_bank[1].u_bank.pf_fb_result);
        if (dut.u_ports.u_dcache.g_bank[2].u_bank.pf_fb_valid) count_fb(dut.u_ports.u_dcache.g_bank[2].u_bank.pf_fb_result);
        if (dut.u_ports.u_dcache.g_bank[3].u_bank.pf_fb_valid) count_fb(dut.u_ports.u_dcache.g_bank[3].u_bank.pf_fb_result);
        if (dut.u_ports.u_dcache.g_bank[0].u_bank.train_valid && dut.u_ports.u_dcache.g_bank[0].u_bank.train_pf_hit) pf_hits = pf_hits + 1;
        if (dut.u_ports.u_dcache.g_bank[1].u_bank.train_valid && dut.u_ports.u_dcache.g_bank[1].u_bank.train_pf_hit) pf_hits = pf_hits + 1;
        if (dut.u_ports.u_dcache.g_bank[2].u_bank.train_valid && dut.u_ports.u_dcache.g_bank[2].u_bank.train_pf_hit) pf_hits = pf_hits + 1;
        if (dut.u_ports.u_dcache.g_bank[3].u_bank.train_valid && dut.u_ports.u_dcache.g_bank[3].u_bank.train_pf_hit) pf_hits = pf_hits + 1;
    end
    task count_fb;
        input [1:0] code;
        begin
            case (code)
                2'd0: fb_issued    = fb_issued + 1;
                2'd1: fb_in_cache  = fb_in_cache + 1;
                2'd2: fb_in_flight = fb_in_flight + 1;
                default: fb_dropped = fb_dropped + 1;
            endcase
        end
    endtask
    task expect_true;
        input        cond;
        input [8*90-1:0] what;
        begin
            if (cond) $display("  CHECK %0s: OK", what);
            else begin $display("  CHECK %0s: FAILED", what); errors = errors + 1; end
        end
    endtask
    localparam N_LINES = 48;
    localparam GAP     = 12;
    integer id0, line_n, hits, misses, data_bad, lat;
    reg [ADDR_W-1:0] a;
    task walk;
        input [ADDR_W-1:0] base;
        begin
            hits = 0; misses = 0; data_bad = 0;
            for (line_n = 0; line_n < N_LINES; line_n = line_n + 1) begin
                a = base + line_n * LINE + 8;
                begin_scn("walk"); trace = 0;
                issue(0, 1, a, id0); idle; wait_done(id0);
                lat = t_resp[id0] - t_issue[id0];
                if (lat == 4) hits = hits + 1; else misses = misses + 1;
                if (d_resp[id0] !== {a[ADDR_W-1:6], 6'd0}) begin
                    data_bad = data_bad + 1;
                    $display("  ERROR load %0h returned %h, expected %h", a, d_resp[id0], {a[ADDR_W-1:6], 6'd0});
                end
                repeat (GAP) @(negedge clk);
            end
        end
    endtask
    integer issued_before;
    initial begin
        for (k = 0; k < (1 << IDX_BITS); k = k + 1) pend[k] = 1'b0;
        force dut.u_ports.u_dcache.pf_enable = 1'b0;
        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (4) @(negedge clk);
        $display("=== 1. sequential walk of %0d lines, prefetch OFF (reference) ===", N_LINES);
        walk(64'h0000_0000_0010_0000);
        $display("  hits %0d, misses %0d, wrong data %0d; feedback issued %0d", hits, misses, data_bad, fb_issued);
        expect_true(data_bad == 0, "1: every load returns the memory data");
        expect_true(hits == 0, "1: no hit without prefetch (cold lines)");
        expect_true(fb_issued == 0, "1: no prefetch issued while pf_enable = 0");
        settle;
        $display("=== 2. sequential walk of %0d new lines, prefetch ON ===", N_LINES);
        release dut.u_ports.u_dcache.pf_enable;
        issued_before = fb_issued;
        walk(64'h0000_0000_0020_0000);
        $display("  hits %0d, misses %0d, wrong data %0d", hits, misses, data_bad);
        $display("  prefetch feedback: issued %0d, in cache %0d, in flight %0d, dropped %0d; demand hits on prefetched lines %0d",
                 fb_issued, fb_in_cache, fb_in_flight, fb_dropped, pf_hits);
        expect_true(data_bad == 0, "2: every load returns the memory data");
        expect_true(fb_issued > issued_before, "2: prefetches were issued (MSHR entries allocated)");
        expect_true(hits > 0, "2: some demand loads hit lines fetched ahead");
        expect_true(pf_hits > 0, "2: the banks reported first-use hits on prefetched lines (training feedback)");
        if (errors == 0) $display("TEST PASSED: tb_prefetch");
        else             $display("TEST FAILED: tb_prefetch (%0d errors)", errors);
        $finish;
    end
    initial begin
        #5000000;
        $display("TEST FAILED: tb_prefetch timeout");
        $finish;
    end
endmodule
