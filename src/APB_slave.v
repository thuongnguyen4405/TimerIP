module apb_slave#(parameter width_reg = 32
)(
    input wire clk, 
    input wire                   rst_n, 
    input wire                   psel, 
    input wire                   pwrite, 
    input wire                   penable, 
    input wire  [width_reg:0]           addr, 
    input wire  [width_reg-1:0]  pwdata, 
    input wire  [width_reg-1:0]  prdata,
    input wire  [3:0]            pstrb,
    input wire                   pready, 
    input wire                   pslver, 
    // connecting register
    input wire  [31:0]           rdata, 
    input wire                   error, 
    output wire [31:0]           reg_addr, 
    output wire                  wr_en, 
    output wire                  rd_en, 
    output wire [31:0]           wdata
 );


 // signal declaration 
 reg pready_reg;

 // define register address

 assign base_addr = addr [31:12]; 
 assign reg_addr  = addr [11:0]; 

 // write access 

assign wr_en = psel & penable & pwrite & (base_addr == 20'h4_001);
assign wdata[7:0]    = pstrb[0]   ? wdata[7:0]     : 8'h00;
assign wdata[15:8]   = pstrb[1]   ? wdata[15:8]    : 8'h00;
assign wdata[23:16]  = pstrb[2]   ? wdata[23:16]   : 8'h00;
assign wdata[31:24]  = pstrb[3]   ? wdata[31:24]   : 8'h00;

 // read access : 
assign rd_en = psel & pwrite & penable & (base_addr == 20'h4_001);
assign rdata = (rd_en &(reg_addr <64)) ? prdata : 32'h0; // RAZ for reserved area 

// pready 
always @(posedge clk or negedge rst_n) begin 
    if (!rst_n) begin 
        pready_reg <= 1'b0; 
    end else begin
        pready_reg <= psel & penable; 
    end 
end 
assign pready = pready_reg; 

// slave error;
assign pslver = pready & error;

endmodule