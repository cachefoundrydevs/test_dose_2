`default_nettype none
`include "l1d_defines.vh"
module l1d_top #(
    parameter ADDR_W           = `L1D_ADDR_W,
    parameter LINE_BYTES       = `L1D_LINE_BYTES,
    parameter NUM_BANKS        = `L1D_NUM_BANKS,
    parameter SETS             = `L1D_SETS,
    parameter WAYS             = `L1D_WAYS,
    parameter WRITE_DATA_WIDTH = `L1D_WRITE_DATA_WIDTH,
    parameter MEM_SIZE_BITS    = `L1D_MEM_SIZE_BITS,
    parameter MASTER_ID_BITS   = `L1D_MASTER_ID_BITS,
    parameter IDX_BITS         = `L1D_IDX_BITS,
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
    parameter HAS_VPU          = `L1D_HAS_VPU,
    parameter PC_W             = `L1D_PC_W,
    parameter TRK_ALLOC_MAX    = `L1D_TRK_ALLOC_MAX,
    parameter PF_MSHR_MAX      = `L1D_PF_MSHR_MAX,
    parameter HAS_ECC          = `L1D_HAS_ECC,
    parameter HAS_PF           = `L1D_HAS_PF
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         flush,
    input  wire                         clean,
    output reg                          flush_complete,
    output reg                          clean_complete,
    input  wire                         valid_cpu_0,
    input  wire                         cacheable_0,
    input  wire [MEM_SIZE_BITS-1:0]     mem_size_cpu_0,
    input  wire [MASTER_ID_BITS-1:0]    master_id_from_cpu_0,
    input  wire [IDX_BITS-1:0]          idx_from_cpu_0,
    input  wire [ADDR_W-1:0]            PC_from_cpu_0,
    input  wire                         is_lr_cpu_0,
    output wire                         stop_0,
    input  wire                         valid_cpu_1,
    input  wire                         cacheable_1,
    input  wire [MEM_SIZE_BITS-1:0]     mem_size_cpu_1,
    input  wire [MASTER_ID_BITS-1:0]    master_id_from_cpu_1,
    input  wire [IDX_BITS-1:0]          idx_from_cpu_1,
    input  wire [ADDR_W-1:0]            PC_from_cpu_1,
    input  wire                         is_lr_cpu_1,
    output wire                         stop_1,
    input  wire                         valid_cpu_2,
    input  wire                         cacheable_2,
    input  wire [MEM_SIZE_BITS-1:0]     mem_size_cpu_2,
    input  wire [MASTER_ID_BITS-1:0]    master_id_from_cpu_2,
    input  wire [IDX_BITS-1:0]          idx_from_cpu_2,
    input  wire [ADDR_W-1:0]            PC_from_cpu_2,
    input  wire [WRITE_DATA_WIDTH-1:0]  data_from_cpu_2,
    input  wire                         is_sc_cpu_2,
    input  wire                         is_amo_cpu_2,
    input  wire [3:0]                   amo_op_cpu_2,
    output wire                         stop_2,
    input  wire                         valid_cpu_3,
    input  wire                         rd_wr_cpu_3,
    input  wire                         cacheable_3,
    input  wire [MASTER_ID_BITS-1:0]    master_id_from_cpu_3,
    input  wire [IDX_BITS-1:0]          idx_from_cpu_3,
    input  wire [ADDR_W-1:0]            PC_from_cpu_3,
    input  wire [LINE_BYTES*8-1:0]      data_from_cpu_3,
    output wire                         stop_3,
    input  wire [PC_W-1:0]              pc_cpu_0,
    input  wire [PC_W-1:0]              pc_cpu_1,
    input  wire [PC_W-1:0]              pc_cpu_2,
    input  wire                         pf_enable,
    input  wire                         read_enable_from_lsu_0,
    output wire                         final_r_cache_hit_from_scheduler_0,
    output wire [MEM_SIZE_BITS-1:0]     final_r_mem_size_from_scheduler_0,
    output wire [MASTER_ID_BITS-1:0]    final_r_master_id_from_scheduler_0,
    output wire [IDX_BITS-1:0]          final_r_idx_from_scheduler_0,
    output wire [WRITE_DATA_WIDTH-1:0]  final_r_data_from_scheduler_0,
    input  wire                         read_enable_from_lsu_1,
    output wire                         final_r_cache_hit_from_scheduler_1,
    output wire [MEM_SIZE_BITS-1:0]     final_r_mem_size_from_scheduler_1,
    output wire [MASTER_ID_BITS-1:0]    final_r_master_id_from_scheduler_1,
    output wire [IDX_BITS-1:0]          final_r_idx_from_scheduler_1,
    output wire [WRITE_DATA_WIDTH-1:0]  final_r_data_from_scheduler_1,
    input  wire                         read_enable_from_lsu_2,
    output wire                         final_r_cache_hit_from_scheduler_2,
    output wire                         final_r_hit_rd_wr_from_scheduler_2,
    output wire [MEM_SIZE_BITS-1:0]     final_r_mem_size_from_scheduler_2,
    output wire [MASTER_ID_BITS-1:0]    final_r_master_id_from_scheduler_2,
    output wire [IDX_BITS-1:0]          final_r_idx_from_scheduler_2,
    output wire [WRITE_DATA_WIDTH-1:0]  final_r_data_from_scheduler_2,
    input  wire                         read_enable_from_lsu_3,
    output wire                         final_r_cache_hit_from_scheduler_3,
    output wire                         final_r_hit_rd_wr_from_scheduler_3,
    output wire [MASTER_ID_BITS-1:0]    final_r_master_id_from_scheduler_3,
    output wire [IDX_BITS-1:0]          final_r_idx_from_scheduler_3,
    output wire [LINE_BYTES*8-1:0]      final_r_data_from_scheduler_3,
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
    output reg                          mem_err,
    output reg                          amo_err,
    output reg                          ecc_correctable_pulse,
    output reg                          ecc_uncorrectable_sticky,
    output wire                         l2_req_valid,
    input  wire                         l2_req_ready,
    output wire [L2_PKT_W-1:0]          l2_req_pkt,
    input  wire                         l2_resp_valid,
    output wire                         l2_resp_ready,
    input  wire [L2_PKT_W-1:0]          l2_resp_pkt,
    input  wire                         l2_resp_err
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam NB = NUM_BANKS;
    wire [1:0]        no_pf_bits   = 2'b00;
    wire              lr_0         = (HAS_AMO != 0) && is_lr_cpu_0;
    wire              lr_1         = (HAS_AMO != 0) && is_lr_cpu_1;
    wire              atomic_2     = (HAS_AMO != 0) && (is_sc_cpu_2 || is_amo_cpu_2);
    wire              amo_2        = atomic_2 && is_amo_cpu_2;
    wire [AMOOP_W-1:0] amo_op_2    = amo_2 ? amo_op_cpu_2[AMOOP_W-1:0] : {AMOOP_W{1'b0}};
    wire              req_valid_0  = valid_cpu_0;
    wire              req_valid_1  = valid_cpu_1;
    wire              req_valid_2  = valid_cpu_2;
    wire              req_valid_3  = (HAS_VPU != 0) && valid_cpu_3;
    wire [REQ_W-1:0]  req_packet_0 = {no_pf_bits, 1'b0, 2'd0, {AMOOP_W{1'b0}}, 1'b0, lr_0, 1'b0, cacheable_0,
                                      mem_size_cpu_0, master_id_from_cpu_0, idx_from_cpu_0, PC_from_cpu_0,
                                      {WRITE_DATA_WIDTH{1'b0}}};
    wire [REQ_W-1:0]  req_packet_1 = {no_pf_bits, 1'b0, 2'd1, {AMOOP_W{1'b0}}, 1'b0, lr_1, 1'b0, cacheable_1,
                                      mem_size_cpu_1, master_id_from_cpu_1, idx_from_cpu_1, PC_from_cpu_1,
                                      {WRITE_DATA_WIDTH{1'b0}}};
    wire [REQ_W-1:0]  req_packet_2 = {no_pf_bits, 1'b0, 2'd2, amo_op_2, amo_2, atomic_2, 1'b1, cacheable_2,
                                      mem_size_cpu_2, master_id_from_cpu_2, idx_from_cpu_2, PC_from_cpu_2,
                                      data_from_cpu_2};
    wire [REQ_W-1:0]  req_packet_3 = {no_pf_bits, 1'b1, 2'd3, {AMOOP_W{1'b0}}, 1'b0, 1'b0, rd_wr_cpu_3, 1'b1,
                                      {MEM_SIZE_BITS{1'b1}}, master_id_from_cpu_3, idx_from_cpu_3, PC_from_cpu_3,
                                      {WRITE_DATA_WIDTH{1'b0}}};
`ifndef SYNTHESIS
    initial if (LSU_PORTS != 4)
        $display("L1D TOP  ERROR LSU_PORTS = %0d: the named ports _0 .. _3 need LSU_PORTS = 4", LSU_PORTS);
    always @(posedge clk) begin
        if (!rst && (HAS_VPU != 0) && valid_cpu_3) begin
            if (PC_from_cpu_3[OFFSET_W-1:0] != {OFFSET_W{1'b0}})
                $display("[%0t] L1D TOP  ERROR VPU request idx %0d address %h is not 64-byte aligned", $time, idx_from_cpu_3, PC_from_cpu_3);
            if (!cacheable_3)
                $display("[%0t] L1D TOP  ERROR VPU request idx %0d is non-cacheable: not built (open item PO-6), done as cacheable", $time, idx_from_cpu_3);
        end
    end
`endif
    wire [NB-1:0]           bk_arrival_req_0;
    wire [NB-1:0]           bk_arrival_req_1;
    wire [NB-1:0]           bk_arrival_req_2;
    wire [NB-1:0]           bk_arrival_req_3;
    wire [NB-1:0]           bk_drain_req;
    wire [NB*REQ_W-1:0]     bk_drain_pkt;
    wire [NB*PC_W-1:0]      bk_drain_pc;
    wire [NB*LINE_W-1:0]    bk_arrival_line;
    wire [NB-1:0]           bk_arrival_alloc_0;
    wire [NB-1:0]           bk_arrival_alloc_1;
    wire [NB-1:0]           bk_arrival_alloc_2;
    wire [NB-1:0]           bk_arrival_alloc_3;
    wire [NB-1:0]           bk_drain_alloc;
    wire [NB*TRK_CNT_W-1:0] bk_tracker_free;
    wire [NB-1:0]           bk_vec_slot_ok;
    wire                    port_stop_3;
    wire [PC_W-1:0]         pc_none;
    assign pc_none = {PC_W{1'b0}};
    l1d_port_front #(`L1D_PARAMS_PASS, .PORT_QUEUE_DEPTH(PORT_QUEUE_DEPTH), .LINE_PORT_ON(HAS_VPU)) u_front (
        .clk                      (clk),
        .rst                      (rst),
        .port_request_valid_0     (req_valid_0),
        .port_request_valid_1     (req_valid_1),
        .port_request_valid_2     (req_valid_2),
        .port_request_valid_3     (req_valid_3),
        .port_request_packet_0    (req_packet_0),
        .port_request_packet_1    (req_packet_1),
        .port_request_packet_2    (req_packet_2),
        .port_request_packet_3    (req_packet_3),
        .port_request_pc_0        (pc_cpu_0),
        .port_request_pc_1        (pc_cpu_1),
        .port_request_pc_2        (pc_cpu_2),
        .port_request_pc_3        (pc_none),
        .port_stop_0              (stop_0),
        .port_stop_1              (stop_1),
        .port_stop_2              (stop_2),
        .port_stop_3              (port_stop_3),
        .port_request_line_3      (data_from_cpu_3),
        .bank_tracker_free_count  (bk_tracker_free),
        .bank_vec_slot_available  (bk_vec_slot_ok),
        .bank_arrival_request_0   (bk_arrival_req_0),
        .bank_arrival_request_1   (bk_arrival_req_1),
        .bank_arrival_request_2   (bk_arrival_req_2),
        .bank_arrival_request_3   (bk_arrival_req_3),
        .bank_drain_request       (bk_drain_req),
        .bank_drain_packet        (bk_drain_pkt),
        .bank_drain_pc            (bk_drain_pc),
        .bank_arrival_line_data   (bk_arrival_line),
        .bank_arrival_allocated_0 (bk_arrival_alloc_0),
        .bank_arrival_allocated_1 (bk_arrival_alloc_1),
        .bank_arrival_allocated_2 (bk_arrival_alloc_2),
        .bank_arrival_allocated_3 (bk_arrival_alloc_3),
        .bank_drain_allocated     (bk_drain_alloc)
    );
    assign stop_3 = (HAS_VPU != 0) ? port_stop_3 : 1'b1;
    wire [NB-1:0]               bk_resp_valid;
    wire [NB*RESP_W-1:0]        bk_resp;
    wire [NB*LINE_W-1:0]        bk_resp_line;
    wire [NB*RCNT_W-1:0]        resp_free_by_bank_0;
    wire [NB*RCNT_W-1:0]        resp_free_by_bank_1;
    wire [NB*RCNT_W-1:0]        resp_free_by_bank_2;
    wire [NB*RCNT_W-1:0]        resp_free_by_bank_3;
    wire [NB*RCNT_W-1:0]        resp_free_next_by_bank_0;
    wire [NB*RCNT_W-1:0]        resp_free_next_by_bank_1;
    wire [NB*RCNT_W-1:0]        resp_free_next_by_bank_2;
    wire [NB*RCNT_W-1:0]        resp_free_next_by_bank_3;
    wire [NB-1:0]               bk_rsv_event;
    reg  [NB-1:0]               other_rsv_event_q;
    wire [NB-1:0]               pf_hint_valid;
    wire [NB*LINE_ADDR_W-1:0]   pf_hint_line;
    wire [NB-1:0]               pf_hint_unique;
    wire [NB-1:0]               pf_hint_ready;
    wire [NB-1:0]               bk_train_valid;
    wire [NB*PORT_W-1:0]        bk_train_port;
    wire [NB*PC_W-1:0]          bk_train_pc;
    wire [NB*ADDR_W-1:0]        bk_train_addr;
    wire [NB-1:0]               bk_train_is_store;
    wire [NB-1:0]               bk_train_miss;
    wire [NB-1:0]               bk_train_pf_hit;
    wire [NB-1:0]               bk_train_no_train;
    wire [NB-1:0]               bk_evict_valid;
    wire [NB*LINE_ADDR_W-1:0]   bk_evict_line;
    wire [NB-1:0]               bk_pf_fb_valid;
    wire [NB*LINE_ADDR_W-1:0]   bk_pf_fb_line;
    wire [NB*2-1:0]             bk_pf_fb_result;
    wire [NB-1:0]               bk_ecc_ce;
    wire [NB-1:0]               bk_ecc_ue;
    wire [NB-1:0]               bk_rd_valid, bk_rd_ready, bk_rd_nc, bk_rd_unique;
    wire [NB*AXI_ADDR_W-1:0]    bk_rd_addr;
    wire [NB*8-1:0]             bk_rd_len;
    wire [NB*3-1:0]             bk_rd_size;
    wire [NB*AXI_SUBID_W-1:0]   bk_rd_sub;
    wire [NB-1:0]               bk_r_valid;
    wire [AXI_SUBID_W-1:0]      bk_r_sub;
    wire                        bk_r_nc, bk_r_last, bk_r_err, bk_r_shared;
    wire [AXI_DATA_W-1:0]       bk_r_data;
    wire [NB-1:0]               bk_wr_valid, bk_wr_ready, bk_wr_nc;
    wire [NB*AXI_ADDR_W-1:0]    bk_wr_addr;
    wire [NB*8-1:0]             bk_wr_len;
    wire [NB*3-1:0]             bk_wr_size;
    wire [NB*AXI_SUBID_W-1:0]   bk_wr_sub;
    wire [NB*LINE_W-1:0]        bk_wr_data;
    wire [NB*AXI_STRB_W-1:0]    bk_wr_strb;
    wire [NB-1:0]               bk_b_valid;
    wire [AXI_SUBID_W-1:0]      bk_b_sub;
    wire                        bk_b_nc, bk_b_err;
    reg                         mt_start;
    reg                         mt_op;
    wire [NB-1:0]               mt_done;
    wire [NB-1:0]               bk_lock_err;
    wire                        l2_err;
    wire [NB-1:0]               refill_busy;
    wire [NB-1:0]               bk_snp_valid, bk_snp_ready;
    wire [LINE_ADDR_W-1:0]      bk_snp_line;
    wire                        bk_snp_inv;
    wire [NB-1:0]               bk_snpr_valid;
    wire [NB*SNPR_W-1:0]        bk_snpr_pkt;
    wire [NB*SNPR_CNT_W-1:0]    bk_snpr_free;
    genvar b;
    generate
        for (b = 0; b < NB; b = b + 1) begin : g_bank
            l1d_bank #(`L1D_PARAMS_PASS, .BANK_ID(b)) u_bank (
                .clk                          (clk),
                .rst                          (rst),
                .arrival_request_0            (bk_arrival_req_0[b]),
                .arrival_request_1            (bk_arrival_req_1[b]),
                .arrival_request_2            (bk_arrival_req_2[b]),
                .arrival_request_3            (bk_arrival_req_3[b]),
                .arrival_packet_0             (req_packet_0),
                .arrival_packet_1             (req_packet_1),
                .arrival_packet_2             (req_packet_2),
                .arrival_packet_3             (req_packet_3),
                .arrival_pc_0                 (pc_cpu_0),
                .arrival_pc_1                 (pc_cpu_1),
                .arrival_pc_2                 (pc_cpu_2),
                .arrival_pc_3                 (pc_none),
                .drain_request                (bk_drain_req[b]),
                .drain_packet                 (bk_drain_pkt[b*REQ_W +: REQ_W]),
                .drain_pc                     (bk_drain_pc[b*PC_W +: PC_W]),
                .arrival_allocated_0          (bk_arrival_alloc_0[b]),
                .arrival_allocated_1          (bk_arrival_alloc_1[b]),
                .arrival_allocated_2          (bk_arrival_alloc_2[b]),
                .arrival_allocated_3          (bk_arrival_alloc_3[b]),
                .drain_allocated              (bk_drain_alloc[b]),
                .tracker_free_count_q         (bk_tracker_free[b*TRK_CNT_W +: TRK_CNT_W]),
                .vec_slot_available           (bk_vec_slot_ok[b]),
                .lsu_request_line_data        (bk_arrival_line[b*LINE_W +: LINE_W]),
                .lsu_response_valid           (bk_resp_valid[b]),
                .lsu_response_packet          (bk_resp[b*RESP_W +: RESP_W]),
                .lsu_response_line_data       (bk_resp_line[b*LINE_W +: LINE_W]),
                .lsu_response_fifo_free_0     (resp_free_by_bank_0[b*RCNT_W +: RCNT_W]),
                .lsu_response_fifo_free_1     (resp_free_by_bank_1[b*RCNT_W +: RCNT_W]),
                .lsu_response_fifo_free_2     (resp_free_by_bank_2[b*RCNT_W +: RCNT_W]),
                .lsu_response_fifo_free_3     (resp_free_by_bank_3[b*RCNT_W +: RCNT_W]),
                .lsu_response_fifo_free_next_0 (resp_free_next_by_bank_0[b*RCNT_W +: RCNT_W]),
                .lsu_response_fifo_free_next_1 (resp_free_next_by_bank_1[b*RCNT_W +: RCNT_W]),
                .lsu_response_fifo_free_next_2 (resp_free_next_by_bank_2[b*RCNT_W +: RCNT_W]),
                .lsu_response_fifo_free_next_3 (resp_free_next_by_bank_3[b*RCNT_W +: RCNT_W]),
                .snoop_request_valid          (bk_snp_valid[b]),
                .snoop_request_line_addr      (bk_snp_line),
                .snoop_request_invalidate     (bk_snp_inv),
                .snoop_request_ready          (bk_snp_ready[b]),
                .snoop_response_valid         (bk_snpr_valid[b]),
                .snoop_response_packet        (bk_snpr_pkt[b*SNPR_W +: SNPR_W]),
                .snoop_response_fifo_free     (bk_snpr_free[b*SNPR_CNT_W +: SNPR_CNT_W]),
                .prefetch_request_valid       (pf_hint_valid[b]),
                .prefetch_request_line_addr   (pf_hint_line[b*LINE_ADDR_W +: LINE_ADDR_W]),
                .prefetch_request_unique      (pf_hint_unique[b]),
                .prefetch_request_ready       (pf_hint_ready[b]),
                .axi_read_req_valid           (bk_rd_valid[b]),
                .axi_read_req_ready           (bk_rd_ready[b]),
                .axi_read_req_addr            (bk_rd_addr[b*AXI_ADDR_W +: AXI_ADDR_W]),
                .axi_read_req_burst_len       (bk_rd_len[b*8 +: 8]),
                .axi_read_req_size            (bk_rd_size[b*3 +: 3]),
                .axi_read_req_sub_id          (bk_rd_sub[b*AXI_SUBID_W +: AXI_SUBID_W]),
                .axi_read_req_non_cacheable   (bk_rd_nc[b]),
                .axi_read_req_unique          (bk_rd_unique[b]),
                .axi_read_data_valid          (bk_r_valid[b]),
                .axi_read_data_sub_id         (bk_r_sub),
                .axi_read_data_non_cacheable  (bk_r_nc),
                .axi_read_data                (bk_r_data),
                .axi_read_data_last           (bk_r_last),
                .axi_read_data_error          (bk_r_err),
                .axi_read_data_shared         (bk_r_shared),
                .axi_write_req_valid          (bk_wr_valid[b]),
                .axi_write_req_ready          (bk_wr_ready[b]),
                .axi_write_req_addr           (bk_wr_addr[b*AXI_ADDR_W +: AXI_ADDR_W]),
                .axi_write_req_burst_len      (bk_wr_len[b*8 +: 8]),
                .axi_write_req_size           (bk_wr_size[b*3 +: 3]),
                .axi_write_req_sub_id         (bk_wr_sub[b*AXI_SUBID_W +: AXI_SUBID_W]),
                .axi_write_req_non_cacheable  (bk_wr_nc[b]),
                .axi_write_req_data           (bk_wr_data[b*LINE_W +: LINE_W]),
                .axi_write_req_strobe         (bk_wr_strb[b*AXI_STRB_W +: AXI_STRB_W]),
                .axi_write_resp_valid         (bk_b_valid[b]),
                .axi_write_resp_sub_id        (bk_b_sub),
                .axi_write_resp_non_cacheable (bk_b_nc),
                .axi_write_resp_error         (bk_b_err),
                .refill_handover_busy         (refill_busy[b]),
                .maint_start                  (mt_start),
                .maint_op_is_flush            (mt_op),
                .maint_done                   (mt_done[b]),
                .amo_lock_timeout_pulse       (bk_lock_err[b]),
                .rsv_event_pulse              (bk_rsv_event[b]),
                .other_bank_rsv_event         (other_rsv_event_q[b]),
                .train_valid                  (bk_train_valid[b]),
                .train_port                   (bk_train_port[b*PORT_W +: PORT_W]),
                .train_pc                     (bk_train_pc[b*PC_W +: PC_W]),
                .train_addr                   (bk_train_addr[b*ADDR_W +: ADDR_W]),
                .train_is_store               (bk_train_is_store[b]),
                .train_miss                   (bk_train_miss[b]),
                .train_pf_hit                 (bk_train_pf_hit[b]),
                .train_no_train               (bk_train_no_train[b]),
                .evict_valid                  (bk_evict_valid[b]),
                .evict_line_addr              (bk_evict_line[b*LINE_ADDR_W +: LINE_ADDR_W]),
                .pf_fb_valid                  (bk_pf_fb_valid[b]),
                .pf_fb_line_addr              (bk_pf_fb_line[b*LINE_ADDR_W +: LINE_ADDR_W]),
                .pf_fb_result                 (bk_pf_fb_result[b*2 +: 2]),
                .ecc_correctable              (bk_ecc_ce[b]),
                .ecc_uncorrectable            (bk_ecc_ue[b])
            );
        end
    endgenerate
    generate
        if (HAS_PF != 0) begin : g_prefetch
            l1d_prefetch_unit #(`L1D_PARAMS_PASS) u_prefetch (
                .clk              (clk),
                .rst              (rst),
                .pf_enable        (pf_enable),
                .train_valid      (bk_train_valid),
                .train_pc         (bk_train_pc),
                .train_addr       (bk_train_addr),
                .train_is_store   (bk_train_is_store),
                .train_miss       (bk_train_miss),
                .train_pf_hit     (bk_train_pf_hit),
                .train_no_train   (bk_train_no_train),
                .evict_valid      (bk_evict_valid),
                .evict_line_addr  (bk_evict_line),
                .pf_fb_valid      (bk_pf_fb_valid),
                .pf_fb_line_addr  (bk_pf_fb_line),
                .pf_fb_result     (bk_pf_fb_result),
                .pf_req_ready     (pf_hint_ready),
                .pf_req_valid     (pf_hint_valid),
                .pf_req_line_addr (pf_hint_line),
                .pf_req_unique    (pf_hint_unique)
            );
        end else begin : g_no_prefetch
            assign pf_hint_valid  = {NB{1'b0}};
            assign pf_hint_line   = {(NB*LINE_ADDR_W){1'b0}};
            assign pf_hint_unique = {NB{1'b0}};
        end
    endgenerate
    always @(posedge clk) begin : ecc_status_proc
        if (rst) begin
            ecc_correctable_pulse    <= 1'b0;
            ecc_uncorrectable_sticky <= 1'b0;
        end else begin
            ecc_correctable_pulse <= |bk_ecc_ce;
            if (|bk_ecc_ue) ecc_uncorrectable_sticky <= 1'b1;
        end
    end
    l1d_snoop_ctrl #(`L1D_PARAMS_PASS) u_snoop (
        .clk                           (clk),
        .rst                           (rst),
        .snoop_request_valid           (snoop_request_valid),
        .snoop_request_ready           (snoop_request_ready),
        .snoop_request_addr            (snoop_request_addr),
        .snoop_request_invalidate      (snoop_request_invalidate),
        .bank_snoop_valid              (bk_snp_valid),
        .bank_snoop_line_addr          (bk_snp_line),
        .bank_snoop_invalidate         (bk_snp_inv),
        .bank_snoop_ready              (bk_snp_ready),
        .bank_snoop_response_valid     (bk_snpr_valid),
        .bank_snoop_response_packet    (bk_snpr_pkt),
        .bank_snoop_response_fifo_free (bk_snpr_free),
        .snoop_response_valid          (snoop_response_valid),
        .snoop_response_ready          (snoop_response_ready),
        .snoop_response_addr           (snoop_response_addr),
        .snoop_response_present        (snoop_response_present),
        .snoop_response_dirty          (snoop_response_dirty),
        .snoop_response_data           (snoop_response_data)
    );
    localparam VPKT_W = RESP_W + LINE_W;
    localparam [RESP_W-1:0] RESP_DATA_MASK = {{(RESP_W-WRITE_DATA_WIDTH){1'b0}}, {WRITE_DATA_WIDTH{1'b1}}} << RESP_DATA_LSB;
    localparam [RCNT_W-1:0] RESP_FIFO_FULL_FREE = RESP_FIFO_DEPTH;
    wire [NB-1:0]        resp_for_port_0;
    wire [NB-1:0]        resp_for_port_1;
    wire [NB-1:0]        resp_for_port_2;
    wire [NB-1:0]        resp_for_port_3;
    wire [NB*VPKT_W-1:0] vpu_bank_resp;
    genvar route_bank;
    generate
        for (route_bank = 0; route_bank < NB; route_bank = route_bank + 1) begin : g_route
            wire [PORT_W-1:0] answer_port = bk_resp[route_bank*RESP_W + RESP_PORT_LSB +: PORT_W];
            assign resp_for_port_0[route_bank] = bk_resp_valid[route_bank] && (answer_port == 2'd0);
            assign resp_for_port_1[route_bank] = bk_resp_valid[route_bank] && (answer_port == 2'd1);
            assign resp_for_port_2[route_bank] = bk_resp_valid[route_bank] && (answer_port == 2'd2);
            assign resp_for_port_3[route_bank] = bk_resp_valid[route_bank] && (answer_port == 2'd3);
            assign vpu_bank_resp[route_bank*VPKT_W +: VPKT_W] =
                {bk_resp_line[route_bank*LINE_W +: LINE_W], (bk_resp[route_bank*RESP_W +: RESP_W] & ~RESP_DATA_MASK)};
        end
    endgenerate
    wire              merged_valid_0, merged_valid_1, merged_valid_2;
    wire [RESP_W-1:0] merged_packet_0;
    wire [RESP_W-1:0] merged_packet_1;
    wire [RESP_W-1:0] merged_packet_2;
    l1d_resp_merge #(`L1D_PARAMS_PASS) u_merge_0 (
        .clk (clk), .rst (rst),
        .bank_response_valid (resp_for_port_0), .bank_response_packet (bk_resp), .bank_response_fifo_free (resp_free_by_bank_0),
        .bank_response_fifo_free_next (resp_free_next_by_bank_0),
        .merged_response_valid (merged_valid_0), .merged_response_packet (merged_packet_0), .lsu_read_enable (read_enable_from_lsu_0)
    );
    l1d_resp_merge #(`L1D_PARAMS_PASS) u_merge_1 (
        .clk (clk), .rst (rst),
        .bank_response_valid (resp_for_port_1), .bank_response_packet (bk_resp), .bank_response_fifo_free (resp_free_by_bank_1),
        .bank_response_fifo_free_next (resp_free_next_by_bank_1),
        .merged_response_valid (merged_valid_1), .merged_response_packet (merged_packet_1), .lsu_read_enable (read_enable_from_lsu_1)
    );
    l1d_resp_merge #(`L1D_PARAMS_PASS) u_merge_2 (
        .clk (clk), .rst (rst),
        .bank_response_valid (resp_for_port_2), .bank_response_packet (bk_resp), .bank_response_fifo_free (resp_free_by_bank_2),
        .bank_response_fifo_free_next (resp_free_next_by_bank_2),
        .merged_response_valid (merged_valid_2), .merged_response_packet (merged_packet_2), .lsu_read_enable (read_enable_from_lsu_2)
    );
    assign final_r_cache_hit_from_scheduler_0 = merged_valid_0;
    assign final_r_mem_size_from_scheduler_0  = merged_packet_0[RESP_SIZE_LSB +: MEM_SIZE_BITS];
    assign final_r_master_id_from_scheduler_0 = merged_packet_0[RESP_MID_LSB  +: MASTER_ID_BITS];
    assign final_r_idx_from_scheduler_0       = merged_packet_0[RESP_IDX_LSB  +: IDX_BITS];
    assign final_r_data_from_scheduler_0      = merged_packet_0[RESP_DATA_LSB +: WRITE_DATA_WIDTH];
    assign final_r_cache_hit_from_scheduler_1 = merged_valid_1;
    assign final_r_mem_size_from_scheduler_1  = merged_packet_1[RESP_SIZE_LSB +: MEM_SIZE_BITS];
    assign final_r_master_id_from_scheduler_1 = merged_packet_1[RESP_MID_LSB  +: MASTER_ID_BITS];
    assign final_r_idx_from_scheduler_1       = merged_packet_1[RESP_IDX_LSB  +: IDX_BITS];
    assign final_r_data_from_scheduler_1      = merged_packet_1[RESP_DATA_LSB +: WRITE_DATA_WIDTH];
    assign final_r_cache_hit_from_scheduler_2 = merged_valid_2;
    assign final_r_hit_rd_wr_from_scheduler_2 = merged_packet_2[RESP_RDWR_BIT];
    assign final_r_mem_size_from_scheduler_2  = merged_packet_2[RESP_SIZE_LSB +: MEM_SIZE_BITS];
    assign final_r_master_id_from_scheduler_2 = merged_packet_2[RESP_MID_LSB  +: MASTER_ID_BITS];
    assign final_r_idx_from_scheduler_2       = merged_packet_2[RESP_IDX_LSB  +: IDX_BITS];
    assign final_r_data_from_scheduler_2      = merged_packet_2[RESP_DATA_LSB +: WRITE_DATA_WIDTH];
    generate
        if (HAS_VPU != 0) begin : g_vpu_out
            wire              merged_valid_3;
            wire [VPKT_W-1:0] merged_packet_3;
            l1d_resp_merge #(`L1D_PARAMS_PASS, .EXTRA_W(LINE_W)) u_merge_3 (
                .clk (clk), .rst (rst),
                .bank_response_valid (resp_for_port_3), .bank_response_packet (vpu_bank_resp),
                .bank_response_fifo_free (resp_free_by_bank_3),
                .bank_response_fifo_free_next (resp_free_next_by_bank_3),
                .merged_response_valid (merged_valid_3), .merged_response_packet (merged_packet_3),
                .lsu_read_enable (read_enable_from_lsu_3)
            );
            assign final_r_cache_hit_from_scheduler_3 = merged_valid_3;
            assign final_r_hit_rd_wr_from_scheduler_3 = merged_packet_3[RESP_RDWR_BIT];
            assign final_r_master_id_from_scheduler_3 = merged_packet_3[RESP_MID_LSB +: MASTER_ID_BITS];
            assign final_r_idx_from_scheduler_3       = merged_packet_3[RESP_IDX_LSB +: IDX_BITS];
            assign final_r_data_from_scheduler_3      = merged_packet_3[RESP_W +: LINE_W];
        end else begin : g_no_vpu
            assign resp_free_by_bank_3                = {NB{RESP_FIFO_FULL_FREE}};
            assign resp_free_next_by_bank_3           = {NB{RESP_FIFO_FULL_FREE}};
            assign final_r_cache_hit_from_scheduler_3 = 1'b0;
            assign final_r_hit_rd_wr_from_scheduler_3 = 1'b0;
            assign final_r_master_id_from_scheduler_3 = {MASTER_ID_BITS{1'b0}};
            assign final_r_idx_from_scheduler_3       = {IDX_BITS{1'b0}};
            assign final_r_data_from_scheduler_3      = {LINE_W{1'b0}};
        end
    endgenerate
    integer lr_bank;
    always @(posedge clk) begin
        if (rst) other_rsv_event_q <= {NB{1'b0}};
        else
            for (lr_bank = 0; lr_bank < NB; lr_bank = lr_bank + 1)
                other_rsv_event_q[lr_bank] <= |(bk_rsv_event & ~({{(NB-1){1'b0}}, 1'b1} << lr_bank));
    end
    l1d_l2_port #(`L1D_PARAMS_PASS, .L2_ADDR_W(L2_ADDR_W), .L2_MID_W(L2_MID_W), .L2_TID_W(L2_TID_W),
                  .L2_MASTER_ID(L2_MASTER_ID)) u_l2_port (
        .clk                           (clk),
        .rst                           (rst),
        .bank_read_req_valid           (bk_rd_valid),
        .bank_read_req_ready           (bk_rd_ready),
        .bank_read_req_addr            (bk_rd_addr),
        .bank_read_req_burst_len       (bk_rd_len),
        .bank_read_req_size            (bk_rd_size),
        .bank_read_req_sub_id          (bk_rd_sub),
        .bank_read_req_non_cacheable   (bk_rd_nc),
        .bank_read_req_unique          (bk_rd_unique),
        .bank_read_data_valid          (bk_r_valid),
        .bank_read_data_sub_id         (bk_r_sub),
        .bank_read_data_non_cacheable  (bk_r_nc),
        .bank_read_data                (bk_r_data),
        .bank_read_data_last           (bk_r_last),
        .bank_read_data_error          (bk_r_err),
        .bank_read_data_shared         (bk_r_shared),
        .bank_write_req_valid          (bk_wr_valid),
        .bank_write_req_ready          (bk_wr_ready),
        .bank_write_req_addr           (bk_wr_addr),
        .bank_write_req_burst_len      (bk_wr_len),
        .bank_write_req_size           (bk_wr_size),
        .bank_write_req_sub_id         (bk_wr_sub),
        .bank_write_req_non_cacheable  (bk_wr_nc),
        .bank_write_req_data           (bk_wr_data),
        .bank_write_req_strobe         (bk_wr_strb),
        .bank_write_resp_valid         (bk_b_valid),
        .bank_write_resp_sub_id        (bk_b_sub),
        .bank_write_resp_non_cacheable (bk_b_nc),
        .bank_write_resp_error         (bk_b_err),
        .bank_refill_replay_busy       (refill_busy),
        .l2_error_pulse                (l2_err),
        .l2_req_valid                  (l2_req_valid),
        .l2_req_ready                  (l2_req_ready),
        .l2_req_pkt                    (l2_req_pkt),
        .l2_resp_valid                 (l2_resp_valid),
        .l2_resp_ready                 (l2_resp_ready),
        .l2_resp_pkt                   (l2_resp_pkt),
        .l2_resp_err                   (l2_resp_err)
    );
    always @(posedge clk) begin
        if (rst)         mem_err <= 1'b0;
        else if (l2_err) mem_err <= 1'b1;
    end
    always @(posedge clk) begin
        if (rst)               amo_err <= 1'b0;
        else if (|bk_lock_err) amo_err <= 1'b1;
    end
    reg          mt_busy;
    reg [NB-1:0] mt_fin;
    wire [NB-1:0] mt_fin_now = mt_fin | mt_done;
    always @(posedge clk) begin
        if (rst) begin
            mt_busy        <= 1'b0;
            mt_start       <= 1'b0;
            mt_op          <= MAINT_CLEAN;
            mt_fin         <= {NB{1'b0}};
            flush_complete <= 1'b0;
            clean_complete <= 1'b0;
        end else begin
            mt_start       <= 1'b0;
            flush_complete <= 1'b0;
            clean_complete <= 1'b0;
            if (!mt_busy) begin
                if (flush || clean) begin
                    mt_busy  <= 1'b1;
                    mt_start <= 1'b1;
                    mt_op    <= flush ? MAINT_FLUSH : MAINT_CLEAN;
                    mt_fin   <= {NB{1'b0}};
                end
            end else if (&mt_fin_now) begin
                mt_busy        <= 1'b0;
                mt_fin         <= {NB{1'b0}};
                flush_complete <= (mt_op == MAINT_FLUSH);
                clean_complete <= (mt_op == MAINT_CLEAN);
            end else begin
                mt_fin <= mt_fin_now;
            end
        end
    end
`ifdef L1D_DEBUG
    localparam DBG_N = LSU_PORTS * (1 << IDX_BITS);
    reg              dbg_ov [0:DBG_N-1];
    reg              dbg_ow [0:DBG_N-1];
    reg              dbg_oc [0:DBG_N-1];
    reg [ADDR_W-1:0] dbg_oa [0:DBG_N-1];
    integer          dbg_ot [0:DBG_N-1];
    integer          dbg_cyc, dbg_i, dbg_age;
    initial begin
        dbg_cyc = 0;
        for (dbg_i = 0; dbg_i < DBG_N; dbg_i = dbg_i + 1) dbg_ov[dbg_i] = 1'b0;
    end
    task dbg_answer;
        input integer        port_num;
        input                answer_valid;
        input                answer_taken;
        input [IDX_BITS-1:0] answer_idx;
        integer              entry_num;
        begin
            if (answer_valid && answer_taken) begin
                entry_num = port_num * (1 << IDX_BITS) + answer_idx;
                if (!dbg_ov[entry_num])
                    $display("[%0t] L1D TOP  ERROR port %0d response for idx %0d, which is not outstanding", $time, port_num, answer_idx);
                else
                    $display("[%0t] L1D TOP  DONE  port %0d idx=%0d %s %s addr=%h latency=%0d cycles",
                             $time, port_num, answer_idx, (dbg_ow[entry_num] ? "ST" : "LD"), (dbg_oc[entry_num] ? "C " : "NC"),
                             dbg_oa[entry_num], dbg_cyc - dbg_ot[entry_num]);
                dbg_ov[entry_num] = 1'b0;
            end
        end
    endtask
    task dbg_request;
        input integer        port_num;
        input                request_valid;
        input [IDX_BITS-1:0] request_idx;
        input [ADDR_W-1:0]   request_addr;
        input                request_is_write;
        input                request_cacheable;
        integer              entry_num;
        begin
            if (request_valid) begin
                entry_num = port_num * (1 << IDX_BITS) + request_idx;
                if (dbg_ov[entry_num])
                    $display("[%0t] L1D TOP  ERROR port %0d idx %0d reused while still outstanding (old addr %h, issued %0d cycles ago; new addr %h). valid_cpu_N must be 1 for exactly one cycle per request, and an index may be reused only after its response.",
                             $time, port_num, request_idx, dbg_oa[entry_num], dbg_cyc - dbg_ot[entry_num], request_addr);
                dbg_ov[entry_num] = 1'b1;
                dbg_ow[entry_num] = request_is_write;
                dbg_oc[entry_num] = request_cacheable;
                dbg_oa[entry_num] = request_addr;
                dbg_ot[entry_num] = dbg_cyc;
            end
        end
    endtask
    always @(posedge clk) begin
        if (rst) begin
            dbg_cyc = 0;
            for (dbg_i = 0; dbg_i < DBG_N; dbg_i = dbg_i + 1) dbg_ov[dbg_i] = 1'b0;
        end else begin
            dbg_cyc = dbg_cyc + 1;
            dbg_answer(0, final_r_cache_hit_from_scheduler_0, read_enable_from_lsu_0, final_r_idx_from_scheduler_0);
            dbg_answer(1, final_r_cache_hit_from_scheduler_1, read_enable_from_lsu_1, final_r_idx_from_scheduler_1);
            dbg_answer(2, final_r_cache_hit_from_scheduler_2, read_enable_from_lsu_2, final_r_idx_from_scheduler_2);
            dbg_answer(3, final_r_cache_hit_from_scheduler_3, read_enable_from_lsu_3, final_r_idx_from_scheduler_3);
            dbg_request(0, req_valid_0, idx_from_cpu_0, PC_from_cpu_0, 1'b0, cacheable_0);
            dbg_request(1, req_valid_1, idx_from_cpu_1, PC_from_cpu_1, 1'b0, cacheable_1);
            dbg_request(2, req_valid_2, idx_from_cpu_2, PC_from_cpu_2, 1'b1, cacheable_2);
            dbg_request(3, req_valid_3, idx_from_cpu_3, PC_from_cpu_3, rd_wr_cpu_3, 1'b1);
            for (dbg_i = 0; dbg_i < DBG_N; dbg_i = dbg_i + 1) begin
                dbg_age = dbg_cyc - dbg_ot[dbg_i];
                if (dbg_ov[dbg_i] && dbg_age > 0 && (dbg_age % `L1D_DBG_WD) == 0)
                    $display("[%0t] L1D TOP  STUCK port %0d idx=%0d %s %s addr=%h (bank %0d) has waited %0d cycles for its response; stop (ports 3..0)=%b, output valid=%b, read_enable=%b",
                             $time, dbg_i / (1 << IDX_BITS), dbg_i % (1 << IDX_BITS), (dbg_ow[dbg_i] ? "ST" : "LD"), (dbg_oc[dbg_i] ? "C " : "NC"),
                             dbg_oa[dbg_i], dbg_oa[dbg_i][BANK_LSB +: BANK_W], dbg_age,
                             {stop_3, stop_2, stop_1, stop_0},
                             {final_r_cache_hit_from_scheduler_3, final_r_cache_hit_from_scheduler_2, final_r_cache_hit_from_scheduler_1, final_r_cache_hit_from_scheduler_0},
                             {read_enable_from_lsu_3, read_enable_from_lsu_2, read_enable_from_lsu_1, read_enable_from_lsu_0});
            end
            if (!mt_busy && (flush || clean))
                $display("[%0t] L1D TOP  MAINT start %s", $time, flush ? "flush" : "clean");
            if (mt_busy && (flush || clean))
                $display("[%0t] L1D TOP  WARNING flush/clean request ignored: one is already running", $time);
            if (mt_busy && (&mt_fin_now))
                $display("[%0t] L1D TOP  MAINT all banks done", $time);
            if (l2_err && !mem_err)
                $display("[%0t] L1D TOP  ERROR L2 error answer: mem_err set", $time);
        end
    end
`endif
endmodule
`default_nettype wire
