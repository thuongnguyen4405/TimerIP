// =======================================================
// top_module.v
// Full integration top that matches the block diagram:
// APB -> apb_slave -> register -> counter_control -> counter
//                      \-> interrupt (TIER/TISR + tim_int)
// Includes debug halt gating and advanced clear-on-disable
// =======================================================
module top_module #(
    parameter [19:0] BASE_ADDR20 = 20'h40001,
    parameter integer WAIT_STATE  = 1
)(
    input  wire         sys_clk,
    input  wire         rst_n,
    input  wire         debug_mode,

    // APB interface (Timer APB slave)
    input  wire [11:0]  tim_paddr,
    input  wire         tim_psel,
    input  wire         tim_penable,
    input  wire         tim_pwrite,
    input  wire [31:0]  tim_pwdata,
    input  wire [3:0]   tim_pstrb,
    output wire [31:0]  tim_prdata,
    output wire         tim_pready,
    output wire         tim_pslverr,

    // interrupt output
    output wire         interrupt
);

    // Rebuild full 32-bit address using base + 12-bit offset
    wire [31:0] paddr32 = {BASE_ADDR20, tim_paddr};

    // APB slave internal bus
    wire [31:0] reg_addr;
    wire        wr_en, rd_en;
    wire [31:0] wdata_m;
    wire [31:0] rdata_reg;
    wire        error_reg;

    // Register outputs
    wire        timer_en, div_en;
    wire [3:0]  div_val;
    wire        halt_req, halt_ack;
    wire [31:0] tcmp0, tcmp1;
    wire [31:0] tdr0_sw, tdr1_sw;
    wire        tdr0_wr_pulse, tdr1_wr_pulse;

    // Counter signals
    wire        count_tick;
    wire        count_en_gated;
    wire [63:0] cnt64;
    wire [31:0] count_0 = cnt64[31:0];
    wire [31:0] count_1 = cnt64[63:32];

    // Advanced: clear counter when timer_en deasserts (H->L)
    reg timer_en_d;
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) timer_en_d <= 1'b0;
        else        timer_en_d <= timer_en;
    end
    wire clr_counter = timer_en_d & ~timer_en;

    // Interrupt compare value
    wire [63:0] tcmp64 = {tcmp1, tcmp0};

    // interrupt selects (write pulses)
    wire tisr_wr_sel = wr_en & (reg_addr[11:0] == 12'h018);
    wire tier_wr_sel = wr_en & (reg_addr[11:0] == 12'h014);

    // Read mux: reg file owns most; interrupt owns TIER/TISR
    wire [31:0] rdata_int;
    wire [31:0] rdata_mux = ((reg_addr[11:0] == 12'h014) || (reg_addr[11:0] == 12'h018)) ? rdata_int : rdata_reg;

    // Error mux: include reg errors only (can extend)
    wire error_mux = error_reg;

    // ---------------------------------------------------
    // Instantiate APB slave
    // ---------------------------------------------------
    apb_slave #(
        .WIDTH_REG(32),
        .BASE_ADDR20(BASE_ADDR20),
        .WAIT_STATE(WAIT_STATE)
    ) u_apb (
        .clk     (sys_clk),
        .rst_n   (rst_n),
        .psel    (tim_psel),
        .penable (tim_penable),
        .pwrite  (tim_pwrite),
        .paddr   (paddr32),
        .pwdata  (tim_pwdata),
        .pstrb   (tim_pstrb),
        .prdata  (tim_prdata),
        .pready  (tim_pready),
        .pslverr (tim_pslverr),
        .addr    (reg_addr),
        .wr_en   (wr_en),
        .rd_en   (rd_en),
        .wdata   (wdata_m),
        .rdata   (rdata_mux),
        .error   (error_mux)
    );

    // ---------------------------------------------------
    // Register file
    // ---------------------------------------------------
    register u_reg (
        .clk          (sys_clk),
        .rst_n        (rst_n),
        .db_mode      (debug_mode),
        .addr         (reg_addr),
        .wr_en        (wr_en),
        .rd_en        (rd_en),
        .wdata        (wdata_m),
        .rdata        (rdata_reg),
        .error        (error_reg),
        .timer_en     (timer_en),
        .div_en       (div_en),
        .div_val      (div_val),
        .halt_req     (halt_req),
        .halt_ack     (halt_ack),
        .tcmp0        (tcmp0),
        .tcmp1        (tcmp1),
        .tdr0_sw      (tdr0_sw),
        .tdr1_sw      (tdr1_sw),
        .tdr0_wr_pulse(tdr0_wr_pulse),
        .tdr1_wr_pulse(tdr1_wr_pulse),
        .count_0      (count_0),
        .count_1      (count_1)
    );

    // ---------------------------------------------------
    // Counter control
    // ---------------------------------------------------
    counter_control u_ctl (
        .clk      (sys_clk),
        .rst_n    (rst_n),
        .div_en   (div_en),
        .timer_en (timer_en),
        .div_val  (div_val),
        .count_en (count_tick)
    );

    // debug halt gating: if debug_mode & halt_req => stop counting
    assign count_en_gated = count_tick & ~(debug_mode & halt_req);

    // ---------------------------------------------------
    // Counter
    // SW writes load counter with wdata from APB
    // ---------------------------------------------------
    counter u_cnt (
        .clk        (sys_clk),
        .rst_n      (rst_n),
        .wdata      (wdata_m),
        .cnt_en     (count_en_gated),
        .clr        (clr_counter),
        .tdr0_wr_sel(tdr0_wr_pulse),
        .tdr1_wr_sel(tdr1_wr_pulse),
        .cnt        (cnt64)
    );

    // ---------------------------------------------------
    // Interrupt block
    // ---------------------------------------------------
    interrupt u_int (
        .clk        (sys_clk),
        .rst_n      (rst_n),
        .wdata      (wdata_m),
        .cnt        (cnt64),
        .tcmp       (tcmp64),
        .tisr_wr_sel(tisr_wr_sel),
        .tier_wr_sel(tier_wr_sel),
        .addr       (reg_addr[11:0]),
        .psel       (tim_psel),
        .pwrite     (tim_pwrite),
        .penable    (tim_penable),
        .tim_int    (interrupt),
        .rdata      (rdata_int)
    );

endmodule
