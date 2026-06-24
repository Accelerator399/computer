module tx(
    input wire clk,
    input wire rst,
    input wire start,
    input wire tick,
    input wire [7:0] data,
    output reg busy,
    output reg pin
);

parameter IDLE=2'd0;
parameter START=2'd1;
parameter DATA=2'd2;
parameter STOP=2'd3;

reg [1:0] state;
reg [2:0] Bit;
reg [7:0] data_reg;

always @(posedge clk) begin
    if(rst) begin
        state<=IDLE;
        Bit<=0;
        data_reg<=0;
        pin<=1'b1;
        busy<=1'b0;
    end else begin
        case(state)
            IDLE:begin
                pin<=1'b1;
                busy<=1'b0;
                if(start) begin
                    data_reg<=data;
                    state<=START;
                    busy<=1'b1;
                end
            end
            START:begin
                if(tick) begin
                    pin<=1'b0;
                    Bit<=0;
                    state<=DATA;
                end
            end
            DATA:begin
                if(tick) begin
                    pin<=data_reg[Bit];
                    if(Bit==3'd7)
                        state<=STOP;
                    Bit<=Bit+3'd1;  // ✅ 修复：总是递增，包括最后一位
                end
            end
            STOP:begin
                if(tick) begin
                    pin<=1'b1;
                    state<=IDLE;
                    busy<=1'b0;
                end
            end
        endcase
    end
end

endmodule
