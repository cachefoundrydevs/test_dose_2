`default_nettype none
`include "l1d_defines.vh"
module l1d_top_axi_ports #(
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
    parameter AXI_ID_W         = 6,
    parameter LSU_PORTS        = `L1D_LSU_PORTS,
    parameter HAS_MISS         = `L1D_HAS_MISS,
    parameter HAS_VC           = `L1D_HAS_VC,
    parameter HAS_NC           = `L1D_HAS_NC,
    parameter HAS_VPU          = 0,
    parameter BRIDGE_SLOTS     = 16
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         flush_request,
    input  wire                         clean_request,
    output wire                         flush_complete,
    output wire                         clean_complete,
    input  wire [LSU_PORTS-1:0]                  cpu_request_valid,
    input  wire [LSU_PORTS-1:0]                  cpu_request_cacheable,
    input  wire [LSU_PORTS-1:0]                  cpu_request_is_write,
    input  wire [LSU_PORTS*MEM_SIZE_BITS-1:0]    cpu_request_size,
    input  wire [LSU_PORTS*MASTER_ID_BITS-1:0]   cpu_request_master_id,
    input  wire [LSU_PORTS*IDX_BITS-1:0]         cpu_request_rob_index,
    input  wire [LSU_PORTS*ADDR_W-1:0]           cpu_request_addr,
    input  wire [LSU_PORTS*WRITE_DATA_WIDTH-1:0] cpu_request_store_data,
    input  wire [LSU_PORTS-1:0]                  cpu_request_is_atomic,
    input  wire [LSU_PORTS-1:0]                  cpu_request_atomic_is_amo,
    input  wire [LSU_PORTS*4-1:0]                cpu_request_amo_op,
    output wire [LSU_PORTS-1:0]                  input_queue_full,
    input  wire [LSU_PORTS-1:0]                  lsu_response_read_enable,
    output wire [LSU_PORTS-1:0]                  lsu_response_valid,
    output wire [LSU_PORTS-1:0]                  lsu_response_is_write_ack,
    output wire [LSU_PORTS*MEM_SIZE_BITS-1:0]    lsu_response_size,
    output wire [LSU_PORTS*MASTER_ID_BITS-1:0]   lsu_response_master_id,
    output wire [LSU_PORTS*IDX_BITS-1:0]         lsu_response_rob_index,
    output wire [LSU_PORTS*WRITE_DATA_WIDTH-1:0] lsu_response_data,
    input  wire                         vpu_req_valid,
    input  wire                         vpu_req_is_write,
    input  wire                         vpu_req_cacheable,
    input  wire [MASTER_ID_BITS-1:0]    vpu_req_master_id,
    input  wire [IDX_BITS-1:0]          vpu_req_rob_index,
    input  wire [ADDR_W-1:0]            vpu_req_addr,
    input  wire [LINE_BYTES*8-1:0]      vpu_req_wdata,
    output wire                         vpu_req_stop,
    input  wire                         vpu_resp_read_enable,
    output wire                         vpu_resp_valid,
    output wire                         vpu_resp_is_write_ack,
    output wire [MASTER_ID_BITS-1:0]    vpu_resp_master_id,
    output wire [IDX_BITS-1:0]          vpu_resp_rob_index,
    output wire [LINE_BYTES*8-1:0]      vpu_resp_data,
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
    output wire                         axi_error_sticky,
    output wire                         amo_lock_timeout_sticky,
    output wire [AXI_ID_W-1:0]          m_axi_awid,
    output wire [AXI_ADDR_W-1:0]        m_axi_awaddr,
    output wire [7:0]                   m_axi_awlen,
    output wire [2:0]                   m_axi_awsize,
    output wire [1:0]                   m_axi_awburst,
    output wire [3:0]                   m_axi_awcache,
    output wire [2:0]                   m_axi_awprot,
    output wire                         m_axi_awvalid,
    input  wire                         m_axi_awready,
    output wire [AXI_DATA_W-1:0]        m_axi_wdata,
    output wire [AXI_DATA_W/8-1:0]      m_axi_wstrb,
    output wire                         m_axi_wlast,
    output wire                         m_axi_wvalid,
    input  wire                         m_axi_wready,
    input  wire [AXI_ID_W-1:0]          m_axi_bid,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,
    output wire                         m_axi_bready,
    output wire [AXI_ID_W-1:0]          m_axi_arid,
    output wire [AXI_ADDR_W-1:0]        m_axi_araddr,
    output wire [7:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output wire [1:0]                   m_axi_arburst,
    output wire [3:0]                   m_axi_arcache,
    output wire [2:0]                   m_axi_arprot,
    output wire                         m_axi_aruser,
    output wire                         m_axi_arvalid,
    input  wire                         m_axi_arready,
    input  wire [AXI_ID_W-1:0]          m_axi_rid,
    input  wire [AXI_DATA_W-1:0]        m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_ruser,
    input  wire                         m_axi_rvalid,
    output wire                         m_axi_rready,
    output wire [BRIDGE_SLOTS-1:0]            rd_pend_valid,
    output wire [BRIDGE_SLOTS*AXI_ADDR_W-1:0] rd_pend_addr
);
    localparam L2_ADDR_W = 56;
    localparam L2_TID_W  = 6;
    localparam L2_PKT_W  = 1 + L2_ADDR_W + 1 + 2 + L2_TID_W + 1 + LINE_BYTES + LINE_BYTES*8;
    initial if (AXI_ID_W < L2_TID_W)
        $display("ERROR l1d_top_axi: AXI_ID_W = %0d is below the packet tid width %0d", AXI_ID_W, L2_TID_W);
    wire                l2_req_valid, l2_req_ready, l2_resp_valid, l2_resp_ready, l2_resp_err;
    wire [L2_PKT_W-1:0] l2_req_pkt, l2_resp_pkt;
    wire                        ld0_stop, ld1_stop, st_stop;
    wire                        ld0_rsp_valid, ld1_rsp_valid, st_rsp_valid;
    wire                        st_rsp_ack;
    wire [MEM_SIZE_BITS-1:0]    ld0_rsp_size, ld1_rsp_size, st_rsp_size;
    wire [MASTER_ID_BITS-1:0]   ld0_rsp_mid,  ld1_rsp_mid,  st_rsp_mid;
    wire [IDX_BITS-1:0]         ld0_rsp_idx,  ld1_rsp_idx,  st_rsp_idx;
    wire [WRITE_DATA_WIDTH-1:0] ld0_rsp_data, ld1_rsp_data, st_rsp_data;
    assign input_queue_full          = {vpu_req_stop, st_stop, ld1_stop, ld0_stop};
    assign lsu_response_valid        = {1'b0, st_rsp_valid, ld1_rsp_valid, ld0_rsp_valid};
    assign lsu_response_is_write_ack = {1'b0, st_rsp_ack, 1'b0, 1'b0};
    assign lsu_response_size         = {{MEM_SIZE_BITS{1'b0}}, st_rsp_size, ld1_rsp_size, ld0_rsp_size};
    assign lsu_response_master_id    = {{MASTER_ID_BITS{1'b0}}, st_rsp_mid, ld1_rsp_mid, ld0_rsp_mid};
    assign lsu_response_rob_index    = {{IDX_BITS{1'b0}}, st_rsp_idx, ld1_rsp_idx, ld0_rsp_idx};
    assign lsu_response_data         = {{WRITE_DATA_WIDTH{1'b0}}, st_rsp_data, ld1_rsp_data, ld0_rsp_data};
    initial if (LSU_PORTS != 4)
        $display("ERROR l1d_top_axi_ports: LSU_PORTS = %0d, the typed ports need 4", LSU_PORTS);
    always @(posedge clk) begin
        if (!rst) begin
            if (cpu_request_valid[0] && (cpu_request_is_write[0] || (cpu_request_is_atomic[0] && cpu_request_atomic_is_amo[0])))
                $display("[%0t] ERROR l1d_top_axi_ports: port 0 (ld0) carries only loads and LR, a store / SC / AMO was sent", $time);
            if (cpu_request_valid[1] && (cpu_request_is_write[1] || (cpu_request_is_atomic[1] && cpu_request_atomic_is_amo[1])))
                $display("[%0t] ERROR l1d_top_axi_ports: port 1 (ld1) carries only loads and LR, a store / SC / AMO was sent", $time);
            if (cpu_request_valid[2] && !cpu_request_is_write[2] && !(cpu_request_is_atomic[2] && cpu_request_atomic_is_amo[2]))
                $display("[%0t] ERROR l1d_top_axi_ports: port 2 (st) carries only stores, SC and AMO, a load / LR was sent", $time);
            if (cpu_request_valid[3])
                $display("[%0t] ERROR l1d_top_axi_ports: port 3 is the VPU port, a scalar request was sent on it", $time);
        end
    end
    wire [`L1D_PC_W-1:0] pc_none;
    wire                 prefetch_on;
    assign pc_none     = {`L1D_PC_W{1'b0}};
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
        .L2_ADDR_W(L2_ADDR_W), .L2_TID_W(L2_TID_W),
        .LSU_PORTS(LSU_PORTS), .HAS_MISS(HAS_MISS), .HAS_VC(HAS_VC), .HAS_NC(HAS_NC), .HAS_VPU(HAS_VPU)
    ) u_dcache (
        .clk(clk), .rst(rst),
        .flush(flush_request), .clean(clean_request), .flush_complete(flush_complete), .clean_complete(clean_complete),
        .valid_cpu_0(cpu_request_valid[0]), .cacheable_0(cpu_request_cacheable[0]),
        .mem_size_cpu_0(cpu_request_size[0*MEM_SIZE_BITS +: MEM_SIZE_BITS]), .master_id_from_cpu_0(cpu_request_master_id[0*MASTER_ID_BITS +: MASTER_ID_BITS]),
        .idx_from_cpu_0(cpu_request_rob_index[0*IDX_BITS +: IDX_BITS]), .PC_from_cpu_0(cpu_request_addr[0*ADDR_W +: ADDR_W]),
        .is_lr_cpu_0(cpu_request_is_atomic[0]), .stop_0(ld0_stop),
        .valid_cpu_1(cpu_request_valid[1]), .cacheable_1(cpu_request_cacheable[1]),
        .mem_size_cpu_1(cpu_request_size[1*MEM_SIZE_BITS +: MEM_SIZE_BITS]), .master_id_from_cpu_1(cpu_request_master_id[1*MASTER_ID_BITS +: MASTER_ID_BITS]),
        .idx_from_cpu_1(cpu_request_rob_index[1*IDX_BITS +: IDX_BITS]), .PC_from_cpu_1(cpu_request_addr[1*ADDR_W +: ADDR_W]),
        .is_lr_cpu_1(cpu_request_is_atomic[1]), .stop_1(ld1_stop),
        .valid_cpu_2(cpu_request_valid[2]), .cacheable_2(cpu_request_cacheable[2]),
        .mem_size_cpu_2(cpu_request_size[2*MEM_SIZE_BITS +: MEM_SIZE_BITS]), .master_id_from_cpu_2(cpu_request_master_id[2*MASTER_ID_BITS +: MASTER_ID_BITS]),
        .idx_from_cpu_2(cpu_request_rob_index[2*IDX_BITS +: IDX_BITS]), .PC_from_cpu_2(cpu_request_addr[2*ADDR_W +: ADDR_W]),
        .data_from_cpu_2(cpu_request_store_data[2*WRITE_DATA_WIDTH +: WRITE_DATA_WIDTH]),
        .is_sc_cpu_2(cpu_request_is_atomic[2] && !cpu_request_atomic_is_amo[2]),
        .is_amo_cpu_2(cpu_request_is_atomic[2] && cpu_request_atomic_is_amo[2]),
        .amo_op_cpu_2(cpu_request_amo_op[2*4 +: 4]), .stop_2(st_stop),
        .valid_cpu_3(vpu_req_valid), .rd_wr_cpu_3(vpu_req_is_write), .cacheable_3(vpu_req_cacheable),
        .master_id_from_cpu_3(vpu_req_master_id), .idx_from_cpu_3(vpu_req_rob_index), .PC_from_cpu_3(vpu_req_addr),
        .data_from_cpu_3(vpu_req_wdata), .stop_3(vpu_req_stop),
        .pc_cpu_0(pc_none), .pc_cpu_1(pc_none), .pc_cpu_2(pc_none), .pf_enable(prefetch_on),
        .ecc_correctable_pulse(), .ecc_uncorrectable_sticky(),
        .read_enable_from_lsu_0(lsu_response_read_enable[0]), .final_r_cache_hit_from_scheduler_0(ld0_rsp_valid),
        .final_r_mem_size_from_scheduler_0(ld0_rsp_size), .final_r_master_id_from_scheduler_0(ld0_rsp_mid),
        .final_r_idx_from_scheduler_0(ld0_rsp_idx), .final_r_data_from_scheduler_0(ld0_rsp_data),
        .read_enable_from_lsu_1(lsu_response_read_enable[1]), .final_r_cache_hit_from_scheduler_1(ld1_rsp_valid),
        .final_r_mem_size_from_scheduler_1(ld1_rsp_size), .final_r_master_id_from_scheduler_1(ld1_rsp_mid),
        .final_r_idx_from_scheduler_1(ld1_rsp_idx), .final_r_data_from_scheduler_1(ld1_rsp_data),
        .read_enable_from_lsu_2(lsu_response_read_enable[2]), .final_r_cache_hit_from_scheduler_2(st_rsp_valid),
        .final_r_hit_rd_wr_from_scheduler_2(st_rsp_ack), .final_r_mem_size_from_scheduler_2(st_rsp_size),
        .final_r_master_id_from_scheduler_2(st_rsp_mid), .final_r_idx_from_scheduler_2(st_rsp_idx),
        .final_r_data_from_scheduler_2(st_rsp_data),
        .read_enable_from_lsu_3(vpu_resp_read_enable), .final_r_cache_hit_from_scheduler_3(vpu_resp_valid),
        .final_r_hit_rd_wr_from_scheduler_3(vpu_resp_is_write_ack), .final_r_master_id_from_scheduler_3(vpu_resp_master_id),
        .final_r_idx_from_scheduler_3(vpu_resp_rob_index), .final_r_data_from_scheduler_3(vpu_resp_data),
        .snoop_request_valid(snoop_request_valid), .snoop_request_ready(snoop_request_ready), .snoop_request_addr(snoop_request_addr),
        .snoop_request_invalidate(snoop_request_invalidate),
        .snoop_response_valid(snoop_response_valid), .snoop_response_ready(snoop_response_ready), .snoop_response_addr(snoop_response_addr),
        .snoop_response_present(snoop_response_present), .snoop_response_dirty(snoop_response_dirty), .snoop_response_data(snoop_response_data),
        .mem_err(axi_error_sticky), .amo_err(amo_lock_timeout_sticky),
        .l2_req_valid(l2_req_valid), .l2_req_ready(l2_req_ready), .l2_req_pkt(l2_req_pkt),
        .l2_resp_valid(l2_resp_valid), .l2_resp_ready(l2_resp_ready), .l2_resp_pkt(l2_resp_pkt), .l2_resp_err(l2_resp_err)
    );
    l2_pkt_axi_bridge #(.ADDR_W(L2_ADDR_W), .TID_W(L2_TID_W), .DATA_W(LINE_BYTES*8), .AXI_ADDR_W(AXI_ADDR_W),
                        .AXI_DATA_W(AXI_DATA_W), .ID_HAS_MID(0), .AXI_ID_W(AXI_ID_W), .N_OUT(BRIDGE_SLOTS)) u_bridge (
        .clk(clk), .rst(rst),
        .req_valid(l2_req_valid), .req_pkt(l2_req_pkt), .req_ready(l2_req_ready),
        .resp_ready(l2_resp_ready), .resp_valid(l2_resp_valid), .resp_pkt(l2_resp_pkt), .resp_err(l2_resp_err),
        .m_axi_awready(m_axi_awready), .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid), .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid), .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_ruser(m_axi_ruser),
        .m_axi_awid(m_axi_awid), .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awcache(m_axi_awcache), .m_axi_awprot(m_axi_awprot), .m_axi_awvalid(m_axi_awvalid),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arcache(m_axi_arcache), .m_axi_arprot(m_axi_arprot), .m_axi_aruser(m_axi_aruser),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_rready(m_axi_rready),
        .rd_pend_valid(rd_pend_valid), .rd_pend_addr(rd_pend_addr)
    );
endmodule
`default_nettype wire
