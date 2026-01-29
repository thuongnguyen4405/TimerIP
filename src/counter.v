module counter(
    input  wire        clk,
    input  wire        rst_n,

    // bus interface
    input  wire [31:0] wdata,
    input  wire        cnt_en,        // enable counter + snapshot
    input  wire        tdr0_wr_sel,   // write enable tdr0
    input  wire        tdr1_wr_sel,   // write enable tdr1

    output wire [63:0] cnt             // 64-bit counter output
);

    // Internal registers
    reg [63:0] cnt_r;   // real 64-bit counter
    reg [31:0] tdr0;    // lower 32-bit storage
    reg [31:0] tdr1;    // upper 32-bit storage

    // 64-bit free-running counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt_r <= 64'd0;
        else if (cnt_en)
            cnt_r <= cnt_r + 64'd1;
    end

    // TDR0 : snapshot / bus write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tdr0 <= 32'd0;
        else if (tdr0_wr_sel) begin
            if (cnt_en)
                tdr0 <= cnt_r[31:0];   // snapshot lower 32-bit
            else
                tdr0 <= wdata;         // CPU write
        end
    end

    // TDR1 : snapshot / bus write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tdr1 <= 32'd0;
        else if (tdr1_wr_sel) begin
            if (cnt_en)
                tdr1 <= cnt_r[63:32];  // snapshot upper 32-bit
            else
                tdr1 <= wdata;         // CPU write
        end
    end

    // Output counter
    assign cnt = cnt_r;

endmodule