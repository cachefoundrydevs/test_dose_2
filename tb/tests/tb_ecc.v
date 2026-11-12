`timescale 1ns/1ps
`include "l1d_defines.vh"
`include "tb_top_select.vh"
module tb_ecc;
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
    integer ce_pulses = 0;
    always @(posedge clk) if (!rst && dut.u_ports.u_dcache.ecc_correctable_pulse) ce_pulses = ce_pulses + 1;
    localparam DWORD_W  = 576;
    localparam TWORD_W  = 57;
    localparam WAYS     = `L1D_WAYS;
    task flip_data_bit;
        input integer set;
        input integer bitpos;
        begin
            dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_data.g_way[0].u_ram.mem[set][bitpos] = ~dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_data.g_way[0].u_ram.mem[set][bitpos];
            dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_data.g_way[1].u_ram.mem[set][bitpos] = ~dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_data.g_way[1].u_ram.mem[set][bitpos];
            dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_data.g_way[2].u_ram.mem[set][bitpos] = ~dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_data.g_way[2].u_ram.mem[set][bitpos];
            dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_data.g_way[3].u_ram.mem[set][bitpos] = ~dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_data.g_way[3].u_ram.mem[set][bitpos];
        end
    endtask
    task flip_tag_bit;
        input integer set;
        input integer bitpos;
        begin
            dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_tags.g_way[0].u_ram.mem[set][bitpos] = ~dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_tags.g_way[0].u_ram.mem[set][bitpos];
            dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_tags.g_way[1].u_ram.mem[set][bitpos] = ~dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_tags.g_way[1].u_ram.mem[set][bitpos];
            dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_tags.g_way[2].u_ram.mem[set][bitpos] = ~dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_tags.g_way[2].u_ram.mem[set][bitpos];
            dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_tags.g_way[3].u_ram.mem[set][bitpos] = ~dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_tags.g_way[3].u_ram.mem[set][bitpos];
        end
    endtask
    function [DWORD_W-1:0] data_word0;
        input integer set;
        data_word0 = dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_data.g_way[0].u_ram.mem[set];
    endfunction
    function [TWORD_W-1:0] tag_word0;
        input integer set;
        tag_word0 = dut.u_ports.u_dcache.g_bank[0].u_bank.u_r.u_tags.g_way[0].u_ram.mem[set];
    endfunction
    task expect_true;
        input        cond;
        input [8*90-1:0] what;
        begin
            if (cond) $display("  CHECK %0s: OK", what);
            else begin $display("  CHECK %0s: FAILED", what); errors = errors + 1; end
        end
    endtask
    integer id0, id1, pulses_before;
    reg [ADDR_W-1:0]  a_addr;
    reg [WDW-1:0]     a_data;
    reg [DWORD_W-1:0] good_data_word;
    reg [TWORD_W-1:0] good_tag_word;
    initial begin
        for (k = 0; k < (1 << IDX_BITS); k = k + 1) pend[k] = 1'b0;
        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (4) @(negedge clk);
        a_addr = mk(1, 5, 0, 8);
        a_data = {a_addr[ADDR_W-1:6], 6'd0};
        $display("=== 1. cold miss of A, then a hit ===");
        begin_scn("1"); trace = 0;
        issue(0, 1, a_addr, id0); idle; wait_done(id0);
        expect_true(d_resp[id0] == a_data, "1: miss returns the memory data");
        settle;
        begin_scn("1b"); trace = 0;
        issue(0, 1, a_addr, id0); idle; wait_done(id0);
        expect_true(d_resp[id0] == a_data, "1: hit returns the same data");
        expect_true(t_resp[id0] - t_issue[id0] == 4, "1: hit latency 4");
        expect_true(ce_pulses == 0, "1: no ECC event on clean lines");
        expect_true(!dut.u_ports.u_dcache.ecc_uncorrectable_sticky, "1: no uncorrectable error");
        good_data_word = data_word0(5);
        good_tag_word  = tag_word0(5);
        settle;
        $display("=== 2. one data bit flipped in A's granule (line bit 70) ===");
        flip_data_bit(5, 70);
        expect_true(data_word0(5) != good_data_word, "2: the SRAM word is now wrong");
        pulses_before = ce_pulses;
        begin_scn("2"); trace = 0;
        issue(0, 1, a_addr, id0); idle; wait_done(id0);
        $display("  load with a single-bit data error: data %h, latency %0d", d_resp[id0], t_resp[id0] - t_issue[id0]);
        expect_true(d_resp[id0] == a_data, "2: the CPU gets the corrected data");
        expect_true(t_resp[id0] - t_issue[id0] > 4, "2: the load took the scrub path (re-issued)");
        expect_true(ce_pulses == pulses_before + 1, "2: exactly one ecc_correctable_pulse");
        settle;
        expect_true(data_word0(5) == good_data_word, "2: the SRAM word was repaired (scrub written)");
        begin_scn("2b"); trace = 0;
        issue(0, 1, a_addr, id0); idle; wait_done(id0);
        expect_true(t_resp[id0] - t_issue[id0] == 4 && d_resp[id0] == a_data, "2: next load hits in 4 cycles, right data");
        expect_true(ce_pulses == pulses_before + 1, "2: no new pulse after the repair");
        settle;
        $display("=== 3. one CHECK bit flipped (data word bit 512 + 9: granule 1, check bit 1) ===");
        flip_data_bit(5, 512 + 9);
        pulses_before = ce_pulses;
        begin_scn("3"); trace = 0;
        issue(0, 1, a_addr, id0); idle; wait_done(id0);
        expect_true(d_resp[id0] == a_data, "3: the CPU gets the right data");
        expect_true(ce_pulses == pulses_before + 1, "3: one ecc_correctable_pulse");
        settle;
        expect_true(data_word0(5) == good_data_word, "3: the check bit was repaired");
        settle;
        $display("=== 4. one TAG bit flipped (tag bit 3) ===");
        flip_tag_bit(5, 3);
        expect_true(tag_word0(5) != good_tag_word, "4: the SRAM tag is now wrong");
        pulses_before = ce_pulses;
        begin_scn("4"); trace = 0;
        issue(0, 1, a_addr, id0); idle; wait_done(id0);
        $display("  load with a single-bit tag error: data %h, latency %0d", d_resp[id0], t_resp[id0] - t_issue[id0]);
        expect_true(d_resp[id0] == a_data, "4: the CPU gets A's data (no false miss / hit)");
        expect_true(ce_pulses >= pulses_before + 1, "4: an ecc_correctable_pulse for the tag scrub");
        settle;
        expect_true(tag_word0(5) == good_tag_word, "4: the SRAM tag was repaired");
        expect_true(!dut.u_ports.u_dcache.ecc_uncorrectable_sticky, "4: still no uncorrectable error");
        settle;
        $display("=== 5. store hit, then load: new data, new check bits, no ECC event ===");
        pulses_before = ce_pulses;
        begin_scn("5"); trace = 0;
        issue(1, 1, a_addr, id0); idle; wait_done(id0);
        issue(0, 1, a_addr, id1); idle; wait_done(id1);
        expect_true(d_resp[id1] == {a_addr[31:0], 32'h5a5a_0000}, "5: the load returns the stored data");
        expect_true(ce_pulses == pulses_before, "5: no ECC event (the store wrote good check bits)");
        settle;
        $display("=== 6. two data bits flipped in one granule (line bits 70 and 75) ===");
        flip_data_bit(5, 70);
        flip_data_bit(5, 75);
        begin_scn("6"); trace = 0;
        issue(0, 1, a_addr, id0); idle; wait_done(id0);
        $display("  load with a double-bit data error: data %h (not checked), latency %0d", d_resp[id0], t_resp[id0] - t_issue[id0]);
        expect_true(dut.u_ports.u_dcache.ecc_uncorrectable_sticky, "6: ecc_uncorrectable_sticky is set");
        settle;
        if (errors == 0) $display("TEST PASSED: tb_ecc");
        else             $display("TEST FAILED: tb_ecc (%0d errors)", errors);
        $finish;
    end
    initial begin
        #2000000;
        $display("TEST FAILED: tb_ecc timeout");
        $finish;
    end
endmodule
