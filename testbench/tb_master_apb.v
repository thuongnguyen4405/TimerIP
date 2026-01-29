
`timescale 1ns/1ps
//------------------------------------------------------------------------------
// Basic Verilog Testbench for TIMER IP (master_apb)
// - Uses APB tasks (write/read)
// - Self-checking with simple error counter
// - Focus: register access, counter enable/disable, debug halt, interrupt flow
//------------------------------------------------------------------------------

module tb_master_apb;

    // Clock / reset
    reg sys_clk;
    reg sys_rst_n;

    // APB signals
    reg         tim_psel;
    reg         tim_pwrite;
    reg         tim_penable;
    reg [11:0]  tim_paddr;
    reg [31:0]  tim_pwdata;
    wire [31:0] tim_prdata;
    reg [3:0]   tim_pstrb;
    wire        tim_pready;
    wire        tim_pslverr;

    // Debug / interrupt
    reg  dbg_mode;
    wire tim_int;

    // DUT
    master_apb #(
        .WAIT_STATE(1)
    ) dut (
        .sys_clk     (sys_clk),
        .sys_rst_n   (sys_rst_n),

        .tim_psel    (tim_psel),
        .tim_pwrite  (tim_pwrite),
        .tim_penable (tim_penable),
        .tim_paddr   (tim_paddr),
        .tim_pwdata  (tim_pwdata),
        .tim_prdata  (tim_prdata),
        .tim_pstrb   (tim_pstrb),
        .tim_pready  (tim_pready),
        .tim_pslverr (tim_pslverr),

        .tim_int     (tim_int),
        .dbg_mode    (dbg_mode)
    );

    // Register offsets
    localparam [11:0] TCR   = 12'h000;
    localparam [11:0] TDR0  = 12'h004;
    localparam [11:0] TDR1  = 12'h008;
    localparam [11:0] TCMP0 = 12'h00C;
    localparam [11:0] TCMP1 = 12'h010;
    localparam [11:0] TIER  = 12'h014;
    localparam [11:0] TISR  = 12'h018;
    localparam [11:0] THCSR = 12'h01C;

    // Expected reset default for TCR differs between PDF spec and current RTL.
    // Compile with +define+USE_PDF_DEFAULTS (or -DUSE_PDF_DEFAULTS) to use PDF defaults.
`ifdef USE_PDF_DEFAULTS
    localparam [31:0] TCR_RST_EXPECT = 32'h0000_0100; // div_val=1, div_en=0, timer_en=0
`else
    localparam [31:0] TCR_RST_EXPECT = 32'h0000_0001; // matches provided RTL register.v
`endif


    integer error_cnt;

    // 200 MHz clock (5ns period)
    initial begin
        sys_clk = 1'b0;
        forever #2.5 sys_clk = ~sys_clk;
    end

    //-------------------------------------------------------------------------
    // APB tasks
    //-------------------------------------------------------------------------
    task apb_idle;
        begin
            tim_psel    = 1'b0;
            tim_penable = 1'b0;
            tim_pwrite  = 1'b0;
            tim_paddr   = 12'h000;
            tim_pwdata  = 32'h0;
            tim_pstrb   = 4'h0;
        end
    endtask

    task apb_write;
        input  [11:0] addr;
        input  [31:0] data;
        input  [3:0]  strb;
        output        slverr;
        begin
            // SETUP phase
            @(negedge sys_clk);
            tim_paddr   <= addr;
            tim_pwdata  <= data;
            tim_pstrb   <= strb;
            tim_pwrite  <= 1'b1;
            tim_psel    <= 1'b1;
            tim_penable <= 1'b0;

            // ENABLE phase
            @(negedge sys_clk);
            tim_penable <= 1'b1;

            // Wait for ready (support wait state)
            while (!tim_pready) @(negedge sys_clk);

            // Sample error at transfer completion
            slverr = tim_pslverr;

            // Return to IDLE
            @(negedge sys_clk);
            apb_idle();
        end
    endtask

    task apb_write32;
        input  [11:0] addr;
        input  [31:0] data;
        output        slverr;
        begin
            apb_write(addr, data, 4'hF, slverr);
        end
    endtask

    task apb_read;
        input  [11:0] addr;
        output [31:0] data;
        begin
            // SETUP
            @(negedge sys_clk);
            tim_paddr   <= addr;
            tim_pwrite  <= 1'b0;
            tim_pstrb   <= 4'h0;
            tim_pwdata  <= 32'h0;
            tim_psel    <= 1'b1;
            tim_penable <= 1'b0;

            // ENABLE
            @(negedge sys_clk);
            tim_penable <= 1'b1;

            // Wait ready
            while (!tim_pready) @(negedge sys_clk);

            // Sample data at transfer completion
            data = tim_prdata;

            // IDLE
            @(negedge sys_clk);
            apb_idle();
        end
    endtask

    task check_read32;
        input [11:0] addr;
        input [31:0] exp;
        reg   [31:0] got;
        begin
            apb_read(addr, got);
            if (got !== exp) begin
                $display("[%0t] ERROR: READ addr=0x%0h exp=0x%08h got=0x%08h", $time, addr, exp, got);
                error_cnt = error_cnt + 1;
            end else begin
                $display("[%0t] INFO : READ addr=0x%0h = 0x%08h (OK)", $time, addr, got);
            end
        end
    endtask

    // Helper: read 64-bit counter via TDR1:TDR0
    task read_counter64;
        output [63:0] cnt;
        reg [31:0] lo, hi;
        begin
            apb_read(TDR0, lo);
            apb_read(TDR1, hi);
            cnt = {hi, lo};
        end
    endtask

    //-------------------------------------------------------------------------
    // Test sequence
    //-------------------------------------------------------------------------
    initial begin
        error_cnt = 0;

        // Default
        apb_idle();
        dbg_mode  = 1'b0;

        // Apply reset
        sys_rst_n = 1'b0;
        repeat (5) @(negedge sys_clk);
        sys_rst_n = 1'b1;
        repeat (2) @(negedge sys_clk);

        $display("------------------------------------------------------------");
        $display("TEST 1: Reset default values");
        $display("------------------------------------------------------------");
        // NOTE: These expected defaults match the provided RTL (not the PDF).
        check_read32(TCR,   TCR_RST_EXPECT);
        check_read32(TDR0,  32'h0000_0000);
        check_read32(TDR1,  32'h0000_0000);
        check_read32(TCMP0, 32'hFFFF_FFFF);
        check_read32(TCMP1, 32'hFFFF_FFFF);
        check_read32(TIER,  32'h0000_0000);
        check_read32(TISR,  32'h0000_0000);
        check_read32(THCSR, 32'h0000_0000);

        $display("------------------------------------------------------------");
        $display("TEST 2: Basic register write/read");
        $display("------------------------------------------------------------");
        begin : t2
            reg slv;
            // TCR: div_val=2, div_en=1, timer_en=1
            apb_write32(TCR, 32'h0000_0203, slv);
            if (slv) begin
                $display("[%0t] ERROR: unexpected PSLVERR during valid TCR write", $time);
                error_cnt = error_cnt + 1;
            end
            check_read32(TCR, 32'h0000_0203);

            // TCMP0/1: program compare
            apb_write32(TCMP0, 32'h0000_0010, slv);
            apb_write32(TCMP1, 32'h0000_0000, slv);
            check_read32(TCMP0, 32'h0000_0010);
            check_read32(TCMP1, 32'h0000_0000);

            // THCSR: request halt (dbg_mode=0 -> ack should stay 0)
            apb_write32(THCSR, 32'h0000_0001, slv);
            check_read32(THCSR, 32'h0000_0001);

            // TIER: enable interrupt
            apb_write32(TIER, 32'h0000_0001, slv);
            check_read32(TIER, 32'h0000_0001);

            // Reserved read-as-zero
            check_read32(12'h020, 32'h0000_0000);
        end

        $display("------------------------------------------------------------");
        $display("TEST 3: Counter run / stop by timer_en");
        $display("------------------------------------------------------------");
        begin : t3
            reg slv;
            reg [63:0] c0, c1, c2;

            // Enable counting: div_en=1, timer_en=1, div_val=1
            apb_write32(TCR, 32'h0000_0103, slv);

            read_counter64(c0);
            repeat (20) @(negedge sys_clk);
            read_counter64(c1);

            if (c1 <= c0) begin
                $display("[%0t] ERROR: counter did not increment (c0=%0d c1=%0d)", $time, c0, c1);
                error_cnt = error_cnt + 1;
            end else begin
                $display("[%0t] INFO : counter incremented (c0=%0d c1=%0d)", $time, c0, c1);
            end

            // Disable timer_en -> counter should stop
            apb_write32(TCR, 32'h0000_0102, slv); // timer_en=0
            read_counter64(c0);
            repeat (20) @(negedge sys_clk);
            read_counter64(c1);

            if (c1 !== c0) begin
                $display("[%0t] ERROR: counter changed while disabled (c0=%0d c1=%0d)", $time, c0, c1);
                error_cnt = error_cnt + 1;
            end else begin
                $display("[%0t] INFO : counter stopped as expected", $time);
            end

            // Re-enable
            apb_write32(TCR, 32'h0000_0103, slv);
            repeat (10) @(negedge sys_clk);
            read_counter64(c2);
            if (c2 <= c1) begin
                $display("[%0t] ERROR: counter did not resume (c1=%0d c2=%0d)", $time, c1, c2);
                error_cnt = error_cnt + 1;
            end else begin
                $display("[%0t] INFO : counter resumed (c1=%0d c2=%0d)", $time, c1, c2);
            end
        end

        $display("------------------------------------------------------------");
        $display("TEST 4: Debug halt (dbg_mode + halt_req)");
        $display("------------------------------------------------------------");
        begin : t4
            reg slv;
            reg [63:0] c0, c1;

            dbg_mode = 1'b1;

            // Request halt
            apb_write32(THCSR, 32'h0000_0001, slv);
            // With dbg_mode=1, provided register RTL sets ack=halt_req => expect 0x3
            check_read32(THCSR, 32'h0000_0003);

            read_counter64(c0);
            repeat (20) @(negedge sys_clk);
            read_counter64(c1);

            if (c1 !== c0) begin
                $display("[%0t] ERROR: counter changed during debug halt (c0=%0d c1=%0d)", $time, c0, c1);
                error_cnt = error_cnt + 1;
            end else begin
                $display("[%0t] INFO : counter halted as expected", $time);
            end

            // Release halt
            apb_write32(THCSR, 32'h0000_0000, slv);
            check_read32(THCSR, 32'h0000_0000);

            repeat (20) @(negedge sys_clk);
            read_counter64(c1);
            if (c1 <= c0) begin
                $display("[%0t] ERROR: counter did not resume after halt release", $time);
                error_cnt = error_cnt + 1;
            end else begin
                $display("[%0t] INFO : counter resumed after halt release", $time);
            end

            dbg_mode = 1'b0;
        end

        $display("------------------------------------------------------------");
        $display("TEST 5: Interrupt (compare match + RW1C clear)");
        $display("------------------------------------------------------------");
        begin : t5
            reg slv;
            reg [63:0] now_cnt, cmp_cnt;
            reg [31:0] tisr;
            integer timeout;

            // Ensure not halted and counting
            dbg_mode = 1'b0;
            apb_write32(THCSR, 32'h0, slv);
            apb_write32(TCR, 32'h0000_0103, slv); // div_en=1, timer_en=1

            // Enable interrupt
            apb_write32(TIER, 32'h0000_0001, slv);

            // Program compare = current_count + 10
            read_counter64(now_cnt);
            cmp_cnt = now_cnt + 64'd10;

            apb_write32(TCMP0, cmp_cnt[31:0], slv);
            apb_write32(TCMP1, cmp_cnt[63:32], slv);

            // Wait for tim_int
            timeout = 0;
            while ((tim_int !== 1'b1) && (timeout < 5000)) begin
                @(negedge sys_clk);
                timeout = timeout + 1;
            end
            if (tim_int !== 1'b1) begin
                $display("[%0t] ERROR: tim_int did not assert before timeout", $time);
                error_cnt = error_cnt + 1;
            end else begin
                $display("[%0t] INFO : tim_int asserted", $time);
            end

            // Read TISR should show pending
            apb_read(TISR, tisr);
            if (tisr[0] !== 1'b1) begin
                $display("[%0t] ERROR: TISR[0] not set after interrupt (TISR=0x%08h)", $time, tisr);
                error_cnt = error_cnt + 1;
            end

            // Clear interrupt by writing 1 to TISR[0] (RW1C behavior in interrupt RTL)
            apb_write32(TISR, 32'h0000_0001, slv);
            repeat (5) @(negedge sys_clk);

            if (tim_int !== 1'b0) begin
                $display("[%0t] ERROR: tim_int did not deassert after clear", $time);
                error_cnt = error_cnt + 1;
            end

            apb_read(TISR, tisr);
            if (tisr[0] !== 1'b0) begin
                $display("[%0t] ERROR: TISR[0] not cleared (TISR=0x%08h)", $time, tisr);
                error_cnt = error_cnt + 1;
            end
        end

        $display("------------------------------------------------------------");
        $display("TEST 6: Error response (invalid div_val)");
        $display("------------------------------------------------------------");
        begin : t6
            reg slv;
            reg [31:0] tcr_before, tcr_after;

            apb_read(TCR, tcr_before);

            // Attempt div_val=9 -> expect PSLVERR and TCR not updated
            apb_write32(TCR, 32'h0000_0903, slv); // div_val=9 (>8)
            if (!slv) begin
                $display("[%0t] ERROR: expected PSLVERR on invalid div_val write", $time);
                error_cnt = error_cnt + 1;
            end else begin
                $display("[%0t] INFO : PSLVERR asserted as expected on invalid div_val", $time);
            end

            apb_read(TCR, tcr_after);
            if (tcr_after !== tcr_before) begin
                $display("[%0t] ERROR: TCR changed despite error (before=0x%08h after=0x%08h)", $time, tcr_before, tcr_after);
                error_cnt = error_cnt + 1;
            end
        end

        $display("------------------------------------------------------------");
        if (error_cnt == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("TESTS FAILED: %0d errors", error_cnt);
        end
        $display("------------------------------------------------------------");

        #50;
        $finish;
    end

endmodule
