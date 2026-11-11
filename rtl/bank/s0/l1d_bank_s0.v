`ifndef L1D_BANK_S0_V
`define L1D_BANK_S0_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_bank_s0 #(
    `L1D_PARAMS,
    parameter BANK_ID = 0
) (
    clk, rst,
    arrival_request_0, arrival_request_1, arrival_request_2, arrival_request_3,
    arrival_packet_0, arrival_packet_1, arrival_packet_2, arrival_packet_3,
    arrival_pc_0, arrival_pc_1, arrival_pc_2, arrival_pc_3,
    drain_request, drain_packet, drain_pc,
    arrival_allocated_0, arrival_allocated_1, arrival_allocated_2, arrival_allocated_3, drain_allocated,
    tracker_free_count_q,
    lsu_response_fifo_free_0, lsu_response_fifo_free_1, lsu_response_fifo_free_2, lsu_response_fifo_free_3,
    lsu_response_fifo_free_next_0, lsu_response_fifo_free_next_1, lsu_response_fifo_free_next_2, lsu_response_fifo_free_next_3,
    snoop_request_valid, snoop_request_line_addr, snoop_request_invalidate, snoop_request_ready, snoop_response_fifo_free,
    prefetch_request_valid, prefetch_request_line_addr, prefetch_request_unique, prefetch_request_ready,
    refill_handover_busy,
    s1_valid, s1_kind, s1_req,
    s2_valid, s2_kind, s2_req, s2_hit, s2_sid, s2_line, s2_seat, s2_kill, s2_answered,
    act_valid, act_code, act_id, snp_act_valid, snp_act_code, snp_act_id,
    s2_train_sent, s2_seat_trained, s2_seat_pc,
    s3_amo_v,
    lock_valid, lock_snp, lock_line, ev_amor,
    tok_valid, tok_id, tok_line, mt_valid, mt_set, mt_way, mt_op,
    m_resp_valid, n_resp_valid,
    mshr_freed, vc_freed, nc_freed,
    any_gnt, g_set, gnt_refill, gnt_maint,
    r_valid, r_kind, r_seat, r_req, r_fast, r_mid, r_line, r_mway, r_mop, r_sinv, r_sid, r_deps,
    tracker_empty, miss_ok,
    vec_slot_available, vec_write_slot, vec_write_valid
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam [BANK_W-1:0]   BANK_C = BANK_ID;
    localparam [OFFSET_W-1:0] OFF0   = {OFFSET_W{1'b0}};
    localparam SET_IN_REQ  = REQ_ADDR_LSB + OFFSET_W + LA_SET_LSB;
    localparam LINE_IN_REQ = REQ_ADDR_LSB + OFFSET_W;
    localparam NE          = TRK_ENTRIES;
    localparam [RCNT_W:0]  CREDIT_TWO   = 2;
    localparam [RCNT_W:0]  CREDIT_THREE = 3;
    input  wire                        clk;
    input  wire                        rst;
    input  wire                        arrival_request_0;
    input  wire                        arrival_request_1;
    input  wire                        arrival_request_2;
    input  wire                        arrival_request_3;
    input  wire [REQ_W-1:0]            arrival_packet_0;
    input  wire [REQ_W-1:0]            arrival_packet_1;
    input  wire [REQ_W-1:0]            arrival_packet_2;
    input  wire [REQ_W-1:0]            arrival_packet_3;
    input  wire [PC_W-1:0]             arrival_pc_0;
    input  wire [PC_W-1:0]             arrival_pc_1;
    input  wire [PC_W-1:0]             arrival_pc_2;
    input  wire [PC_W-1:0]             arrival_pc_3;
    input  wire                        drain_request;
    input  wire [REQ_W-1:0]            drain_packet;
    input  wire [PC_W-1:0]             drain_pc;
    output wire                        arrival_allocated_0;
    output wire                        arrival_allocated_1;
    output wire                        arrival_allocated_2;
    output wire                        arrival_allocated_3;
    output wire                        drain_allocated;
    output wire [TRK_CNT_W-1:0]        tracker_free_count_q;
    input  wire [RCNT_W-1:0]           lsu_response_fifo_free_0;
    input  wire [RCNT_W-1:0]           lsu_response_fifo_free_1;
    input  wire [RCNT_W-1:0]           lsu_response_fifo_free_2;
    input  wire [RCNT_W-1:0]           lsu_response_fifo_free_3;
    input  wire [RCNT_W-1:0]           lsu_response_fifo_free_next_0;
    input  wire [RCNT_W-1:0]           lsu_response_fifo_free_next_1;
    input  wire [RCNT_W-1:0]           lsu_response_fifo_free_next_2;
    input  wire [RCNT_W-1:0]           lsu_response_fifo_free_next_3;
    input  wire                        snoop_request_valid;
    input  wire [LINE_ADDR_W-1:0]      snoop_request_line_addr;
    input  wire                        snoop_request_invalidate;
    output wire                        snoop_request_ready;
    input  wire [SNPR_CNT_W-1:0]       snoop_response_fifo_free;
    input  wire                        prefetch_request_valid;
    input  wire [LINE_ADDR_W-1:0]      prefetch_request_line_addr;
    input  wire                        prefetch_request_unique;
    output wire                        prefetch_request_ready;
    input  wire                        refill_handover_busy;
    input  wire                        s1_valid;
    input  wire [1:0]                  s1_kind;
    input  wire [REQ_W-1:0]            s1_req;
    input  wire                        s2_valid;
    input  wire [1:0]                  s2_kind;
    input  wire [REQ_W-1:0]            s2_req;
    input  wire                        s2_hit;
    input  wire [SNP_ID_W-1:0]         s2_sid;
    input  wire [LINE_ADDR_W-1:0]      s2_line;
    input  wire [SEAT_W-1:0]           s2_seat;
    input  wire                        s2_kill;
    input  wire                        s2_answered;
    input  wire                        act_valid;
    input  wire [2:0]                  act_code;
    input  wire [WID_W-1:0]            act_id;
    input  wire                        snp_act_valid;
    input  wire [1:0]                  snp_act_code;
    input  wire [WID_W-1:0]            snp_act_id;
    input  wire                        s2_train_sent;
    output wire                        s2_seat_trained;
    output wire [PC_W-1:0]             s2_seat_pc;
    input  wire                        s3_amo_v;
    input  wire                        lock_valid;
    input  wire                        lock_snp;
    input  wire [LINE_ADDR_W-1:0]      lock_line;
    input  wire                        ev_amor;
    input  wire                        tok_valid;
    input  wire [MSHR_ID_W-1:0]        tok_id;
    input  wire [LINE_ADDR_W-1:0]      tok_line;
    input  wire                        mt_valid;
    input  wire [INDEX_W-1:0]          mt_set;
    input  wire [WAY_W-1:0]            mt_way;
    input  wire                        mt_op;
    input  wire                        m_resp_valid;
    input  wire                        n_resp_valid;
    input  wire [MSHR_ENTRIES-1:0]     mshr_freed;
    input  wire [VC_SLOTS-1:0]         vc_freed;
    input  wire                        nc_freed;
    output wire                        any_gnt;
    output wire [INDEX_W-1:0]          g_set;
    output wire                        gnt_refill;
    output wire                        gnt_maint;
    output reg                         r_valid;
    output reg  [1:0]                  r_kind;
    output reg  [SEAT_W-1:0]           r_seat;
    output reg  [REQ_W-1:0]            r_req;
    output reg                         r_fast;
    output reg  [MSHR_ID_W-1:0]        r_mid;
    output reg  [LINE_ADDR_W-1:0]      r_line;
    output reg  [WAY_W-1:0]            r_mway;
    output reg                         r_mop;
    output reg                         r_sinv;
    output reg  [SNP_ID_W-1:0]         r_sid;
    output wire [TRK_ENTRIES-1:0]      r_deps;
    output wire                        tracker_empty;
    output wire                        miss_ok;
    input  wire                        vec_slot_available;
    input  wire [VEC_SLOT_W-1:0]       vec_write_slot;
    output wire                        vec_write_valid;
    reg                r_cpu_q;
    reg                r_pf_q;
    wire               s1_lsu;
    wire               s2_lsu;
    wire               s2_cpu;
    wire [PORT_W-1:0]  r_port;
    wire [PORT_W-1:0]  s1_port;
    wire               r_wr;
    wire               s1_wr;
    wire               s1_pf;
    assign s1_lsu  = s1_valid && (s1_kind == K_LSU);
    assign s2_lsu  = s2_valid && (s2_kind == K_LSU);
    assign s2_cpu  = s2_lsu && !s2_req[REQ_PF_BIT];
    assign s1_pf   = s1_req[REQ_PF_BIT];
    assign r_port  = r_req[REQ_PORT_LSB +: PORT_W];
    assign s1_port = s1_req[REQ_PORT_LSB +: PORT_W];
    assign r_wr    = r_req[REQ_RDWR_BIT];
    assign s1_wr   = s1_req[REQ_RDWR_BIT];
    wire [LSU_PORTS-1:0] arrival_request;
    wire [LSU_PORTS-1:0] lowest_req;
    wire                 any_pins_arrival;
    assign arrival_request = {arrival_request_3, arrival_request_2, arrival_request_1, arrival_request_0};
    assign lowest_req[0]   = arrival_request[0];
    assign lowest_req[1]   = arrival_request[1] & ~arrival_request[0];
    assign lowest_req[2]   = arrival_request[2] & ~arrival_request[1] & ~arrival_request[0];
    assign lowest_req[3]   = arrival_request[3] & ~arrival_request[2] & ~arrival_request[1] & ~arrival_request[0];
    assign any_pins_arrival = |arrival_request;
    reg  [REQ_W-1:0]   fresh_packet;
    wire [REQ_W-1:0]   arrival_packet_flat;
    assign arrival_packet_flat = {arrival_packet_3, arrival_packet_2, arrival_packet_1, arrival_packet_0};
    integer fp_port;
    always @* begin
        fresh_packet = {REQ_W{1'b0}};
        for (fp_port = 0; fp_port < LSU_PORTS; fp_port = fp_port + 1)
            fresh_packet = fresh_packet | ({REQ_W{lowest_req[fp_port]}} & arrival_packet_flat[fp_port*REQ_W +: REQ_W]);
    end
    wire [INDEX_W-1:0]     fresh_set;
    wire [LINE_ADDR_W-1:0] fresh_line;
    wire                   fresh_is_write;
    wire                   fresh_is_amo;
    assign fresh_set      = fresh_packet[SET_IN_REQ +: INDEX_W];
    assign fresh_line     = fresh_packet[LINE_IN_REQ +: LINE_ADDR_W];
    assign fresh_is_write = fresh_packet[REQ_RDWR_BIT];
    assign fresh_is_amo   = fresh_packet[REQ_AMO_BIT] & fresh_packet[REQ_SEQ_BIT];
    wire                   fresh_allowed_q;
    reg  [LSU_PORTS-1:0]   credit_q;
    wire                   fresh_issue;
    wire [LSU_PORTS-1:0]   fresh_port_onehot;
    wire [NE-1:0]          fresh_entry_onehot;
    wire                   tracker_any_pins;
    wire                   oldest_ready_valid;
    wire [NE-1:0]          oldest_ready_onehot;
    wire [INDEX_W-1:0]     oldest_ready_set;
    wire [LINE_ADDR_W-1:0] oldest_ready_line;
    wire [PORT_W-1:0]      oldest_ready_port;
    wire                   oldest_ready_is_write;
    wire                   oldest_ready_is_line_op;
    wire                   oldest_ready_is_amo;
    wire                   arrival_book_valid;
    wire [NE-1:0]          arrival_book_entry_onehot;
    wire [INDEX_W-1:0]     arrival_book_set;
    wire [LINE_ADDR_W-1:0] arrival_book_line;
    wire [PORT_W-1:0]      arrival_book_port;
    wire                   arrival_book_is_write;
    wire                   arrival_book_is_line_op;
    wire                   arrival_book_is_amo;
    wire [NE-1:0]          book_entry_onehot;
    wire [NE-1:0]          issue_entry_onehot;
    wire [NE*REQ_W-1:0]    entry_packet_flat;
    wire [NE*PC_W-1:0]     entry_pc_flat;
    wire [NE-1:0]          entry_valid_q;
    l1d_req_tracker #(`L1D_PARAMS_PASS, .BANK_ID(BANK_ID)) u_tracker (
        .clk                       (clk),
        .rst                       (rst),
        .arrival_request_0         (arrival_request_0),
        .arrival_request_1         (arrival_request_1),
        .arrival_request_2         (arrival_request_2),
        .arrival_request_3         (arrival_request_3),
        .arrival_packet_0          (arrival_packet_0),
        .arrival_packet_1          (arrival_packet_1),
        .arrival_packet_2          (arrival_packet_2),
        .arrival_packet_3          (arrival_packet_3),
        .arrival_pc_0              (arrival_pc_0),
        .arrival_pc_1              (arrival_pc_1),
        .arrival_pc_2              (arrival_pc_2),
        .arrival_pc_3              (arrival_pc_3),
        .drain_request             (drain_request),
        .drain_packet              (drain_packet),
        .drain_pc                  (drain_pc),
        .vec_slot_available        (vec_slot_available),
        .vec_write_slot            (vec_write_slot),
        .vec_write_valid           (vec_write_valid),
        .fresh_allowed_q           (fresh_allowed_q),
        .credit_q_0                (credit_q[0]),
        .credit_q_1                (credit_q[1]),
        .credit_q_2                (credit_q[2]),
        .credit_q_3                (credit_q[3]),
        .fresh_issue               (fresh_issue),
        .fresh_port_onehot         (fresh_port_onehot),
        .fresh_entry_onehot        (fresh_entry_onehot),
        .any_pins_arrival          (tracker_any_pins),
        .arrival_allocated_0       (arrival_allocated_0),
        .arrival_allocated_1       (arrival_allocated_1),
        .arrival_allocated_2       (arrival_allocated_2),
        .arrival_allocated_3       (arrival_allocated_3),
        .drain_allocated           (drain_allocated),
        .oldest_ready_valid        (oldest_ready_valid),
        .oldest_ready_onehot       (oldest_ready_onehot),
        .oldest_ready_set          (oldest_ready_set),
        .oldest_ready_line         (oldest_ready_line),
        .oldest_ready_port         (oldest_ready_port),
        .oldest_ready_is_write     (oldest_ready_is_write),
        .oldest_ready_is_line_op   (oldest_ready_is_line_op),
        .oldest_ready_is_amo       (oldest_ready_is_amo),
        .arrival_book_valid        (arrival_book_valid),
        .arrival_book_entry_onehot (arrival_book_entry_onehot),
        .arrival_book_set          (arrival_book_set),
        .arrival_book_line         (arrival_book_line),
        .arrival_book_port         (arrival_book_port),
        .arrival_book_is_write     (arrival_book_is_write),
        .arrival_book_is_line_op   (arrival_book_is_line_op),
        .arrival_book_is_amo       (arrival_book_is_amo),
        .book_entry_onehot         (book_entry_onehot),
        .issue_entry_onehot        (issue_entry_onehot),
        .entry_packet_flat         (entry_packet_flat),
        .entry_pc_flat             (entry_pc_flat),
        .s2_cpu_valid              (s2_cpu),
        .s2_seat                   (s2_seat),
        .s2_kill                   (s2_kill),
        .s2_answered               (s2_answered),
        .act_valid                 (act_valid),
        .act_code                  (act_code),
        .act_id                    (act_id),
        .s2_train_sent             (s2_train_sent),
        .s2_seat_trained           (s2_seat_trained),
        .s2_seat_pc                (s2_seat_pc),
        .mshr_freed                (mshr_freed),
        .vc_freed                  (vc_freed),
        .nc_freed                  (nc_freed),
        .free_count_q              (tracker_free_count_q),
        .entry_valid_q             (entry_valid_q),
        .tracker_empty             (tracker_empty),
        .r_seat                    (r_seat),
        .r_seat_deps               (r_deps)
    );
    wire [LSU_PORTS*RCNT_W-1:0] free_now_flat;
    wire [LSU_PORTS*RCNT_W-1:0] free_next_flat;
    assign free_now_flat  = {lsu_response_fifo_free_3, lsu_response_fifo_free_2, lsu_response_fifo_free_1, lsu_response_fifo_free_0};
    assign free_next_flat = {lsu_response_fifo_free_next_3, lsu_response_fifo_free_next_2, lsu_response_fifo_free_next_1, lsu_response_fifo_free_next_0};
    wire                 book_entry_issue;
    reg  [PORT_W-1:0]    book_port_q;
    reg                  book_is_write_q;
    reg                  book_is_amo_q;
    reg  [LSU_PORTS-1:0] r_is_port;
    reg  [LSU_PORTS-1:0] s1_is_port;
    reg  [LSU_PORTS-1:0] issue_is_port;
    reg  [LSU_PORTS-1:0] credit_next;
    reg  [LSU_PORTS-1:0] credit_book_next;
    reg  [LSU_PORTS-1:0] port_miss_ok;
    reg  [RCNT_W:0]      promised_next;
    integer cr_port;
    always @* begin
        for (cr_port = 0; cr_port < LSU_PORTS; cr_port = cr_port + 1) begin
            r_is_port[cr_port]     = r_cpu_q && (r_port == cr_port);
            s1_is_port[cr_port]    = s1_lsu && !s1_pf && (s1_port == cr_port);
            issue_is_port[cr_port] = (book_entry_issue && (book_port_q == cr_port)) || (fresh_issue && fresh_port_onehot[cr_port]);
            promised_next          = {{RCNT_W{1'b0}}, r_is_port[cr_port]} + {{RCNT_W{1'b0}}, issue_is_port[cr_port]} + CREDIT_TWO;
            credit_next[cr_port]   = ({1'b0, free_next_flat[cr_port*RCNT_W +: RCNT_W]} >= promised_next);
            credit_book_next[cr_port] = ({1'b0, free_next_flat[cr_port*RCNT_W +: RCNT_W]} >=
                                         ({{RCNT_W{1'b0}}, r_is_port[cr_port]} + CREDIT_THREE));
            port_miss_ok[cr_port]  = ({1'b0, free_now_flat[cr_port*RCNT_W +: RCNT_W]} >
                                      ({{RCNT_W{1'b0}}, r_is_port[cr_port]} + {{RCNT_W{1'b0}}, s1_is_port[cr_port]}));
        end
    end
    assign miss_ok = &port_miss_ok;
    always @(posedge clk) begin : credit_proc
        if (rst) credit_q <= {LSU_PORTS{1'b1}};
        else     credit_q <= credit_next;
    end
    wire entry_credit_ok;
    wire arrival_credit_ok;
    assign entry_credit_ok   = credit_book_next[oldest_ready_port];
    assign arrival_credit_ok = credit_book_next[arrival_book_port];
    wire                   sn_sel_valid;
    wire                   sn_sel_inv;
    wire [SNP_ID_W-1:0]    sn_sel_id;
    wire [LINE_ADDR_W-1:0] sn_sel_line;
    wire                   gnt_snoop;
    wire                   snp_credit;
    wire                   r_amor_any;
    wire                   s1_amor_any;
    wire                   s2_amor_any;
    wire                   amor_busy;
    assign snp_credit  = (snoop_response_fifo_free != {SNPR_CNT_W{1'b0}});
    assign r_amor_any  = r_cpu_q && r_req[REQ_AMO_BIT]  && r_req[REQ_SEQ_BIT]  && !r_req[REQ_RDWR_BIT];
    assign s1_amor_any = s1_lsu  && s1_req[REQ_AMO_BIT] && s1_req[REQ_SEQ_BIT] && !s1_req[REQ_RDWR_BIT];
    assign s2_amor_any = s2_lsu  && s2_req[REQ_AMO_BIT] && s2_req[REQ_SEQ_BIT] && !s2_req[REQ_RDWR_BIT];
    assign amor_busy   = r_amor_any || s1_amor_any || s2_amor_any;
    wire amo_hold_snoops;
    assign amo_hold_snoops = amor_busy || refill_handover_busy;
    l1d_snoop_buf #(`L1D_PARAMS_PASS) u_snp (
        .clk                  (clk),
        .rst                  (rst),
        .new_snoop_valid      (snoop_request_valid),
        .new_snoop_line_addr  (snoop_request_line_addr),
        .new_snoop_invalidate (snoop_request_invalidate),
        .new_snoop_ready      (snoop_request_ready),
        .amo_lock_snoop_hold  (lock_snp),
        .amo_lock_line        (lock_line),
        .amo_read_in_pipeline (amo_hold_snoops),
        .amo_lock_set_valid   (ev_amor),
        .amo_lock_set_line    (s2_line),
        .offer_valid          (sn_sel_valid),
        .offer_entry_id       (sn_sel_id),
        .offer_line_addr      (sn_sel_line),
        .offer_invalidate     (sn_sel_inv),
        .offer_granted        (gnt_snoop),
        .s2_action_valid      (snp_act_valid),
        .s2_action_entry_id   (s2_sid),
        .s2_action_code       (snp_act_code),
        .s2_action_wait_id    (snp_act_id),
        .mshr_entry_freed     (mshr_freed),
        .victim_slot_freed    (vc_freed),
        .buffer_empty         ()
    );
    reg                    pf_valid_q;
    reg  [LINE_ADDR_W-1:0] pf_line_q;
    reg                    pf_unique_q;
    reg                    pf_booked_q;
    wire                   pf_issue;
    wire                   pf_take_new;
    assign pf_take_new            = prefetch_request_valid && !pf_booked_q && (HAS_PF != 0);
    assign prefetch_request_ready = !pf_booked_q;
    wire [REQ_W-1:0]       pf_packet;
    assign pf_packet = {pf_unique_q, 1'b1, 1'b0, {PORT_W{1'b0}}, {AMOOP_W{1'b0}}, 1'b0, 1'b0, 1'b0, 1'b1,
                        {MEM_SIZE_BITS{1'b0}}, {MASTER_ID_BITS{1'b0}}, {IDX_BITS{1'b0}}, {pf_line_q, OFF0}, {WRITE_DATA_WIDTH{1'b0}}};
    wire book_valid_q;
    wire [BOOK_KIND_W-1:0] book_kind_q;
    wire book_now_snoop, book_now_refill, book_now_maint;
    wire book_now_entry, book_now_arrival, book_now_prefetch;
    wire amo_issued_now;
    wire store_in_flight_next;
    wire s2_amo_served;
    assign amo_issued_now       = (book_entry_issue && book_is_amo_q) || (fresh_issue && fresh_is_amo);
    assign s2_amo_served        = s2_cpu && s2_hit && !s2_kill && s2_req[REQ_AMO_BIT] && s2_req[REQ_SEQ_BIT];
    assign store_in_flight_next = (book_entry_issue && book_is_write_q) || (fresh_issue && fresh_is_write) ||
                                  (r_cpu_q && r_wr) || (s1_lsu && !s1_pf && s1_wr) || s2_amo_served;
    l1d_book_select #(.REFILL_SKIP(REFILL_SKIP + 1), .SNP_STARVE(SNP_STARVE), .BOOK_KIND_W(BOOK_KIND_W)) u_book (
        .clk                  (clk),
        .rst                  (rst),
        .snoop_offer_valid    (sn_sel_valid),
        .snoop_credit_ok      (snp_credit),
        .refill_token_valid   (tok_valid),
        .maint_token_valid    (mt_valid),
        .entry_ready_valid    (oldest_ready_valid),
        .entry_credit_ok      (entry_credit_ok),
        .arrival_ready_valid  (arrival_book_valid),
        .arrival_credit_ok    (arrival_credit_ok),
        .prefetch_valid       (pf_valid_q),
        .amo_issued_now       (amo_issued_now),
        .store_in_flight_next (store_in_flight_next),
        .book_valid_q         (book_valid_q),
        .book_kind_q          (book_kind_q),
        .fresh_allowed_q      (fresh_allowed_q),
        .book_now_snoop       (book_now_snoop),
        .book_now_refill      (book_now_refill),
        .book_now_maint       (book_now_maint),
        .book_now_entry       (book_now_entry),
        .book_now_arrival     (book_now_arrival),
        .book_now_prefetch    (book_now_prefetch)
    );
    assign book_entry_onehot = ({NE{book_now_entry}} & oldest_ready_onehot) | ({NE{book_now_arrival}} & arrival_book_entry_onehot);
    wire [LINE_ADDR_W-1:0] mt_line;
    assign mt_line = {{TAG_W{1'b0}}, mt_set, BANK_C};
    reg  [LINE_ADDR_W-1:0] book_line_q;
    reg  [INDEX_W-1:0]     book_set_q;
    reg  [NE-1:0]          book_entry_onehot_q;
    reg  [NE-1:0]          book_entry_sel_q [0:3];
    reg  [SNP_ID_W-1:0]    book_sid_q;
    reg                    book_sinv_q;
    reg  [MSHR_ID_W-1:0]   book_mid_q;
    reg  [WAY_W-1:0]       book_mway_q;
    reg                    book_mop_q;
    reg  [LINE_ADDR_W-1:0] book_line_next;
    reg  [PORT_W-1:0]      book_port_next;
    reg                    book_is_write_next;
    reg                    book_is_amo_next;
    always @* begin
        book_line_next     = {LINE_ADDR_W{1'b0}};
        book_port_next     = {PORT_W{1'b0}};
        book_is_write_next = 1'b0;
        book_is_amo_next   = 1'b0;
        if (book_now_snoop)  book_line_next = sn_sel_line;
        if (book_now_refill) book_line_next = tok_line;
        if (book_now_maint)  book_line_next = mt_line;
        if (book_now_prefetch) book_line_next = pf_line_q;
        if (book_now_entry) begin
            book_line_next     = oldest_ready_line;
            book_port_next     = oldest_ready_port;
            book_is_write_next = oldest_ready_is_write;
            book_is_amo_next   = oldest_ready_is_amo;
        end
        if (book_now_arrival) begin
            book_line_next     = arrival_book_line;
            book_port_next     = arrival_book_port;
            book_is_write_next = arrival_book_is_write;
            book_is_amo_next   = arrival_book_is_amo;
        end
    end
    integer cp_idx;
    always @(posedge clk) begin : book_fields_proc
        if (rst) begin
            book_entry_onehot_q <= {NE{1'b0}};
            for (cp_idx = 0; cp_idx < 4; cp_idx = cp_idx + 1) book_entry_sel_q[cp_idx] <= {NE{1'b0}};
            pf_booked_q <= 1'b0;
        end else begin
            book_line_q         <= book_line_next;
            book_set_q          <= book_line_next[LA_SET_LSB +: INDEX_W];
            book_port_q         <= book_port_next;
            book_is_write_q     <= book_is_write_next;
            book_is_amo_q       <= book_is_amo_next;
            book_entry_onehot_q <= book_entry_onehot;
            for (cp_idx = 0; cp_idx < 4; cp_idx = cp_idx + 1) book_entry_sel_q[cp_idx] <= book_entry_onehot;
            book_sid_q          <= sn_sel_id;
            book_sinv_q         <= sn_sel_inv;
            book_mid_q          <= tok_id;
            book_mway_q         <= mt_way;
            book_mop_q          <= mt_op;
            pf_booked_q         <= book_now_prefetch;
        end
    end
    wire snoop_issue;
    wire refill_issue;
    wire maint_issue;
    wire book_issue;
    assign snoop_issue      = book_valid_q && book_kind_q[BOOK_SNOOP_B]  && sn_sel_valid && (sn_sel_id == book_sid_q);
    assign refill_issue     = book_valid_q && book_kind_q[BOOK_REFILL_B] && tok_valid && (tok_id == book_mid_q);
    assign maint_issue      = book_valid_q && book_kind_q[BOOK_MAINT_B]  && mt_valid;
    assign book_entry_issue = book_valid_q && book_kind_q[BOOK_ENTRY_B];
    assign pf_issue         = book_valid_q && book_kind_q[BOOK_PF_B];
    assign book_issue       = snoop_issue || refill_issue || maint_issue || book_entry_issue || pf_issue;
    assign gnt_snoop          = snoop_issue;
    assign gnt_refill         = refill_issue;
    assign gnt_maint          = maint_issue;
    assign issue_entry_onehot = {NE{book_entry_issue}} & book_entry_onehot_q;
    always @(posedge clk) begin : pf_proc
        if (rst) begin
            pf_valid_q <= 1'b0;
        end else begin
            if (pf_take_new)      pf_valid_q <= 1'b1;
            else if (pf_issue)    pf_valid_q <= 1'b0;
            if (pf_take_new) begin
                pf_line_q   <= prefetch_request_line_addr;
                pf_unique_q <= prefetch_request_unique;
            end
        end
    end
    assign g_set   = book_valid_q ? book_set_q : fresh_set;
    assign any_gnt = book_valid_q || any_pins_arrival;
    reg  [REQ_W-1:0] booked_entry_packet;
    integer be_entry;
    integer be_group;
    localparam GROUP_W = (REQ_W + 3) / 4;
    always @* begin
        booked_entry_packet = {REQ_W{1'b0}};
        for (be_entry = 0; be_entry < NE; be_entry = be_entry + 1)
            for (be_group = 0; be_group < 4; be_group = be_group + 1)
                if (be_group * GROUP_W < REQ_W)
                    booked_entry_packet[be_group*GROUP_W +: GROUP_W] = booked_entry_packet[be_group*GROUP_W +: GROUP_W] |
                        ({GROUP_W{book_entry_sel_q[be_group][be_entry]}} & entry_packet_flat[be_entry*REQ_W + be_group*GROUP_W +: GROUP_W]);
    end
    wire [REQ_W-1:0] booked_packet;
    assign booked_packet = book_kind_q[BOOK_PF_B] ? pf_packet : booked_entry_packet;
    wire [1:0] booked_kind;
    assign booked_kind = book_kind_q[BOOK_SNOOP_B]  ? K_SNOOP :
                         book_kind_q[BOOK_REFILL_B] ? K_REFILL :
                         book_kind_q[BOOK_MAINT_B]  ? K_MAINT : K_LSU;
    reg  [SEAT_W-1:0] booked_seat;
    reg  [SEAT_W-1:0] fresh_seat;
    integer en_idx;
    always @* begin
        booked_seat = {SEAT_W{1'b0}};
        fresh_seat  = {SEAT_W{1'b0}};
        for (en_idx = 0; en_idx < NE; en_idx = en_idx + 1) begin
            if (book_entry_onehot_q[en_idx]) booked_seat = booked_seat | en_idx[SEAT_W-1:0];
            if (fresh_entry_onehot[en_idx])  fresh_seat  = fresh_seat  | en_idx[SEAT_W-1:0];
        end
    end
    always @(posedge clk) begin : g_to_r_proc
        if (rst) begin
            r_valid <= 1'b0;
            r_cpu_q <= 1'b0;
            r_pf_q  <= 1'b0;
            r_fast  <= 1'b0;
        end else begin
            r_valid <= book_issue || fresh_issue;
            r_cpu_q <= book_entry_issue || fresh_issue;
            r_pf_q  <= pf_issue;
            r_fast  <= fresh_issue;
            r_kind  <= book_valid_q ? booked_kind : K_LSU;
            r_req   <= book_valid_q ? booked_packet : fresh_packet;
            r_line  <= book_valid_q ? book_line_q : fresh_line;
            r_seat  <= book_valid_q ? booked_seat : fresh_seat;
            r_mid   <= book_mid_q;
            r_mway  <= book_mway_q;
            r_mop   <= book_mop_q;
            r_sinv  <= book_sinv_q;
            r_sid   <= book_sid_q;
        end
    end
`ifndef SYNTHESIS
    reg [INDEX_W-1:0] g_set_q;
    always @(posedge clk) begin
        g_set_q <= g_set;
        if (!rst) begin
            if (r_valid && (r_line[LA_SET_LSB +: INDEX_W] != g_set_q))
                $display("[%0t] L1D B%0d S0 ADDR LANE ERROR: the op in R has set %0d but the SRAMs read set %0d", $time, BANK_ID,
                         r_line[LA_SET_LSB +: INDEX_W], g_set_q);
            if (fresh_issue && book_valid_q)
                $display("[%0t] L1D B%0d S0 ERROR: fresh issue while an operation is booked", $time, BANK_ID);
            if (book_valid_q && !book_issue)
                $display("[%0t] L1D B%0d S0 NOTE: booked %b cancelled (source offer changed): bubble", $time, BANK_ID, book_kind_q);
        end
    end
`endif
`ifdef L1D_DEBUG
    always @(posedge clk) begin
        if (!rst) begin
            if (snoop_issue)
                $display("[%0t] L1D B%0d S0 ISSUE snoop %s line=%h", $time, BANK_ID, book_sinv_q ? "INV" : "READ", {book_line_q, OFF0});
            else if (refill_issue)
                $display("[%0t] L1D B%0d S0 ISSUE refill token  mshr=%0d line=%h", $time, BANK_ID, book_mid_q, {book_line_q, OFF0});
            else if (maint_issue)
                $display("[%0t] L1D B%0d S0 ISSUE %s token  set=%0d way=%0d", $time, BANK_ID,
                         (book_mop_q == MAINT_FLUSH) ? "flush" : "clean", book_set_q, book_mway_q);
            else if (book_entry_issue)
                $display("[%0t] L1D B%0d S0 ISSUE BOOKED entry %0d port %0d idx=%0d %s addr=%h", $time, BANK_ID, booked_seat,
                         booked_entry_packet[REQ_PORT_LSB +: PORT_W], booked_entry_packet[REQ_IDX_LSB +: IDX_BITS],
                         (booked_entry_packet[REQ_RDWR_BIT] ? "ST" : "LD"), booked_entry_packet[REQ_ADDR_LSB +: ADDR_W]);
            else if (pf_issue)
                $display("[%0t] L1D B%0d S0 ISSUE PREFETCH line=%h unique=%b", $time, BANK_ID, {pf_line_q, OFF0}, pf_unique_q);
            else if (fresh_issue)
                $display("[%0t] L1D B%0d S0 ISSUE FRESH entry %0d port %0d idx=%0d %s addr=%h", $time, BANK_ID, fresh_seat,
                         fresh_packet[REQ_PORT_LSB +: PORT_W], fresh_packet[REQ_IDX_LSB +: IDX_BITS],
                         (fresh_packet[REQ_RDWR_BIT] ? "ST" : "LD"), fresh_packet[REQ_ADDR_LSB +: ADDR_W]);
        end
    end
`endif
endmodule
`default_nettype wire
`endif
