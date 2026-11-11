`ifndef L1D_REQ_TRACKER_V
`define L1D_REQ_TRACKER_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_req_tracker #(
    `L1D_PARAMS,
    parameter BANK_ID = 0
) (
    clk, rst, arrival_request_0, arrival_request_1, arrival_request_2, arrival_request_3,
    arrival_packet_0, arrival_packet_1, arrival_packet_2, arrival_packet_3, arrival_pc_0, arrival_pc_1,
    arrival_pc_2, arrival_pc_3, drain_request, drain_packet, drain_pc, vec_slot_available,
    vec_write_slot, vec_write_valid, fresh_allowed_q, credit_q_0, credit_q_1, credit_q_2,
    credit_q_3, fresh_issue, fresh_port_onehot, fresh_entry_onehot, any_pins_arrival, arrival_allocated_0,
    arrival_allocated_1, arrival_allocated_2, arrival_allocated_3, drain_allocated, oldest_ready_valid, oldest_ready_onehot,
    oldest_ready_set, oldest_ready_line, oldest_ready_port, oldest_ready_is_write, oldest_ready_is_line_op, oldest_ready_is_amo,
    arrival_book_valid, arrival_book_entry_onehot, arrival_book_set, arrival_book_line, arrival_book_port, arrival_book_is_write,
    arrival_book_is_line_op, arrival_book_is_amo, book_entry_onehot, issue_entry_onehot, entry_packet_flat, entry_pc_flat,
    s2_cpu_valid, s2_seat, s2_kill, s2_answered, act_valid, act_code,
    act_id, s2_train_sent, s2_seat_trained, s2_seat_pc, mshr_freed, vc_freed,
    nc_freed, free_count_q, entry_valid_q, tracker_empty,
    r_seat, r_seat_deps
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    input  wire clk;
    input  wire rst;
    input  wire arrival_request_0;
    input  wire arrival_request_1;
    input  wire arrival_request_2;
    input  wire arrival_request_3;
    input  wire [REQ_W-1:0]  arrival_packet_0;
    input  wire [REQ_W-1:0]  arrival_packet_1;
    input  wire [REQ_W-1:0]  arrival_packet_2;
    input  wire [REQ_W-1:0]  arrival_packet_3;
    input  wire [PC_W-1:0]             arrival_pc_0;
    input  wire [PC_W-1:0]             arrival_pc_1;
    input  wire [PC_W-1:0]             arrival_pc_2;
    input  wire [PC_W-1:0]             arrival_pc_3;
    input  wire drain_request;
    input  wire [REQ_W-1:0]  drain_packet;
    input  wire [PC_W-1:0]             drain_pc;
    input  wire vec_slot_available;
    input  wire [VEC_SLOT_W-1:0] vec_write_slot;
    output wire vec_write_valid;
    input  wire fresh_allowed_q;
    input  wire credit_q_0;
    input  wire credit_q_1;
    input  wire credit_q_2;
    input  wire credit_q_3;
    output wire fresh_issue;
    output wire [3:0]                  fresh_port_onehot;
    output wire [TRK_ENTRIES-1:0]      fresh_entry_onehot;
    output wire any_pins_arrival;
    output wire arrival_allocated_0;
    output wire arrival_allocated_1;
    output wire arrival_allocated_2;
    output wire arrival_allocated_3;
    output wire drain_allocated;
    output wire oldest_ready_valid;
    output wire [TRK_ENTRIES-1:0]      oldest_ready_onehot;
    output wire [INDEX_W-1:0] oldest_ready_set;
    output wire [LINE_ADDR_W-1:0] oldest_ready_line;
    output wire [PORT_W-1:0] oldest_ready_port;
    output wire oldest_ready_is_write;
    output wire oldest_ready_is_line_op;
    output wire oldest_ready_is_amo;
    output wire arrival_book_valid;
    output wire [TRK_ENTRIES-1:0]      arrival_book_entry_onehot;
    output wire [INDEX_W-1:0] arrival_book_set;
    output wire [LINE_ADDR_W-1:0] arrival_book_line;
    output wire [PORT_W-1:0] arrival_book_port;
    output wire arrival_book_is_write;
    output wire arrival_book_is_line_op;
    output wire arrival_book_is_amo;
    input  wire [TRK_ENTRIES-1:0]      book_entry_onehot;
    input  wire [TRK_ENTRIES-1:0]      issue_entry_onehot;
    output wire [TRK_ENTRIES*REQ_W-1:0] entry_packet_flat;
    output wire [TRK_ENTRIES*PC_W-1:0] entry_pc_flat;
    input  wire s2_cpu_valid;
    input  wire [SEAT_W-1:0] s2_seat;
    input  wire s2_kill;
    input  wire s2_answered;
    input  wire act_valid;
    input  wire [2:0]                  act_code;
    input  wire [WID_W-1:0]  act_id;
    input  wire s2_train_sent;
    output wire s2_seat_trained;
    output wire [PC_W-1:0]             s2_seat_pc;
    input  wire [MSHR_ENTRIES-1:0]     mshr_freed;
    input  wire [VC_SLOTS-1:0]         vc_freed;
    input  wire nc_freed;
    input  wire [SEAT_W-1:0] r_seat;
    output wire [TRK_ENTRIES-1:0] r_seat_deps;
    output reg  [TRK_CNT_W-1:0] free_count_q;
    output wire [TRK_ENTRIES-1:0]      entry_valid_q;
    output wire tracker_empty;
    localparam NE          = TRK_ENTRIES;
    localparam NS          = LSU_PORTS + 1;
    localparam RANK_W      = 3;
    localparam NA          = (TRK_ALLOC_MAX < NS) ? TRK_ALLOC_MAX : NS;
    localparam SET_IN_REQ  = REQ_ADDR_LSB + OFFSET_W + LA_SET_LSB;
    localparam LINE_IN_REQ = REQ_ADDR_LSB + OFFSET_W;
    localparam [TRK_CNT_W-1:0] NE_C = NE;
    localparam [REQ_W-1:0] SLOT_MASK = {{(REQ_W-VEC_SLOT_W){1'b0}}, {VEC_SLOT_W{1'b1}}} << REQ_DATA_LSB;
    reg  [NE-1:0]           valid_q;
    reg  [TRK_STATE_W-1:0]  state_q [0:NE-1];
    reg  [REQ_W-1:0]        packet_q [0:NE-1];
    reg  [PC_W-1:0]         pc_q [0:NE-1];
    reg  [INDEX_W-1:0]      set_q [0:NE-1];
    reg  [NE-1:0]           write_q;
    reg  [NE-1:0]           deps_q [0:NE-1];
    reg  [MSHR_ENTRIES-1:0] wait_mshr_q [0:NE-1];
    reg  [VC_SLOTS-1:0]     wait_vc_q [0:NE-1];
    reg  [NE-1:0]           wait_nc_q;
    reg  [NE-1:0]           trained_q;
    wire [NS-1:0]       src_valid;
    wire [NS*REQ_W-1:0] src_packet;
    wire [NS*PC_W-1:0]  src_pc;
    wire [NS-1:0]       src_write;
    wire [NS-1:0]       src_line_op;
    wire [NS-1:0]       src_line_store;
    wire [NS-1:0]       src_place_ok;
    wire [NS-1:0]       eligible;
    wire [NS*INDEX_W-1:0] src_set;
    assign src_valid  = {drain_request, arrival_request_3, arrival_request_2, arrival_request_1, arrival_request_0};
    assign src_packet = {drain_packet, arrival_packet_3, arrival_packet_2, arrival_packet_1, arrival_packet_0};
    assign src_pc     = {drain_pc, arrival_pc_3, arrival_pc_2, arrival_pc_1, arrival_pc_0};
    genvar src_idx;
    generate
        for (src_idx = 0; src_idx < NS; src_idx = src_idx + 1) begin : g_src
            assign src_write[src_idx]      = src_packet[src_idx*REQ_W + REQ_RDWR_BIT];
            assign src_line_op[src_idx]    = src_packet[src_idx*REQ_W + REQ_LINE_BIT];
            assign src_line_store[src_idx] = src_line_op[src_idx] & src_write[src_idx];
            assign src_place_ok[src_idx]   = !src_line_store[src_idx] | vec_slot_available;
            assign eligible[src_idx]       = src_valid[src_idx] & src_place_ok[src_idx];
            assign src_set[src_idx*INDEX_W +: INDEX_W] = src_packet[src_idx*REQ_W + SET_IN_REQ +: INDEX_W];
        end
    endgenerate
    assign any_pins_arrival = |src_valid[LSU_PORTS-1:0];
    reg  [RANK_W-1:0] rank [0:NS-1];
    integer rank_src;
    integer rank_lower;
    always @* begin
        for (rank_src = 0; rank_src < NS; rank_src = rank_src + 1) begin
            rank[rank_src] = {RANK_W{1'b0}};
            for (rank_lower = 0; rank_lower < rank_src; rank_lower = rank_lower + 1)
                rank[rank_src] = rank[rank_src] + {{(RANK_W-1){1'b0}}, eligible[rank_lower]};
        end
    end
    wire [NS-1:0] alloc;
    genvar al_idx;
    generate
        for (al_idx = 0; al_idx < NS; al_idx = al_idx + 1) begin : g_alloc
            wire rank_in_room;
            wire rank_in_max;
            assign rank_in_room = ({{(TRK_CNT_W-RANK_W){1'b0}}, rank[al_idx]} < free_count_q);
            assign rank_in_max  = (rank[al_idx] < NA);
            assign alloc[al_idx] = eligible[al_idx] & rank_in_room & rank_in_max;
        end
    endgenerate
    assign arrival_allocated_0 = alloc[0];
    assign arrival_allocated_1 = alloc[1];
    assign arrival_allocated_2 = alloc[2];
    assign arrival_allocated_3 = alloc[3];
    assign drain_allocated     = alloc[LSU_PORTS];
    assign vec_write_valid     = |(alloc & src_line_store);
    wire [NA*NE-1:0] free_pick;
    generate
        if (NA <= 2) begin : g_pick_chain
            wire [NE-1:0] free_now;
            wire [NE-1:0] first_free;
            wire [NE-1:0] rest_free;
            wire [NE-1:0] second_free;
            assign free_now = ~valid_q;
            genvar ch_idx;
            for (ch_idx = 0; ch_idx < NE; ch_idx = ch_idx + 1) begin : g_chain
                if (ch_idx == 0) begin : g_first
                    assign first_free[ch_idx]  = free_now[ch_idx];
                    assign second_free[ch_idx] = 1'b0;
                end else begin : g_rest
                    assign first_free[ch_idx]  = free_now[ch_idx] & ~|free_now[ch_idx-1:0];
                    assign second_free[ch_idx] = rest_free[ch_idx] & ~|rest_free[ch_idx-1:0];
                end
            end
            assign rest_free = free_now & ~first_free;
            assign free_pick[0 +: NE] = first_free;
            if (NA == 2) begin : g_two
                assign free_pick[NE +: NE] = second_free;
            end
        end else begin : g_pick_count
            reg [RANK_W-1:0] free_below [0:NE-1];
            integer fb_entry;
            integer fb_lower;
            always @* begin
                for (fb_entry = 0; fb_entry < NE; fb_entry = fb_entry + 1) begin
                    free_below[fb_entry] = {RANK_W{1'b0}};
                    for (fb_lower = 0; fb_lower < fb_entry; fb_lower = fb_lower + 1)
                        free_below[fb_entry] = free_below[fb_entry] + {{(RANK_W-1){1'b0}}, ~valid_q[fb_lower]};
                end
            end
            genvar pk_k, pk_e;
            for (pk_k = 0; pk_k < NA; pk_k = pk_k + 1) begin : g_pick_k
                for (pk_e = 0; pk_e < NE; pk_e = pk_e + 1) begin : g_pick_e
                    assign free_pick[pk_k*NE + pk_e] = ~valid_q[pk_e] & (free_below[pk_e] == pk_k);
                end
            end
        end
    endgenerate
    reg  [NE-1:0] src_entry [0:NS-1];
    reg  [NS-1:0] data_sel [0:NE-1];
    reg  [NE-1:0] alloc_en;
    reg  [NA*NE-1:0] age_groups;
    integer se_src;
    integer se_rank;
    integer se_entry;
    always @* begin
        for (se_src = 0; se_src < NS; se_src = se_src + 1) begin
            src_entry[se_src] = {NE{1'b0}};
            for (se_rank = 0; se_rank < NA; se_rank = se_rank + 1)
                if (rank[se_src] == se_rank)
                    src_entry[se_src] = src_entry[se_src] | free_pick[se_rank*NE +: NE];
        end
        for (se_entry = 0; se_entry < NE; se_entry = se_entry + 1) begin
            alloc_en[se_entry] = 1'b0;
            for (se_src = 0; se_src < NS; se_src = se_src + 1) begin
                data_sel[se_entry][se_src] = eligible[se_src] & src_entry[se_src][se_entry];
                alloc_en[se_entry] = alloc_en[se_entry] | (alloc[se_src] & src_entry[se_src][se_entry]);
            end
        end
        for (se_rank = 0; se_rank < NA; se_rank = se_rank + 1) begin
            age_groups[se_rank*NE +: NE] = {NE{1'b0}};
            for (se_src = 0; se_src < NS; se_src = se_src + 1)
                if (alloc[se_src] && (rank[se_src] == se_rank))
                    age_groups[se_rank*NE +: NE] = age_groups[se_rank*NE +: NE] | src_entry[se_src];
        end
    end
    reg  [REQ_W-1:0] load_packet [0:NE-1];
    reg  [PC_W-1:0]  load_pc [0:NE-1];
    reg  [NE-1:0]    load_line_store;
    integer ld_entry;
    integer ld_src;
    always @* begin
        for (ld_entry = 0; ld_entry < NE; ld_entry = ld_entry + 1) begin
            load_packet[ld_entry]     = {REQ_W{1'b0}};
            load_pc[ld_entry]         = {PC_W{1'b0}};
            load_line_store[ld_entry] = 1'b0;
            for (ld_src = 0; ld_src < NS; ld_src = ld_src + 1) begin
                load_packet[ld_entry] = load_packet[ld_entry] | ({REQ_W{data_sel[ld_entry][ld_src]}} & src_packet[ld_src*REQ_W +: REQ_W]);
                load_pc[ld_entry]     = load_pc[ld_entry]     | ({PC_W{data_sel[ld_entry][ld_src]}}  & src_pc[ld_src*PC_W +: PC_W]);
                load_line_store[ld_entry] = load_line_store[ld_entry] | (data_sel[ld_entry][ld_src] & src_line_store[ld_src]);
            end
            if (load_line_store[ld_entry])
                load_packet[ld_entry] = (load_packet[ld_entry] & ~SLOT_MASK) |
                                        ({{(REQ_W-VEC_SLOT_W){1'b0}}, vec_write_slot} << REQ_DATA_LSB);
        end
    end
    wire [3:0] credit_q;
    reg  [LSU_PORTS-1:0] lowest_req;
    reg  [LSU_PORTS-1:0] lowest_port;
    reg                  lowest_credit;
    reg                  lower_req_seen;
    integer lo_port;
    assign credit_q = {credit_q_3, credit_q_2, credit_q_1, credit_q_0};
    always @* begin
        lowest_credit  = 1'b0;
        lower_req_seen = 1'b0;
        for (lo_port = 0; lo_port < LSU_PORTS; lo_port = lo_port + 1) begin
            lowest_req[lo_port]  = src_valid[lo_port] & !lower_req_seen;
            lower_req_seen       = lower_req_seen | src_valid[lo_port];
            lowest_port[lo_port] = lowest_req[lo_port] & alloc[lo_port];
            lowest_credit        = lowest_credit | (lowest_port[lo_port] & credit_q[lo_port]);
        end
    end
    assign fresh_issue        = fresh_allowed_q & (|lowest_port) & lowest_credit;
    assign fresh_port_onehot  = lowest_port;
    assign fresh_entry_onehot = free_pick[0 +: NE];
    wire [NE-1:0] freed_now;
    reg  [NE-1:0] deps_new [0:NS-1];
    reg           same_set_pair;
    integer dp_src;
    integer dp_entry;
    integer dp_lower;
    always @* begin
        for (dp_src = 0; dp_src < NS; dp_src = dp_src + 1) begin
            for (dp_entry = 0; dp_entry < NE; dp_entry = dp_entry + 1)
                deps_new[dp_src][dp_entry] = valid_q[dp_entry] & ~freed_now[dp_entry] &
                                             (set_q[dp_entry] == src_set[dp_src*INDEX_W +: INDEX_W]) &
                                             (write_q[dp_entry] | src_write[dp_src]);
            for (dp_lower = 0; dp_lower < dp_src; dp_lower = dp_lower + 1) begin
                same_set_pair = alloc[dp_lower] &&
                                (src_set[dp_lower*INDEX_W +: INDEX_W] == src_set[dp_src*INDEX_W +: INDEX_W]) &&
                                (src_write[dp_lower] || src_write[dp_src]);
                if (same_set_pair)
                    deps_new[dp_src] = deps_new[dp_src] | src_entry[dp_lower];
            end
        end
    end
    reg  [NS-1:0] arrival_cand;
    reg  [NS-1:0] arrival_pick;
    reg           arrival_seen;
    integer ab_src;
    always @* begin
        arrival_seen = 1'b0;
        for (ab_src = 0; ab_src < NS; ab_src = ab_src + 1) begin
            arrival_cand[ab_src] = alloc[ab_src] && (deps_new[ab_src] == {NE{1'b0}}) &&
                                   !(fresh_issue && (rank[ab_src] == {RANK_W{1'b0}}) && (ab_src < LSU_PORTS));
            arrival_pick[ab_src] = arrival_cand[ab_src] && !arrival_seen;
            arrival_seen         = arrival_seen || arrival_cand[ab_src];
        end
    end
    reg  [NE-1:0]          ab_entry;
    reg  [REQ_W-1:0]       ab_packet;
    integer ab_mux;
    always @* begin
        ab_entry  = {NE{1'b0}};
        ab_packet = {REQ_W{1'b0}};
        for (ab_mux = 0; ab_mux < NS; ab_mux = ab_mux + 1) begin
            ab_entry  = ab_entry  | ({NE{arrival_pick[ab_mux]}}    & src_entry[ab_mux]);
            ab_packet = ab_packet | ({REQ_W{arrival_pick[ab_mux]}} & src_packet[ab_mux*REQ_W +: REQ_W]);
        end
    end
    assign arrival_book_valid        = |arrival_pick;
    assign arrival_book_entry_onehot = ab_entry;
    assign arrival_book_set          = ab_packet[SET_IN_REQ +: INDEX_W];
    assign arrival_book_line         = ab_packet[LINE_IN_REQ +: LINE_ADDR_W];
    assign arrival_book_port         = ab_packet[REQ_PORT_LSB +: PORT_W];
    assign arrival_book_is_write     = ab_packet[REQ_RDWR_BIT];
    assign arrival_book_is_line_op   = ab_packet[REQ_LINE_BIT];
    assign arrival_book_is_amo       = ab_packet[REQ_AMO_BIT] & ab_packet[REQ_SEQ_BIT];
    reg  [NE-1:0] ready_cand;
    integer rc_entry;
    always @* begin
        for (rc_entry = 0; rc_entry < NE; rc_entry = rc_entry + 1)
            ready_cand[rc_entry] = valid_q[rc_entry] & state_q[rc_entry][TRK_READY_B] & (deps_q[rc_entry] == {NE{1'b0}});
    end
    wire [NE*NE-1:0] older_than_flat;
    wire [SEAT_W-1:0] oldest_index_unused;
    l1d_age_matrix #(.N(NE), .IDX_W(SEAT_W), .ONEHOT_ALLOC(1), .ONEHOT_ENC(1), .MULTI_ALLOC(1), .MULTI_GROUPS(NA)) u_age (
        .clk                   (clk),
        .rst                   (rst),
        .allocate_valid        (1'b0),
        .allocate_index        ({SEAT_W{1'b0}}),
        .allocate_onehot       ({NE{1'b0}}),
        .allocate_group_onehot (age_groups),
        .candidate_mask        (ready_cand),
        .older_than_flat       (older_than_flat),
        .oldest_onehot         (oldest_ready_onehot),
        .oldest_index          (oldest_index_unused),
        .any_candidate         (oldest_ready_valid)
    );
    reg  [REQ_W-1:0] or_packet;
    integer or_entry;
    always @* begin
        or_packet = {REQ_W{1'b0}};
        for (or_entry = 0; or_entry < NE; or_entry = or_entry + 1)
            or_packet = or_packet | ({REQ_W{oldest_ready_onehot[or_entry]}} & packet_q[or_entry]);
    end
    assign oldest_ready_set        = or_packet[SET_IN_REQ +: INDEX_W];
    assign oldest_ready_line       = or_packet[LINE_IN_REQ +: LINE_ADDR_W];
    assign oldest_ready_port       = or_packet[REQ_PORT_LSB +: PORT_W];
    assign oldest_ready_is_write   = or_packet[REQ_RDWR_BIT];
    assign oldest_ready_is_line_op = or_packet[REQ_LINE_BIT];
    assign oldest_ready_is_amo     = or_packet[REQ_AMO_BIT] & or_packet[REQ_SEQ_BIT];
    genvar fl_idx;
    generate
        for (fl_idx = 0; fl_idx < NE; fl_idx = fl_idx + 1) begin : g_flat
            assign entry_packet_flat[fl_idx*REQ_W +: REQ_W] = packet_q[fl_idx];
            assign entry_pc_flat[fl_idx*PC_W +: PC_W]       = pc_q[fl_idx];
        end
    endgenerate
    reg  [NE-1:0] s2_entry_onehot;
    integer s2_dec;
    always @* begin
        for (s2_dec = 0; s2_dec < NE; s2_dec = s2_dec + 1)
            s2_entry_onehot[s2_dec] = s2_cpu_valid && (s2_seat == s2_dec);
    end
    wire s2_free_entry;
    wire s2_to_ready;
    wire s2_to_wait;
    assign s2_free_entry = !s2_kill && (s2_answered || (act_valid && (act_code == ACT_OWNED)));
    assign s2_to_ready   = s2_kill || (act_valid && (act_code == ACT_WECC));
    assign s2_to_wait    = !s2_kill && act_valid && ((act_code == ACT_WMSHR) || (act_code == ACT_WANY) ||
                                                     (act_code == ACT_WVC)   || (act_code == ACT_WNC));
    assign freed_now = s2_entry_onehot & {NE{s2_free_entry}};
    wire [MSHR_ENTRIES-1:0] push_mshr_mask;
    wire [VC_SLOTS-1:0]     push_vc_mask;
    wire                    push_nc_bit;
    wire                    push_ready_now;
    assign push_mshr_mask = (act_code == ACT_WMSHR) ? ({{(MSHR_ENTRIES-1){1'b0}}, 1'b1} << act_id[MSHR_ID_W-1:0]) :
                            (act_code == ACT_WANY)  ? {MSHR_ENTRIES{1'b1}} : {MSHR_ENTRIES{1'b0}};
    assign push_vc_mask   = (act_code == ACT_WVC) ? ({{(VC_SLOTS-1){1'b0}}, 1'b1} << act_id[VC_ID_W-1:0]) : {VC_SLOTS{1'b0}};
    assign push_nc_bit    = (act_code == ACT_WNC);
    assign push_ready_now = (|(push_mshr_mask & mshr_freed)) || (|(push_vc_mask & vc_freed)) || (push_nc_bit && nc_freed);
    assign s2_seat_trained = trained_q[s2_seat];
    assign s2_seat_pc      = pc_q[s2_seat];
    assign r_seat_deps     = deps_q[r_seat];
    reg  [RANK_W-1:0]    alloc_cnt;
    integer ac_src;
    always @* begin
        alloc_cnt = {RANK_W{1'b0}};
        for (ac_src = 0; ac_src < NS; ac_src = ac_src + 1)
            alloc_cnt = alloc_cnt + {{(RANK_W-1){1'b0}}, alloc[ac_src]};
    end
    wire [TRK_CNT_W-1:0] free_count_next;
    assign free_count_next = free_count_q - {{(TRK_CNT_W-RANK_W){1'b0}}, alloc_cnt} + {{(TRK_CNT_W-1){1'b0}}, |freed_now};
    integer ent;
    always @(posedge clk) begin : tracker_proc
        if (rst) begin
            valid_q      <= {NE{1'b0}};
            write_q      <= {NE{1'b0}};
            wait_nc_q    <= {NE{1'b0}};
            trained_q    <= {NE{1'b0}};
            free_count_q <= NE_C;
            for (ent = 0; ent < NE; ent = ent + 1) begin
                state_q[ent]     <= {TRK_STATE_W{1'b0}};
                deps_q[ent]      <= {NE{1'b0}};
                wait_mshr_q[ent] <= {MSHR_ENTRIES{1'b0}};
                wait_vc_q[ent]   <= {VC_SLOTS{1'b0}};
            end
        end else begin
            free_count_q <= free_count_next;
            for (ent = 0; ent < NE; ent = ent + 1) begin
                if (!valid_q[ent]) begin
                    packet_q[ent] <= load_packet[ent];
                    pc_q[ent]     <= load_pc[ent];
                    set_q[ent]    <= load_packet[ent][SET_IN_REQ +: INDEX_W];
                    write_q[ent]  <= load_packet[ent][REQ_RDWR_BIT];
                end
                if (alloc_en[ent]) begin
                    valid_q[ent]     <= 1'b1;
                    trained_q[ent]   <= 1'b0;
                    wait_nc_q[ent]   <= 1'b0;
                    wait_mshr_q[ent] <= {MSHR_ENTRIES{1'b0}};
                    wait_vc_q[ent]   <= {VC_SLOTS{1'b0}};
                    state_q[ent]     <= {TRK_STATE_W{1'b0}};
                    if (fresh_issue && fresh_entry_onehot[ent])
                        state_q[ent][TRK_INFL_B]   <= 1'b1;
                    else if (book_entry_onehot[ent])
                        state_q[ent][TRK_BOOKED_B] <= 1'b1;
                    else
                        state_q[ent][TRK_READY_B]  <= 1'b1;
                    deps_q[ent] <= {NE{1'b0}};
                    for (ac_src = 0; ac_src < NS; ac_src = ac_src + 1)
                        if (alloc[ac_src] && src_entry[ac_src][ent])
                            deps_q[ent] <= deps_new[ac_src];
                end else if (valid_q[ent]) begin
                    deps_q[ent] <= deps_q[ent] & ~freed_now;
                    if (s2_entry_onehot[ent]) begin
                        if (s2_free_entry) begin
                            valid_q[ent] <= 1'b0;
                            state_q[ent] <= {TRK_STATE_W{1'b0}};
                        end else if (s2_to_ready) begin
                            state_q[ent] <= {TRK_STATE_W{1'b0}};
                            state_q[ent][TRK_READY_B] <= 1'b1;
                        end else if (s2_to_wait) begin
                            state_q[ent] <= {TRK_STATE_W{1'b0}};
                            if (push_ready_now) state_q[ent][TRK_READY_B] <= 1'b1;
                            else                state_q[ent][TRK_WAIT_B]  <= 1'b1;
                            wait_mshr_q[ent] <= push_mshr_mask;
                            wait_vc_q[ent]   <= push_vc_mask;
                            wait_nc_q[ent]   <= push_nc_bit;
                        end
                        if (s2_train_sent) trained_q[ent] <= 1'b1;
                    end else begin
                        if (state_q[ent][TRK_WAIT_B] &&
                            ((|(wait_mshr_q[ent] & mshr_freed)) || (|(wait_vc_q[ent] & vc_freed)) || (wait_nc_q[ent] && nc_freed))) begin
                            state_q[ent] <= {TRK_STATE_W{1'b0}};
                            state_q[ent][TRK_READY_B] <= 1'b1;
                        end
                        if (book_entry_onehot[ent] && state_q[ent][TRK_READY_B]) begin
                            state_q[ent] <= {TRK_STATE_W{1'b0}};
                            state_q[ent][TRK_BOOKED_B] <= 1'b1;
                        end
                        if (issue_entry_onehot[ent]) begin
                            state_q[ent] <= {TRK_STATE_W{1'b0}};
                            state_q[ent][TRK_INFL_B] <= 1'b1;
                        end
                    end
                end
            end
        end
    end
    assign entry_valid_q = valid_q;
    assign tracker_empty = ~|valid_q;
`ifndef SYNTHESIS
    integer chk_src;
    integer chk_entry;
    integer chk_hits;
    initial if (LSU_PORTS != 4)
        $display("L1D TRACKER ERROR bank %0d: LSU_PORTS = %0d, the ports _0 .. _3 need LSU_PORTS = 4", BANK_ID, LSU_PORTS);
    always @(posedge clk) begin
        if (!rst) begin
            if (drain_request && any_pins_arrival)
                $display("[%0t] L1D TRACKER ERROR bank %0d: pins arrival and drain in the same cycle (front rule A1 broken)", $time, BANK_ID);
            for (chk_entry = 0; chk_entry < NE; chk_entry = chk_entry + 1) begin
                chk_hits = 0;
                for (chk_src = 0; chk_src < NS; chk_src = chk_src + 1)
                    if (alloc[chk_src] && src_entry[chk_src][chk_entry]) chk_hits = chk_hits + 1;
                if (chk_hits > 1)
                    $display("[%0t] L1D TRACKER ERROR bank %0d: entry %0d allocated by %0d sources at once", $time, BANK_ID, chk_entry, chk_hits);
                if (alloc_en[chk_entry] && valid_q[chk_entry])
                    $display("[%0t] L1D TRACKER ERROR bank %0d: entry %0d allocated while in use", $time, BANK_ID, chk_entry);
            end
            for (chk_src = 0; chk_src < NS; chk_src = chk_src + 1)
                if (alloc[chk_src] && (src_entry[chk_src] == {NE{1'b0}}))
                    $display("[%0t] L1D TRACKER ERROR bank %0d: source %0d allocated without a free entry (request lost)", $time, BANK_ID, chk_src);
            if (s2_cpu_valid && !valid_q[s2_seat])
                $display("[%0t] L1D TRACKER ERROR bank %0d: S2 result for entry %0d, which is free", $time, BANK_ID, s2_seat);
            if (s2_cpu_valid && !state_q[s2_seat][TRK_INFL_B])
                $display("[%0t] L1D TRACKER ERROR bank %0d: S2 result for entry %0d, which is not in flight", $time, BANK_ID, s2_seat);
            if ((|book_entry_onehot) && (|(book_entry_onehot & issue_entry_onehot)))
                $display("[%0t] L1D TRACKER ERROR bank %0d: an entry is booked and issued in one cycle", $time, BANK_ID);
        end
    end
`endif
`ifdef L1D_DEBUG
    always @(posedge clk) begin
        if (!rst) begin
            for (chk_src = 0; chk_src < NS; chk_src = chk_src + 1)
                if (alloc[chk_src])
                    $display("[%0t] L1D TRACKER bank %0d: source %0d (port %0d) -> entry %b rank %0d%s deps=%b", $time, BANK_ID, chk_src,
                             src_packet[chk_src*REQ_W + REQ_PORT_LSB +: PORT_W], src_entry[chk_src], rank[chk_src],
                             (fresh_issue && rank[chk_src] == 0 && chk_src < LSU_PORTS) ? " FRESH" : "", deps_new[chk_src]);
            if (|freed_now)
                $display("[%0t] L1D TRACKER bank %0d: entry %0d freed (free next = %0d)", $time, BANK_ID, s2_seat, free_count_next);
        end
    end
`endif
endmodule
`default_nettype wire
`endif
