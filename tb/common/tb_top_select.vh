`ifndef TB_TOP_SELECT_VH
`define TB_TOP_SELECT_VH
`ifdef L1D_SINGLE_PORT_TOP
`define L1D_TB_TOP l1d_top_single_port_axi
`else
`define L1D_TB_TOP l1d_top_axi
`endif
`endif
