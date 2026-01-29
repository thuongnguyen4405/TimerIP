module register( 
    input wire          clk, 
    input wire          rst_n, 
    input wire          db_mode,

    output wire         tim_int, 
// APB interface connection
    input wire  [31:0]  addr, 
    input wire          wr_en, 
    input wire          rd_en, 
    input wire  [31:0]  wdata,
    output wire [31:0]  rdata, 
    output wire         error, 
// coounter control connection 
    output wire         timer_en,
    output wire         div_en,
    output wire [3:0]   div_val, 
    output wire         halt, 
// counter connection 
    input wire  [31:0]  count_0,
    input wire  [31:0]  count_1,
    output reg  [31:0]  tdr0,
    output reg  [31:0]  tdr1 
);

parameter TCR      = 12'h000;    // timer control register
parameter TDR0     = 12'h004;    // timer Data reg 0
parameter TDR1     = 12'h008;    // timer data reg 1 
parameter TCMP0    = 12'h00C;    // timer comapre reg 0 
parameter TCMP1    = 12'h010;    // timer compare reg 1 
parameter TIER     = 12'h014;    // timer interrupt enable register  
parameter TISR     = 12'h018;    // timer interrupt status register 
parameter THCRS    = 12'h01C;    // timer halt control status register 

// define default value 
parameter DEFAULT_TCR        =  32'h0000_0001;
parameter DEFAULT_TDR0       =  32'h0000_0000;
parameter DEFAULT_TDR1       =  32'h0000_0000;
parameter DEFAULT_TCMP0      =  32'hffff_ffff;
parameter DEFAULT_TCMP1      =  32'hffff_ffff;
parameter DEFAULT_TIER       =  32'h0000_0000;
parameter DEFAULT_TISR       =  32'h0000_0000;
parameter DEFAULT_THCRS      =  32'h0000_0000;

// declare signal 
reg [31:0] tcr, tcmp0, tcmp1, tier, tisr, thcsr, rdata_reg; 
reg [7:0]  reg_sel;
reg        error_reg;

// decoder -> address -> reg_sel;
always @(*) begin 
    if (!rst_n) 
        reg_sel = 8'h00;
    else begin 
        case(addr[11:0])
            TCR     : reg_sel = 8'b00000001;
            TDR0    : reg_sel = 8'b00000010;
            TDR1    : reg_sel = 8'b00000100;
            TCMP0   : reg_sel = 8'b00001000;
            TCMP1   : reg_sel = 8'b00010000;
            TIER    : reg_sel = 8'b00100000;
            TISR    : reg_sel = 8'b01000000;
            THCRS   : reg_sel = 8'b10000000;
            default : reg_sel = 8'b00000000;
        endcase
    end 
end 

// check condition 
always @(*) begin
    if (wr_en & reg_sel[0]) begin 
        error_reg = (wdata[11:8] > 4'h8);
    end else begin 
        error_reg = 1'b0;
    end 
end 

// TCR register
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin 
        tcr <= DEFAULT_TCR;
    end else if (wr_en & reg_sel[0] & ~error_reg) begin 
        tcr[11:0] <= wdata[11:0];
        tcr[31:12] <= 20'b0;
    end else begin 
        tcr <= tcr;
    end 
end 

// TDR0 register
always @(posedge clk or negedge rst_n) begin 
    if (!rst_n) begin 
        tdr0 <= DEFAULT_TDR0;
    end else if (wr_en & reg_sel[1]) begin 
        tdr0 <= wdata;
    end else begin 
        tdr0 <= count_0;
    end 
end 

// TDR1 register
always @(posedge clk or negedge rst_n) begin 
    if (!rst_n) begin 
        tdr1 <= DEFAULT_TDR1;
    end else if (wr_en & reg_sel[2]) begin 
        tdr1 <= wdata;
    end else begin 
        tdr1 <= count_1;
    end 
end 

// TCMP0 register
always @(posedge clk or negedge rst_n) begin 
    if (!rst_n) begin 
        tcmp0 <= DEFAULT_TCMP0;
    end else if (wr_en & reg_sel[3]) begin 
        tcmp0 <= wdata;
    end else begin 
        tcmp0 <= tcmp0;
    end 
end 

// TCMP1 register
always @(posedge clk or negedge rst_n) begin 
    if (!rst_n) begin 
        tcmp1 <= DEFAULT_TCMP1;
    end else if (wr_en & reg_sel[4]) begin 
        tcmp1 <= wdata;
    end else begin 
        tcmp1 <= tcmp1;
    end 
end 

// TIER register
always @(posedge clk or negedge rst_n) begin 
    if (!rst_n) begin 
        tier <= DEFAULT_TIER;
    end else if (wr_en & reg_sel[5]) begin 
        tier <= wdata;
    end else begin 
        tier <= tier;
    end 
end 

// TISR register
always @(posedge clk or negedge rst_n) begin 
    if (!rst_n) begin 
        tisr <= DEFAULT_TISR;
    end else if (wr_en & reg_sel[6]) begin 
        tisr <= wdata;
    end else begin 
        tisr <= tisr;
    end 
end 

// THCRS register
always @(posedge clk or negedge rst_n) begin 
    if (!rst_n) begin 
        thcsr <= DEFAULT_THCRS;
    end else if (wr_en & reg_sel[7]) begin 
        thcsr <= wdata;
    end else begin 
        thcsr <= thcsr;
    end 
end 

// Halt logic
always @(*) begin 
    thcsr[1] = thcsr[0] & db_mode;
end 

// READ ACCESS 
always @(*) begin 
    if (rd_en) begin 
        case (1'b1)
            reg_sel[0]: rdata_reg = tcr;
            reg_sel[1]: rdata_reg = tdr0;
            reg_sel[2]: rdata_reg = tdr1;
            reg_sel[3]: rdata_reg = tcmp0;
            reg_sel[4]: rdata_reg = tcmp1;
            reg_sel[5]: rdata_reg = tier;
            reg_sel[6]: rdata_reg = tisr;
            reg_sel[7]: rdata_reg = thcsr;
            default:    rdata_reg = 32'h00000000;
        endcase 
    end else begin
        rdata_reg = 32'h00000000;
    end
end 

// output 
assign rdata = rdata_reg;
assign error = error_reg; 

//output to counter controller
assign timer_en = tcr[0];
assign div_en   = tcr[1];
assign div_val  = tcr[11:8];

// Halt signal
assign halt = thcsr[0];

// interrupt output
assign tim_int = tier[0] & tisr[0];

endmodule