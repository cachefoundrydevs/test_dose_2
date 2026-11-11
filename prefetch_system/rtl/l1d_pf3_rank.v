`ifndef L1D_PF3_RANK_V
`define L1D_PF3_RANK_V
`default_nettype none
module l1d_pf3_rank #(
    parameter NB              = 4,
    parameter LINE_W          = 58,
    parameter HOLD_MAX        = 2,
    parameter CREDIT_PER_BANK = 2,
    parameter CREDIT_WAIT_MAX = 64
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 pf_enable,
    input  wire [NB-1:0]        pf_req_ready,
    input  wire                 s_valid,
    input  wire [LINE_W-1:0]    s_line,
    input  wire [NB-1:0]        s_bank,
    input  wire                 s_unique,
    input  wire                 t_valid,
    input  wire [LINE_W-1:0]    t_line,
    input  wire [NB-1:0]        t_bank,
    input  wire                 t_unique,
    input  wire                 m_valid,
    input  wire [LINE_W-1:0]    m_line,
    input  wire [NB-1:0]        m_bank,
    input  wire [NB-1:0]        fb_valid,
    output wire                 t_held,
    output wire                 m_held,
    output reg  [NB-1:0]        pf_req_valid,
    output reg  [NB*LINE_W-1:0] pf_req_line,
    output reg  [NB-1:0]        pf_req_unique
);
    localparam HOLD_W = $clog2(HOLD_MAX + 1);
    localparam CRED_W = $clog2(CREDIT_PER_BANK + 1);
    localparam WAIT_W = $clog2(CREDIT_WAIT_MAX + 1);
    localparam [HOLD_W-1:0] HOLD_ONE  = 1;
    localparam [HOLD_W-1:0] HOLD_LAST = HOLD_MAX - 1;
    localparam [CRED_W-1:0] CRED_MAX  = CREDIT_PER_BANK;
    localparam [WAIT_W-1:0] WAIT_LAST = CREDIT_WAIT_MAX;
    reg                  s_hold_vld;
    reg  [LINE_W-1:0]    s_hold_line;
    reg  [NB-1:0]        s_hold_bank;
    reg                  s_hold_uniq;
    reg  [HOLD_W-1:0]    s_hold_cnt;
    reg                  t_hold_vld;
    reg  [LINE_W-1:0]    t_hold_line;
    reg  [NB-1:0]        t_hold_bank;
    reg                  t_hold_uniq;
    reg  [HOLD_W-1:0]    t_hold_cnt;
    reg                  m_hold_vld;
    reg  [LINE_W-1:0]    m_hold_line;
    reg  [NB-1:0]        m_hold_bank;
    reg  [HOLD_W-1:0]    m_hold_cnt;
    reg  [NB*CRED_W-1:0] credit_q;
    reg  [NB-1:0]        credit_ok_q;
    reg  [WAIT_W-1:0]    wait_q;
    reg  [NB*CRED_W-1:0] credit_next;
    reg  [CRED_W-1:0]    one_credit;
    wire                 s_off;
    wire [LINE_W-1:0]    s_off_line;
    wire [NB-1:0]        s_off_bank;
    wire                 s_off_uniq;
    wire [HOLD_W-1:0]    s_off_cnt;
    wire                 t_off;
    wire [LINE_W-1:0]    t_off_line;
    wire [NB-1:0]        t_off_bank;
    wire                 t_off_uniq;
    wire [HOLD_W-1:0]    t_off_cnt;
    wire                 m_off;
    wire [LINE_W-1:0]    m_off_line;
    wire [NB-1:0]        m_off_bank;
    wire [HOLD_W-1:0]    m_off_cnt;
    wire [NB-1:0]        s_want;
    wire [NB-1:0]        t_want;
    wire [NB-1:0]        m_want;
    wire [NB-1:0]        s_win;
    wire [NB-1:0]        t_win;
    wire [NB-1:0]        m_win;
    wire                 s_taken;
    wire                 t_taken;
    wire                 m_taken;
    wire                 t_dup;
    wire                 m_dup;
    wire                 s_keep;
    wire                 t_keep;
    wire                 m_keep;
    wire                 m_waits;
    wire                 m_timeout;
    reg  [NB-1:0]        valid_next;
    reg  [NB*LINE_W-1:0] line_next;
    reg  [NB-1:0]        unique_next;
    reg  [LINE_W-1:0]    tm_line;
    integer              bank_idx;
    assign s_off      = s_valid | s_hold_vld;
    assign s_off_line = s_valid ? s_line : s_hold_line;
    assign s_off_bank = s_valid ? s_bank : (s_hold_bank & {NB{s_hold_vld}});
    assign s_off_uniq = s_valid ? s_unique : s_hold_uniq;
    assign s_off_cnt  = s_valid ? {HOLD_W{1'b0}} : s_hold_cnt;
    assign t_off      = t_valid | t_hold_vld;
    assign t_off_line = t_valid ? t_line : t_hold_line;
    assign t_off_bank = t_valid ? t_bank : (t_hold_bank & {NB{t_hold_vld}});
    assign t_off_uniq = t_valid ? t_unique : t_hold_uniq;
    assign t_off_cnt  = t_valid ? {HOLD_W{1'b0}} : t_hold_cnt;
    assign m_off      = m_valid | m_hold_vld;
    assign m_off_line = m_valid ? m_line : m_hold_line;
    assign m_off_bank = m_valid ? m_bank : (m_hold_bank & {NB{m_hold_vld}});
    assign m_off_cnt  = m_valid ? {HOLD_W{1'b0}} : m_hold_cnt;
    assign s_want = s_off_bank & {NB{pf_enable}};
    assign t_want = t_off_bank & {NB{pf_enable}};
    assign m_want = m_off_bank & credit_ok_q & {NB{pf_enable}};
    assign s_win  = s_want & pf_req_ready;
    assign t_win  = t_want & pf_req_ready & ~s_want;
    assign m_win  = m_want & pf_req_ready & ~s_want & ~t_want;
    assign s_taken = |s_win;
    assign t_taken = |t_win;
    assign m_taken = |m_win;
    always @* begin : out_next_proc
        for (bank_idx = 0; bank_idx < NB; bank_idx = bank_idx + 1) begin
            valid_next[bank_idx] = s_win[bank_idx] | t_win[bank_idx]
                                   | m_win[bank_idx];
            tm_line = t_want[bank_idx] ? t_off_line : m_off_line;
            line_next[bank_idx*LINE_W +: LINE_W] =
                s_want[bank_idx] ? s_off_line : tm_line;
            unique_next[bank_idx] = s_want[bank_idx] ? s_off_uniq
                                    : (t_want[bank_idx] & t_off_uniq);
        end
    end
    always @(posedge clk) begin : out_reg_proc
        if (rst) begin
            pf_req_valid  <= {NB{1'b0}};
            pf_req_unique <= {NB{1'b0}};
        end
        else begin
            pf_req_valid  <= valid_next;
            pf_req_unique <= unique_next;
        end
        pf_req_line <= line_next;
    end
    assign t_dup = s_off & t_off & (s_off_line == t_off_line);
    assign m_dup = m_off & ((s_off & (s_off_line == m_off_line))
                            | (t_off & (t_off_line == m_off_line)));
    assign s_keep = s_off & ~s_taken & (s_off_cnt != HOLD_LAST);
    assign t_keep = t_off & ~t_taken & ~t_dup & (t_off_cnt != HOLD_LAST);
    assign m_keep = m_off & ~m_taken & ~m_dup
                    & (m_waits | (m_off_cnt != HOLD_LAST));
    always @(posedge clk) begin : hold_ctl_proc
        if (rst || !pf_enable) begin
            s_hold_vld <= 1'b0;
            t_hold_vld <= 1'b0;
            m_hold_vld <= 1'b0;
        end
        else begin
            s_hold_vld <= s_keep;
            t_hold_vld <= t_keep;
            m_hold_vld <= m_keep;
        end
        s_hold_cnt <= s_off_cnt + HOLD_ONE;
        t_hold_cnt <= t_off_cnt + HOLD_ONE;
        m_hold_cnt <= m_waits ? m_off_cnt : (m_off_cnt + HOLD_ONE);
    end
    always @(posedge clk) begin : hold_data_proc
        if (s_valid) begin
            s_hold_line <= s_line;
            s_hold_bank <= s_bank;
            s_hold_uniq <= s_unique;
        end
        if (t_valid) begin
            t_hold_line <= t_line;
            t_hold_bank <= t_bank;
            t_hold_uniq <= t_unique;
        end
        if (m_valid) begin
            m_hold_line <= m_line;
            m_hold_bank <= m_bank;
        end
    end
    assign t_held = t_hold_vld;
    assign m_held = m_hold_vld;
    assign m_waits   = m_off & ~(|(m_off_bank & credit_ok_q)) & pf_enable;
    assign m_timeout = m_waits & (wait_q == WAIT_LAST);
    always @* begin : credit_next_proc
        for (bank_idx = 0; bank_idx < NB; bank_idx = bank_idx + 1) begin
            one_credit = credit_q[bank_idx*CRED_W +: CRED_W];
            if (m_win[bank_idx] && !(fb_valid[bank_idx]
                                     && (one_credit != {CRED_W{1'b0}}))) begin
                one_credit = one_credit + 1'b1;
            end
            else if (!m_win[bank_idx] && fb_valid[bank_idx]
                     && (one_credit != {CRED_W{1'b0}})) begin
                one_credit = one_credit - 1'b1;
            end
            if (m_timeout) begin
                one_credit = {CRED_W{1'b0}};
            end
            credit_next[bank_idx*CRED_W +: CRED_W] = one_credit;
        end
    end
    always @(posedge clk) begin : credit_proc
        if (rst) begin
            credit_q    <= {(NB*CRED_W){1'b0}};
            credit_ok_q <= {NB{1'b1}};
            wait_q      <= {WAIT_W{1'b0}};
        end
        else begin
            credit_q <= credit_next;
            for (bank_idx = 0; bank_idx < NB; bank_idx = bank_idx + 1) begin
                credit_ok_q[bank_idx] <=
                    (credit_next[bank_idx*CRED_W +: CRED_W] < CRED_MAX);
            end
            if (m_waits && !m_timeout) begin
                wait_q <= wait_q + 1'b1;
            end
            else begin
                wait_q <= {WAIT_W{1'b0}};
            end
        end
    end
`ifdef L1D_DEBUG
    always @(posedge clk) begin : debug_proc
        if (!rst) begin
            if (t_valid && t_hold_vld) begin
                $display("[%0t] L1D PF3_RANK ERROR stream offer while held",
                         $time);
            end
            if (m_valid && m_hold_vld) begin
                $display("[%0t] L1D PF3_RANK ERROR SMS offer while held",
                         $time);
            end
            if ((s_win & t_win) != {NB{1'b0}} || (s_win & m_win) != {NB{1'b0}}
                || (t_win & m_win) != {NB{1'b0}}) begin
                $display("[%0t] L1D PF3_RANK ERROR two winners for a bank",
                         $time);
            end
        end
    end
`endif
endmodule
`default_nettype wire
`endif
