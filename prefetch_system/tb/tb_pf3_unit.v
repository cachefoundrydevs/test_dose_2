`timescale 1ns/1ps
`default_nettype none
module tb_pf3_unit;
    localparam NB     = 4;
    localparam PC_W   = 64;
    localparam ADDR_W = 64;
    localparam LINE_W = 58;
    reg clk;
    reg rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;
    reg                  pf_enable;
    reg  [NB-1:0]        train_valid;
    reg  [NB*PC_W-1:0]   train_pc;
    reg  [NB*ADDR_W-1:0] train_addr;
    reg  [NB-1:0]        train_is_store;
    reg  [NB-1:0]        train_miss;
    reg  [NB-1:0]        train_pf_hit;
    reg  [NB-1:0]        train_no_train;
    reg  [NB-1:0]        evict_valid;
    reg  [NB*LINE_W-1:0] evict_line_addr;
    reg  [NB-1:0]        pf_fb_valid;
    reg  [NB*LINE_W-1:0] pf_fb_line_addr;
    reg  [NB*2-1:0]      pf_fb_result;
    reg  [NB-1:0]        pf_req_ready;
    wire [NB-1:0]        pf_req_valid;
    wire [NB*LINE_W-1:0] pf_req_line_addr;
    wire [NB-1:0]        pf_req_unique;
    l1d_prefetch_unit u_dut (
        .clk              (clk),
        .rst              (rst),
        .pf_enable        (pf_enable),
        .train_valid      (train_valid),
        .train_pc         (train_pc),
        .train_addr       (train_addr),
        .train_is_store   (train_is_store),
        .train_miss       (train_miss),
        .train_pf_hit     (train_pf_hit),
        .train_no_train   (train_no_train),
        .evict_valid      (evict_valid),
        .evict_line_addr  (evict_line_addr),
        .pf_fb_valid      (pf_fb_valid),
        .pf_fb_line_addr  (pf_fb_line_addr),
        .pf_fb_result     (pf_fb_result),
        .pf_req_ready     (pf_req_ready),
        .pf_req_valid     (pf_req_valid),
        .pf_req_line_addr (pf_req_line_addr),
        .pf_req_unique    (pf_req_unique)
    );
    integer   cyc, err_cnt, seed, nrec, n, b, lane, g;
    reg [NB-1:0] ready_q;
    reg [NB-1:0] fb_pipe [0:3];
    integer   hint_n;
    integer   hint_cyc  [0:1023];
    integer   hint_bank [0:1023];
    reg [LINE_W-1:0] hint_line [0:1023];
    always @(posedge clk) begin
        if (rst) begin
            ready_q <= {NB{1'b1}};
            fb_pipe[0] <= 0; fb_pipe[1] <= 0; fb_pipe[2] <= 0; fb_pipe[3] <= 0;
            pf_fb_valid <= 0;
        end
        else begin
            cyc = cyc + 1;
            for (b = 0; b < NB; b = b + 1) begin
                if (pf_req_valid[b]) begin
                    if (!ready_q[b]) begin
                        $display("ERROR cycle %0d: hint to bank %0d that was not ready", cyc, b);
                        err_cnt = err_cnt + 1;
                    end
                    if (pf_req_line_addr[b*LINE_W +: 2] !== b) begin
                        $display("ERROR cycle %0d: bank %0d hint line %h", cyc, b,
                                 pf_req_line_addr[b*LINE_W +: LINE_W]);
                        err_cnt = err_cnt + 1;
                    end
                    if (^pf_req_line_addr[b*LINE_W +: LINE_W] === 1'bx || ^pf_req_unique[b] === 1'bx) begin
                        $display("ERROR cycle %0d: X on bank %0d", cyc, b);
                        err_cnt = err_cnt + 1;
                    end
                    if (hint_n < 1024) begin
                        hint_cyc[hint_n]  = cyc;
                        hint_bank[hint_n] = b;
                        hint_line[hint_n] = pf_req_line_addr[b*LINE_W +: LINE_W];
                        hint_n = hint_n + 1;
                    end
                end
            end
            if (^pf_req_valid === 1'bx) begin
                $display("ERROR cycle %0d: X on pf_req_valid", cyc);
                err_cnt = err_cnt + 1;
            end
            ready_q <= pf_req_ready;
            fb_pipe[0] <= pf_req_valid;
            fb_pipe[1] <= fb_pipe[0];
            fb_pipe[2] <= fb_pipe[1];
            fb_pipe[3] <= fb_pipe[2];
            pf_fb_valid <= fb_pipe[3];
        end
    end
    task quiet;
        begin
            train_valid = 0; train_no_train = 0; train_miss = 0; train_pf_hit = 0;
            train_is_store = 0; evict_valid = 0;
        end
    endtask
    task record;
        input [PC_W-1:0] pc;
        input [ADDR_W-1:0] addr;
        input miss;
        output integer s1_cyc;
        begin
            @(negedge clk);
            quiet;
            train_valid[0] = 1'b1;
            train_pc[0 +: PC_W] = pc;
            train_addr[0 +: ADDR_W] = addr;
            train_miss[0] = miss;
            s1_cyc = cyc + 1;
            @(negedge clk);
            quiet;
        end
    endtask
    task evict;
        input [LINE_W-1:0] line;
        begin
            @(negedge clk);
            quiet;
            evict_valid[1] = 1'b1;
            evict_line_addr[1*LINE_W +: LINE_W] = line;
            @(negedge clk);
            quiet;
        end
    endtask
    task expect_hint;
        input integer from_idx;
        input integer t;
        input [LINE_W-1:0] line;
        input [255:0] name;
        integer h, found;
        begin
            found = 0;
            for (h = from_idx; h < hint_n; h = h + 1)
                if (hint_line[h] == line) begin
                    found = 1;
                    if (hint_cyc[h] - t != 3) begin
                        $display("ERROR %0s: hint %h %0d cycles after the record (want 3)",
                                 name, line, hint_cyc[h] - t + 0);
                        err_cnt = err_cnt + 1;
                    end
                    else $display("OK %0s: hint %h 3 cycles after the record", name, line);
                end
            if (!found) begin
                $display("ERROR %0s: no hint for line %h", name, line);
                err_cnt = err_cnt + 1;
            end
        end
    endtask
    integer t1, t2, t3, start;
    reg [ADDR_W-1:0] a;
    initial begin
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        if (!$value$plusargs("NREC=%d", nrec)) nrec = 20000;
        cyc = 0; err_cnt = 0; hint_n = 0;
        rst = 1; pf_enable = 1;
        quiet;
        train_pc = 0; train_addr = 0; evict_line_addr = 0;
        pf_fb_line_addr = 0; pf_fb_result = 0; pf_req_ready = {NB{1'b1}};
        repeat (4) @(posedge clk);
        rst = 0;
        a = 64'h0000_0012_3456_7100;
        record(64'h0000_0000_0080_0010, a, 1'b1, t1);
        repeat (20) @(posedge clk);
        record(64'h0000_0000_0080_0010, a + 128, 1'b1, t2);
        repeat (20) @(posedge clk);
        start = hint_n;
        record(64'h0000_0000_0080_0010, a + 256, 1'b1, t3);
        repeat (20) @(posedge clk);
        expect_hint(start, t3, (a + 512) >> 6, "L1 stride");
        a = 64'h0000_0034_5678_9400;
        record(64'h0000_0000_0090_0020, a, 1'b1, t1);
        repeat (20) @(posedge clk);
        record(64'h0000_0000_0090_0020, a + 64, 1'b1, t2);
        repeat (20) @(posedge clk);
        start = hint_n;
        record(64'h0000_0000_0090_0020, a + 128, 1'b1, t3);
        repeat (30) @(posedge clk);
        expect_hint(start, t3, (a + 192) >> 6, "L2 stream");
        expect_hint(start, t3, (a + 256) >> 6, "L2 stride");
        record(64'h0000_0000_00A0_0100, {8'd0, 45'h2468A, 5'd0, 6'd0}, 1'b1, t1);
        repeat (20) @(posedge clk);
        record(64'h0000_0000_00A0_0204, {8'd0, 45'h2468A, 5'd3, 6'd0}, 1'b1, t1);
        repeat (20) @(posedge clk);
        record(64'h0000_0000_00A0_0308, {8'd0, 45'h2468A, 5'd6, 6'd0}, 1'b1, t1);
        repeat (20) @(posedge clk);
        evict({8'd0, 45'h2468A, 5'd3});
        repeat (20) @(posedge clk);
        start = hint_n;
        record(64'h0000_0000_00A0_0100, {8'd0, 45'h2468B, 5'd0, 6'd0}, 1'b1, t3);
        repeat (30) @(posedge clk);
        expect_hint(start, t3, {8'd0, 45'h2468B, 5'd3}, "L3 SMS");
        for (n = 0; n < nrec; n = n + 1) begin
            @(negedge clk);
            quiet;
            pf_req_ready = $random(seed) | $random(seed);
            for (lane = 0; lane < NB; lane = lane + 1) begin
                if ((($random(seed) & 32'h7fffffff) % 3) == 0) begin
                    train_valid[lane] = 1'b1;
                    train_pc[lane*PC_W +: PC_W] = {48'd0, 12'h400 + ((($random(seed) & 32'h7fffffff) % 16) * 4), 4'd0};
                    train_addr[lane*ADDR_W +: ADDR_W] = {8'd0, 36'h000ABCDE, 8'h00 + (($random(seed) & 32'h7fffffff) % 8),
                                                         ($random(seed) & 32'hfff)};
                    train_is_store[lane] = (($random(seed) & 32'h7fffffff) % 5 == 0);
                    train_miss[lane] = (($random(seed) & 32'h7fffffff) % 2 == 0);
                    train_pf_hit[lane] = (($random(seed) & 32'h7fffffff) % 7 == 0);
                    train_no_train[lane] = (($random(seed) & 32'h7fffffff) % 12 == 0);
                end
                if ((($random(seed) & 32'h7fffffff) % 9) == 0) begin
                    evict_valid[lane] = 1'b1;
                    evict_line_addr[lane*LINE_W +: LINE_W] = {8'd0, 36'h000ABCDE, 8'h00 + (($random(seed) & 32'h7fffffff) % 8),
                                                              ($random(seed) & 32'h3f)};
                end
            end
            if (n == nrec / 2) pf_enable = 1'b0;
            if (n == nrec / 2 + 50) pf_enable = 1'b1;
        end
        @(negedge clk);
        quiet;
        repeat (100) @(posedge clk);
        $display("SUMMARY unit seed=%0d records=%0d hints=%0d errors=%0d", seed, nrec, hint_n, err_cnt);
        if (err_cnt == 0) $display("TEST PASSED");
        else $display("TEST FAILED");
        $finish;
    end
    initial begin
        #400000000;
        $display("ERROR: time-out");
        $display("TEST FAILED");
        $finish;
    end
endmodule
`default_nettype wire
