module interrupt(
    input        clk, 
    input        rst_n, 
    input [31:0] wdata, 
    input [63:0] cnt, 
    input [63:0] tcmp, 
    input        tisr_wr_sel, 
    input        tier_wr_sel, 
    input [11:0] addr, 
    input        psel, 
    input        pwrite, 
    input        penable, 
    output       tim_int, 
    output reg [31:0] rdata
);

    reg [31:0] TISR; 
    reg        int_en;
    reg        int_st; 
    wire       int_set, int_clr, select_signal; 

    // TIER register - Timer Interrupt Enable
    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin 
            int_en <= 1'b0;
        end else if (tier_wr_sel) begin 
            int_en <= wdata[0];
        end 
    end 

    // Compare match detection
    assign int_set = (cnt == tcmp); 
    
    // Interrupt clear - write 1 to clear
    assign int_clr = tisr_wr_sel & (wdata[0] == 1'b1);

    // Interrupt status flag
    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin 
            int_st <= 1'b0;
        end else if (int_clr) begin 
            int_st <= 1'b0;
        end else if (int_set) begin 
            int_st <= 1'b1;
        end 
    end 

    // Timer interrupt output
    assign tim_int = int_en & int_st; 
    
    // TISR register - Timer Interrupt Status Register
    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin 
            TISR <= 32'h0;
        end else begin
            TISR <= 32'h0;
            TISR[0] <= int_st;
        end
    end 

    // APB read interface
    assign select_signal = psel & (~pwrite) & penable; 
    
    always @(*) begin 
        if (select_signal) begin
            case (addr)
                12'h018 : rdata = TISR;        // TISR at 0x18
                12'h010 : rdata = {31'h0, int_en}; // TIER at 0x10
                default : rdata = 32'h0;
            endcase 
        end else begin
            rdata = 32'h0;
        end
    end 

endmodule