`default_nettype none
`include "l1d_defines.vh"
module l1d_top_single_port #(
    parameter ADDR_W           = `L1D_ADDR_W,
    parameter LINE_BYTES       = `L1D_LINE_BYTES,
    parameter NUM_BANKS        = `L1D_NUM_BANKS,
    parameter SETS             = `L1D_SETS,
    parameter WAYS             = `L1D_WAYS,
    parameter WRITE_DATA_WIDTH = `L1D_WRITE_DATA_WIDTH,
    parameter MEM_SIZE_BITS    = `L1D_MEM_SIZE_BITS,
    parameter MASTER_ID_BITS   = `L1D_MASTER_ID_BITS,
    parameter IDX_BITS         = `L1D_IDX_BITS,
    parameter INQ_DEPTH        = (1 << IDX_BITS),
    parameter HAS_INPUT_QUEUE  = 1,
    parameter PORT_QUEUE_DEPTH = `L1D_PORT_QUEUE_DEPTH,
    parameter LSU_BUF_DEPTH    = `L1D_LSU_BUF_DEPTH,
    parameter TRK_ENTRIES      = `L1D_TRK_ENTRIES,
    parameter TRK_REFILL_RSV   = `L1D_TRK_REFILL_RSV,
    parameter MSHR_ENTRIES     = `L1D_MSHR_ENTRIES,
    parameter MSHR_NC_ENTRIES  = `L1D_MSHR_NC_ENTRIES,
    parameter VC_SLOTS         = `L1D_VC_SLOTS,
    parameter RESP_FIFO_DEPTH  = `L1D_RESP_FIFO_DEPTH,
    parameter REFILL_SKIP      = `L1D_REFILL_SKIP,
    parameter SNP_BUF_DEPTH    = `L1D_SNP_BUF_DEPTH,
    parameter SNP_RESP_DEPTH   = `L1D_SNP_RESP_DEPTH,
    parameter PF_FIFO_DEPTH    = `L1D_PF_FIFO_DEPTH,
    parameter SNP_STARVE       = `L1D_SNP_STARVE,
    parameter LOCK_TIMEOUT     = `L1D_LOCK_TIMEOUT,
    parameter RSV_CLR_ON_EVICT = `L1D_RSV_CLR_ON_EVICT,
    parameter HAS_SNOOP        = `L1D_HAS_SNOOP,
    parameter HAS_AMO          = `L1D_HAS_AMO,
    parameter AXI_DATA_W       = `L1D_AXI_DATA_W,
    parameter AXI_ADDR_W       = `L1D_AXI_ADDR_W,
    parameter L2_ADDR_W        = 56,
    parameter L2_MID_W         = 2,
    parameter L2_TID_W         = 6,
    parameter L2_MASTER_ID     = 0,
    parameter L2_PKT_W         = 1 + L2_ADDR_W + 1 + L2_MID_W + L2_TID_W + 1 + LINE_BYTES + LINE_BYTES*8,
    parameter LSU_PORTS        = `L1D_LSU_PORTS,
    parameter HAS_MISS         = `L1D_HAS_MISS,
    parameter HAS_VC           = `L1D_HAS_VC,
    parameter HAS_NC           = `L1D_HAS_NC,
    parameter HAS_VPU          = 0,
    parameter PC_W             = `L1D_PC_W,
    parameter TRK_ALLOC_MAX    = `L1D_TRK_ALLOC_MAX,
    parameter PF_MSHR_MAX      = `L1D_PF_MSHR_MAX,
    parameter HAS_ECC          = `L1D_HAS_ECC,
    parameter HAS_PF           = `L1D_HAS_PF
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         flush_request,
    input  wire                         clean_request,
    output wire                         flush_complete,
    output wire                         clean_complete,
    input  wire                         cpu_request_valid,
    input  wire                         cpu_request_cacheable,
    input  wire                         cpu_request_is_write,
    input  wire [MEM_SIZE_BITS-1:0]     cpu_request_size,
    input  wire [MASTER_ID_BITS-1:0]    cpu_request_master_id,
    input  wire [IDX_BITS-1:0]          cpu_request_rob_index,
    input  wire [ADDR_W-1:0]            cpu_request_addr,
    input  wire [WRITE_DATA_WIDTH-1:0]  cpu_request_store_data,
    input  wire                         cpu_request_is_atomic,
    input  wire                         cpu_request_atomic_is_amo,
    input  wire [3:0]                   cpu_request_amo_op,
    output wire                         input_queue_full,
    input  wire                         lsu_response_read_enable,
    output wire                         lsu_response_valid,
    output wire                         lsu_response_is_write_ack,
    output wire [MEM_SIZE_BITS-1:0]     lsu_response_size,
    output wire [MASTER_ID_BITS-1:0]    lsu_response_master_id,
    output wire [IDX_BITS-1:0]          lsu_response_rob_index,
    output wire [WRITE_DATA_WIDTH-1:0]  lsu_response_data,
    input  wire                         snoop_request_valid,
    output wire                         snoop_request_ready,
    input  wire [ADDR_W-1:0]            snoop_request_addr,
    input  wire                         snoop_request_invalidate,
    output wire                         snoop_response_valid,
    input  wire                         snoop_response_ready,
    output wire [ADDR_W-1:0]            snoop_response_addr,
    output wire                         snoop_response_present,
    output wire                         snoop_response_dirty,
    output wire [LINE_BYTES*8-1:0]      snoop_response_data,
    output wire                         l2_error_sticky,
    output wire                         amo_lock_timeout_sticky,
    output wire                         ecc_correctable_pulse,
    output wire                         ecc_uncorrectable_sticky,
    output wire                         l2_req_valid,
    input  wire                         l2_req_ready,
    output wire [L2_PKT_W-1:0]          l2_req_pkt,
    input  wire                         l2_resp_valid,
    output wire                         l2_resp_ready,
    input  wire [L2_PKT_W-1:0]          l2_resp_pkt,
    input  wire                         l2_resp_err
);
    localparam DATA_LSB      = 0;
    localparam ADDR_LSB      = DATA_LSB + WRITE_DATA_WIDTH;
    localparam ROB_LSB       = ADDR_LSB + ADDR_W;
    localparam MASTER_LSB    = ROB_LSB + IDX_BITS;
    localparam SIZE_LSB      = MASTER_LSB + MASTER_ID_BITS;
    localparam CACHEABLE_BIT = SIZE_LSB + MEM_SIZE_BITS;
    localparam WRITE_BIT     = CACHEABLE_BIT + 1;
    localparam AMO_OP_LSB    = WRITE_BIT + 1;
    localparam AMO_BIT       = AMO_OP_LSB + 4;
    localparam ATOMIC_BIT    = AMO_BIT + 1;
    localparam STORE_PORT_BIT = ATOMIC_BIT + 1;
    wire pin_goes_to_store_port = cpu_request_is_write || (cpu_request_is_atomic && cpu_request_atomic_is_amo);
    wire [STORE_PORT_BIT:0] pin_request = {pin_goes_to_store_port, cpu_request_is_atomic, cpu_request_atomic_is_amo,
                                           cpu_request_amo_op, cpu_request_is_write, cpu_request_cacheable,
                                           cpu_request_size, cpu_request_master_id, cpu_request_rob_index,
                                           cpu_request_addr, cpu_request_store_data};
    wire load_port_stop;
    wire store_port_stop;
    wire                    issue_valid;
    wire [STORE_PORT_BIT:0] issue_request;
    generate
        if (HAS_INPUT_QUEUE != 0) begin : g_input_queue
            wire                    queue_empty;
            wire                    queue_full;
            wire [STORE_PORT_BIT:0] queue_front;
            wire                    queue_push;
            wire                    queue_pop;
            wire                    candidate_valid   = !queue_empty || cpu_request_valid;
            wire [STORE_PORT_BIT:0] candidate_request = queue_empty ? pin_request : queue_front;
            wire                    candidate_port_stopped = candidate_request[STORE_PORT_BIT] ? store_port_stop : load_port_stop;
            assign issue_valid   = candidate_valid && !candidate_port_stopped;
            assign issue_request = candidate_request;
            assign queue_pop     = !queue_empty && !candidate_port_stopped;
            assign queue_push    = cpu_request_valid && !(queue_empty && !candidate_port_stopped);
            l1d_fifo #(.WIDTH(STORE_PORT_BIT + 1), .DEPTH(INQ_DEPTH)) u_input_queue (
                .clk        (clk),
                .rst        (rst),
                .push       (queue_push),
                .push_data  (pin_request),
                .pop        (queue_pop),
                .front_data (queue_front),
                .empty      (queue_empty),
                .full       (queue_full),
                .used_slots (),
                .free_slots ()
            );
            assign input_queue_full = queue_full;
`ifndef SYNTHESIS
            always @(posedge clk)
                if (!rst && cpu_request_valid && queue_full)
                    $display("[%0t] L1D SINGLE PORT  ERROR request idx %0d lost: input queue full (more than %0d requests in flight)",
                             $time, cpu_request_rob_index, INQ_DEPTH);
`endif
        end else begin : g_no_input_queue
            assign issue_valid      = cpu_request_valid;
            assign issue_request    = pin_request;
            assign input_queue_full = load_port_stop || store_port_stop;
`ifndef SYNTHESIS
            always @(posedge clk)
                if (!rst && cpu_request_valid && (pin_goes_to_store_port ? store_port_stop : load_port_stop))
                    $display("[%0t] L1D SINGLE PORT  ERROR request idx %0d sent while its port is stopped (HAS_INPUT_QUEUE = 0)",
                             $time, cpu_request_rob_index);
`endif
        end
    endgenerate
    wire                        issue_to_store_port = issue_request[STORE_PORT_BIT];
    wire                        issue_is_atomic     = issue_request[ATOMIC_BIT];
    wire                        issue_is_amo        = issue_request[AMO_BIT];
    wire [3:0]                  issue_amo_op        = issue_request[AMO_OP_LSB +: 4];
    wire                        issue_cacheable     = issue_request[CACHEABLE_BIT];
    wire [MEM_SIZE_BITS-1:0]    issue_size          = issue_request[SIZE_LSB +: MEM_SIZE_BITS];
    wire [MASTER_ID_BITS-1:0]   issue_master_id     = issue_request[MASTER_LSB +: MASTER_ID_BITS];
    wire [IDX_BITS-1:0]         issue_rob_index     = issue_request[ROB_LSB +: IDX_BITS];
    wire [ADDR_W-1:0]           issue_addr          = issue_request[ADDR_LSB +: ADDR_W];
    wire [WRITE_DATA_WIDTH-1:0] issue_data          = issue_request[DATA_LSB +: WRITE_DATA_WIDTH];
    wire load_port_valid  = issue_valid && !issue_to_store_port;
    wire store_port_valid = issue_valid &&  issue_to_store_port;
    wire                        load_answer_valid;
    wire [MEM_SIZE_BITS-1:0]    load_answer_size;
    wire [MASTER_ID_BITS-1:0]   load_answer_master_id;
    wire [IDX_BITS-1:0]         load_answer_rob_index;
    wire [WRITE_DATA_WIDTH-1:0] load_answer_data;
    wire                        store_answer_valid;
    wire                        store_answer_is_write_ack;
    wire [MEM_SIZE_BITS-1:0]    store_answer_size;
    wire [MASTER_ID_BITS-1:0]   store_answer_master_id;
    wire [IDX_BITS-1:0]         store_answer_rob_index;
    wire [WRITE_DATA_WIDTH-1:0] store_answer_data;
    reg  store_turn_q;
    reg  shown_held_q;
    reg  shown_is_store_q;
    wire show_store = shown_held_q ? shown_is_store_q
                                   : (store_answer_valid && (!load_answer_valid || store_turn_q));
    assign lsu_response_valid        = show_store ? store_answer_valid        : load_answer_valid;
    assign lsu_response_is_write_ack = show_store ? store_answer_is_write_ack : 1'b0;
    assign lsu_response_size         = show_store ? store_answer_size         : load_answer_size;
    assign lsu_response_master_id    = show_store ? store_answer_master_id    : load_answer_master_id;
    assign lsu_response_rob_index    = show_store ? store_answer_rob_index    : load_answer_rob_index;
    assign lsu_response_data         = show_store ? store_answer_data         : load_answer_data;
    wire answer_taken      = lsu_response_valid && lsu_response_read_enable;
    wire take_load_answer  = answer_taken && !show_store;
    wire take_store_answer = answer_taken &&  show_store;
    always @(posedge clk) begin
        if (rst) begin
            store_turn_q     <= 1'b0;
            shown_held_q     <= 1'b0;
            shown_is_store_q <= 1'b0;
        end else begin
            if (answer_taken)
                store_turn_q <= !show_store;
            shown_held_q     <= lsu_response_valid && !lsu_response_read_enable;
            shown_is_store_q <= show_store;
        end
    end
`ifndef SYNTHESIS
    initial if (LSU_PORTS != 4)
        $display("L1D SINGLE PORT  ERROR LSU_PORTS = %0d: l1d_top has the named ports _0 .. _3 and needs 4", LSU_PORTS);
`endif
    wire [PC_W-1:0] pc_none;
    wire            prefetch_on;
    assign pc_none     = {PC_W{1'b0}};
    assign prefetch_on = 1'b1;
    l1d_top #(
        .ADDR_W(ADDR_W), .LINE_BYTES(LINE_BYTES), .NUM_BANKS(NUM_BANKS), .SETS(SETS), .WAYS(WAYS),
        .WRITE_DATA_WIDTH(WRITE_DATA_WIDTH), .MEM_SIZE_BITS(MEM_SIZE_BITS), .MASTER_ID_BITS(MASTER_ID_BITS),
        .IDX_BITS(IDX_BITS), .PORT_QUEUE_DEPTH(PORT_QUEUE_DEPTH), .LSU_BUF_DEPTH(LSU_BUF_DEPTH), .TRK_ENTRIES(TRK_ENTRIES),
        .TRK_REFILL_RSV(TRK_REFILL_RSV), .MSHR_ENTRIES(MSHR_ENTRIES), .MSHR_NC_ENTRIES(MSHR_NC_ENTRIES),
        .VC_SLOTS(VC_SLOTS), .RESP_FIFO_DEPTH(RESP_FIFO_DEPTH), .REFILL_SKIP(REFILL_SKIP),
        .SNP_BUF_DEPTH(SNP_BUF_DEPTH), .SNP_RESP_DEPTH(SNP_RESP_DEPTH), .PF_FIFO_DEPTH(PF_FIFO_DEPTH),
        .SNP_STARVE(SNP_STARVE), .LOCK_TIMEOUT(LOCK_TIMEOUT), .RSV_CLR_ON_EVICT(RSV_CLR_ON_EVICT),
        .HAS_SNOOP(HAS_SNOOP), .HAS_AMO(HAS_AMO), .AXI_DATA_W(AXI_DATA_W), .AXI_ADDR_W(AXI_ADDR_W),
        .L2_ADDR_W(L2_ADDR_W), .L2_MID_W(L2_MID_W), .L2_TID_W(L2_TID_W), .L2_MASTER_ID(L2_MASTER_ID),
        .LSU_PORTS(LSU_PORTS), .HAS_MISS(HAS_MISS), .HAS_VC(HAS_VC), .HAS_NC(HAS_NC), .HAS_VPU(HAS_VPU),
        .PC_W(PC_W), .TRK_ALLOC_MAX(TRK_ALLOC_MAX), .PF_MSHR_MAX(PF_MSHR_MAX), .HAS_ECC(HAS_ECC), .HAS_PF(HAS_PF)
    ) u_dcache (
        .clk(clk), .rst(rst),
        .flush(flush_request), .clean(clean_request), .flush_complete(flush_complete), .clean_complete(clean_complete),
        .pc_cpu_0(pc_none), .pc_cpu_1(pc_none), .pc_cpu_2(pc_none), .pf_enable(prefetch_on),
        .ecc_correctable_pulse(ecc_correctable_pulse), .ecc_uncorrectable_sticky(ecc_uncorrectable_sticky),
        .valid_cpu_0          (load_port_valid),
        .cacheable_0          (issue_cacheable),
        .mem_size_cpu_0       (issue_size),
        .master_id_from_cpu_0 (issue_master_id),
        .idx_from_cpu_0       (issue_rob_index),
        .PC_from_cpu_0        (issue_addr),
        .is_lr_cpu_0          (issue_is_atomic),
        .stop_0               (load_port_stop),
        .valid_cpu_1          (1'b0),
        .cacheable_1          (1'b1),
        .mem_size_cpu_1       ({MEM_SIZE_BITS{1'b0}}),
        .master_id_from_cpu_1 ({MASTER_ID_BITS{1'b0}}),
        .idx_from_cpu_1       ({IDX_BITS{1'b0}}),
        .PC_from_cpu_1        ({ADDR_W{1'b0}}),
        .is_lr_cpu_1          (1'b0),
        .stop_1               (),
        .valid_cpu_2          (store_port_valid),
        .cacheable_2          (issue_cacheable),
        .mem_size_cpu_2       (issue_size),
        .master_id_from_cpu_2 (issue_master_id),
        .idx_from_cpu_2       (issue_rob_index),
        .PC_from_cpu_2        (issue_addr),
        .data_from_cpu_2      (issue_data),
        .is_sc_cpu_2          (issue_is_atomic && !issue_is_amo),
        .is_amo_cpu_2         (issue_is_atomic &&  issue_is_amo),
        .amo_op_cpu_2         (issue_amo_op),
        .stop_2               (store_port_stop),
        .valid_cpu_3          (1'b0),
        .rd_wr_cpu_3          (1'b0),
        .cacheable_3          (1'b1),
        .master_id_from_cpu_3 ({MASTER_ID_BITS{1'b0}}),
        .idx_from_cpu_3       ({IDX_BITS{1'b0}}),
        .PC_from_cpu_3        ({ADDR_W{1'b0}}),
        .data_from_cpu_3      ({(LINE_BYTES*8){1'b0}}),
        .stop_3               (),
        .read_enable_from_lsu_0             (take_load_answer),
        .final_r_cache_hit_from_scheduler_0 (load_answer_valid),
        .final_r_mem_size_from_scheduler_0  (load_answer_size),
        .final_r_master_id_from_scheduler_0 (load_answer_master_id),
        .final_r_idx_from_scheduler_0       (load_answer_rob_index),
        .final_r_data_from_scheduler_0      (load_answer_data),
        .read_enable_from_lsu_1             (1'b1),
        .final_r_cache_hit_from_scheduler_1 (),
        .final_r_mem_size_from_scheduler_1  (),
        .final_r_master_id_from_scheduler_1 (),
        .final_r_idx_from_scheduler_1       (),
        .final_r_data_from_scheduler_1      (),
        .read_enable_from_lsu_2             (take_store_answer),
        .final_r_cache_hit_from_scheduler_2 (store_answer_valid),
        .final_r_hit_rd_wr_from_scheduler_2 (store_answer_is_write_ack),
        .final_r_mem_size_from_scheduler_2  (store_answer_size),
        .final_r_master_id_from_scheduler_2 (store_answer_master_id),
        .final_r_idx_from_scheduler_2       (store_answer_rob_index),
        .final_r_data_from_scheduler_2      (store_answer_data),
        .read_enable_from_lsu_3             (1'b1),
        .final_r_cache_hit_from_scheduler_3 (),
        .final_r_hit_rd_wr_from_scheduler_3 (),
        .final_r_master_id_from_scheduler_3 (),
        .final_r_idx_from_scheduler_3       (),
        .final_r_data_from_scheduler_3      (),
        .snoop_request_valid     (snoop_request_valid),
        .snoop_request_ready     (snoop_request_ready),
        .snoop_request_addr      (snoop_request_addr),
        .snoop_request_invalidate(snoop_request_invalidate),
        .snoop_response_valid    (snoop_response_valid),
        .snoop_response_ready    (snoop_response_ready),
        .snoop_response_addr     (snoop_response_addr),
        .snoop_response_present  (snoop_response_present),
        .snoop_response_dirty    (snoop_response_dirty),
        .snoop_response_data     (snoop_response_data),
        .mem_err                 (l2_error_sticky),
        .amo_err                 (amo_lock_timeout_sticky),
        .l2_req_valid            (l2_req_valid),
        .l2_req_ready            (l2_req_ready),
        .l2_req_pkt              (l2_req_pkt),
        .l2_resp_valid           (l2_resp_valid),
        .l2_resp_ready           (l2_resp_ready),
        .l2_resp_pkt             (l2_resp_pkt),
        .l2_resp_err             (l2_resp_err)
    );
endmodule
`default_nettype wire
