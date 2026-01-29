
//------------------------------------------------------------------------------
// Timer IP Top Module (APB slave)
// Top module name per spec: master_apb
//
// This file integrates the user's RTL blocks:
//   - register.v         : register bank + basic control outputs
//   - counter_control.v  : counter enable generation
//   - counter.v          : 64-bit counter
//   - interupt.v         : interrupt set/clear + output (compare match)
//
// Notes
//  - Address map uses 12-bit APB address (offset) as described in the project PDF.
//  - Optional 1-cycle wait-state is supported via parameter WAIT_STATE.
//------------------------------------------------------------------------------
// Timescale is intentionally omitted here (leave to simulation compile options).
//------------------------------------------------------------------------------

module master_apb #(
    parameter integer WAIT_STATE = 1,              // 0: zero-wait APB, 1: 1-cycle wait (hold PSEL/PENABLE)
    parameter [19:0]  BASE_ADDR20 = 20'h40001       // 0x4000_1000 >> 12 = 0x40001 (spec base)
)(
    input  wire        sys_clk,
    input  wire        sys_rst_n,     // active-low async reset

    // APB (Timer is APB slave)
    input  wire        tim_psel,
    input  wire        tim_pwrite,
    input  wire        tim_penable,
    input  wire [11:0] tim_paddr,
    input  wire [31:0] tim_pwdata,
    output wire [31:0] tim_prdata,
    input  wire [3:0]  tim_pstrb,
    output wire        tim_pready,
    output wire        tim_pslverr,

    // Interrupt + debug
    output wire        tim_int,
    input  wire        dbg_mode
);

    // -------------------------------------------------------------------------
    // Register offsets (12-bit)
    // -------------------------------------------------------------------------
    localparam [11:0] TCR   = 12'h000;
    localparam [11:0] TDR0  = 12'h004;
    localparam [11:0] TDR1  = 12'h008;
    localparam [11:0] TCMP0 = 12'h00C;
    localparam [11:0] TCMP1 = 12'h010;
    localparam [11:0] TIER  = 12'h014;
    localparam [11:0] TISR  = 12'h018;
    localparam [11:0] THCSR = 12'h01C;

    // -------------------------------------------------------------------------
    // Local helpers
    // -------------------------------------------------------------------------
    function [31:0] apply_strb;
        input [31:0] data;
        input [3:0]  strb;
        begin
            // NOTE: This follows the "mask to zero" behavior (not "merge with old data").
            apply_strb = { (strb[3] ? data[31:24] : 8'h00),
                           (strb[2] ? data[23:16] : 8'h00),
                           (strb[1] ? data[15:8]  : 8'h00),
                           (strb[0] ? data[7:0]   : 8'h00) };
        end
    endfunction

    // -------------------------------------------------------------------------
    // APB ready / handshake (simple)
    // -------------------------------------------------------------------------
    wire apb_enable = tim_psel & tim_penable;

    reg pready_r;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            pready_r <= 1'b0;
        end else if (WAIT_STATE == 0) begin
            pready_r <= 1'b1;
        end else begin
            // 1-cycle wait-state: ready is a registered version of enable-phase
            pready_r <= apb_enable;
        end
    end

    assign tim_pready = (WAIT_STATE == 0) ? 1'b1 : pready_r;

    wire apb_xfer = apb_enable & tim_pready;
    wire apb_wr   = apb_xfer &  tim_pwrite;
    wire apb_rd   = apb_xfer & ~tim_pwrite;

    wire [31:0] apb_addr32 = {BASE_ADDR20, tim_paddr};
    wire [31:0] apb_wdata  = apply_strb(tim_pwdata, tim_pstrb);

    // Address decode (offset only)
    wire is_tier  = (tim_paddr == TIER);
    wire is_tisr  = (tim_paddr == TISR);
    wire is_tcmp0 = (tim_paddr == TCMP0);
    wire is_tcmp1 = (tim_paddr == TCMP1);
    wire is_tdr0  = (tim_paddr == TDR0);
    wire is_tdr1  = (tim_paddr == TDR1);

    // -------------------------------------------------------------------------
    // Shadow compare registers for interrupt module (since compare regs are
    // internal to register.v and not exposed as ports).
    // -------------------------------------------------------------------------
    reg [31:0] tcmp0_shadow;
    reg [31:0] tcmp1_shadow;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            tcmp0_shadow <= 32'hFFFF_FFFF;
            tcmp1_shadow <= 32'hFFFF_FFFF;
        end else begin
            if (apb_wr && is_tcmp0) tcmp0_shadow <= apb_wdata;
            if (apb_wr && is_tcmp1) tcmp1_shadow <= apb_wdata;
        end
    end

    wire [63:0] tcmp_shadow = {tcmp1_shadow, tcmp0_shadow};

    // -------------------------------------------------------------------------
    // Register block instance
    //   - Keep TIER/TISR ownership in interrupt module -> block writes to these
    //     offsets toward register.v to avoid duplicate (and incorrect) storage.
    // -------------------------------------------------------------------------
    wire        reg_timer_en;
    wire        reg_div_en;
    wire [3:0]  reg_div_val;
    wire        reg_halt_req;
    wire [31:0] reg_rdata;
    wire        reg_error;
    wire [31:0] reg_tdr0;
    wire [31:0] reg_tdr1;
    wire        reg_tim_int_unused;

    wire reg_wr_en = apb_wr & ~(is_tier | is_tisr);
    wire reg_rd_en = apb_rd;

    // Counter value split for register block
    wire [63:0] cnt64;
    wire [31:0] cnt_lo = cnt64[31:0];
    wire [31:0] cnt_hi = cnt64[63:32];

    register u_reg (
        .clk     (sys_clk),
        .rst_n   (sys_rst_n),
        .db_mode (dbg_mode),

        .tim_int (reg_tim_int_unused),

        .addr    (apb_addr32),
        .wr_en   (reg_wr_en),
        .rd_en   (reg_rd_en),
        .wdata   (apb_wdata),
        .rdata   (reg_rdata),
        .error   (reg_error),

        .timer_en(reg_timer_en),
        .div_en  (reg_div_en),
        .div_val (reg_div_val),
        .halt    (reg_halt_req),

        .count_0 (cnt_lo),
        .count_1 (cnt_hi),
        .tdr0    (reg_tdr0),
        .tdr1    (reg_tdr1)
    );

    // -------------------------------------------------------------------------
    // Counter enable generation + debug halt gating
    // -------------------------------------------------------------------------
    wire cnt_en_raw;

    counter_control u_cnt_ctl (
        .clk      (sys_clk),
        .rst_n    (sys_rst_n),
        .div_en   (reg_div_en),
        .timer_en (reg_timer_en),
        .div_val  (reg_div_val),
        .count_en (cnt_en_raw)
    );

    wire halted = dbg_mode & reg_halt_req;
    wire cnt_en = cnt_en_raw & ~halted;

    // -------------------------------------------------------------------------
    // Counter instance
    // -------------------------------------------------------------------------
    wire tdr0_wr_sel = apb_wr & is_tdr0;
    wire tdr1_wr_sel = apb_wr & is_tdr1;

    counter u_counter (
        .clk         (sys_clk),
        .rst_n       (sys_rst_n),
        .wdata       (apb_wdata),
        .cnt_en      (cnt_en),
        .tdr0_wr_sel (tdr0_wr_sel),
        .tdr1_wr_sel (tdr1_wr_sel),
        .cnt         (cnt64)
    );

    // -------------------------------------------------------------------------
    // Interrupt module instance
    //   - Owns TIER/TISR behavior + tim_int output.
    //   - TIER address remap: PDF uses 0x14, interrupt RTL uses 0x10.
    // -------------------------------------------------------------------------
    wire tier_wr_sel = apb_wr & is_tier;
    wire tisr_wr_sel = apb_wr & is_tisr;

    wire [11:0] int_addr = (tim_paddr == TIER) ? 12'h010 : tim_paddr;
    wire [31:0] int_rdata;

    interrupt u_int (
        .clk         (sys_clk),
        .rst_n       (sys_rst_n),
        .wdata       (apb_wdata),
        .cnt         (cnt64),
        .tcmp        (tcmp_shadow),
        .tisr_wr_sel (tisr_wr_sel),
        .tier_wr_sel (tier_wr_sel),
        .addr        (int_addr),
        .psel        (tim_psel),
        .pwrite      (tim_pwrite),
        .penable     (tim_penable),
        .tim_int     (tim_int),
        .rdata       (int_rdata)
    );

    // -------------------------------------------------------------------------
    // APB read data mux
    // -------------------------------------------------------------------------
    wire [31:0] rd_mux = (is_tier | is_tisr) ? int_rdata : reg_rdata;
    assign tim_prdata = (apb_rd) ? rd_mux : 32'h0000_0000;

    // -------------------------------------------------------------------------
    // APB slave error (simple)
    //   - Use register block's error (invalid div_val in TCR write)
    // -------------------------------------------------------------------------
    assign tim_pslverr = apb_xfer & reg_error;

endmodule


//------------------------------------------------------------------------------
// Optional wrapper name (diagram uses timer_top)
//------------------------------------------------------------------------------
module timer_top #(
    parameter integer WAIT_STATE = 1,
    parameter [19:0]  BASE_ADDR20 = 20'h40001
)(
    input  wire        sys_clk,
    input  wire        rst_n,
    input  wire        debug_mode,

    input  wire        tim_psel,
    input  wire        tim_pwrite,
    input  wire        tim_penable,
    input  wire [11:0] tim_paddr,
    input  wire [31:0] tim_pwdata,
    output wire [31:0] tim_prdata,
    input  wire [3:0]  tim_pstrb,
    output wire        tim_pready,
    output wire        tim_pslverr,
    output wire        interrupt
);

    master_apb #(
        .WAIT_STATE (WAIT_STATE),
        .BASE_ADDR20(BASE_ADDR20)
    ) u_dut (
        .sys_clk    (sys_clk),
        .sys_rst_n  (rst_n),

        .tim_psel   (tim_psel),
        .tim_pwrite (tim_pwrite),
        .tim_penable(tim_penable),
        .tim_paddr  (tim_paddr),
        .tim_pwdata (tim_pwdata),
        .tim_prdata (tim_prdata),
        .tim_pstrb  (tim_pstrb),
        .tim_pready (tim_pready),
        .tim_pslverr(tim_pslverr),

        .tim_int    (interrupt),
        .dbg_mode   (debug_mode)
    );

endmodule
