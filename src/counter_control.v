module counter_control #(parameter CNT_W = 8)(
    input wire clk, 
    input wire rst_n, 
    input wire div_en, 
    input wire timer_en, 
    input wire [3:0] div_val, 
    output wire count_en
); 
    
    reg [CNT_W-1:0] int_cnt; 
    reg [CNT_W-1:0] limit;

    wire control_default, control_mode_other, control_mode0; 
    wire cnt_rst; 
    wire reach_limit;

    // MUX for DIV VAL -> limit : period clk 
    always @(*) begin 
        case (div_val)
            4'd0: limit = 8'd1;      // divide 1 
            4'd1: limit = 8'd2;      // divide 2
            4'd2: limit = 8'd4;      // divide 4
            4'd3: limit = 8'd8;      // divide 8
            4'd4: limit = 8'd16;     // divide 16 
            4'd5: limit = 8'd32;     // divide 32
            4'd6: limit = 8'd64;     // divide 64
            4'd7: limit = 8'd128;    // divide 128
            4'd8: limit = 8'd255;    // divide 255
            default: limit = 8'd1;
        endcase 
    end 

    assign reach_limit = (int_cnt == limit);
    
    // control logic
    assign control_mode0      = (div_val == 4'd0) & div_en & timer_en;
    assign control_default    = div_en & timer_en;
    assign control_mode_other = timer_en & div_en & (div_val != 4'd0) & reach_limit;

    // output count_en 
    assign count_en = control_mode0 | control_default | control_mode_other; 
    
    // counter reset condition
    assign cnt_rst = reach_limit | !timer_en | !div_en;

    // bo dem counter_tmp -> dem chu ki clk 
    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin 
            int_cnt <= {CNT_W{1'b0}};
        end else if (cnt_rst) begin 
            int_cnt <= {CNT_W{1'b0}};
        end else if (div_en && timer_en && (div_val != 4'd0)) begin 
            int_cnt <= int_cnt + 1'b1; 
        end else begin 
            int_cnt <= int_cnt;
        end 
    end 

endmodule