module rx(
    input wire clk,
    input wire rst,
    input wire tick,
    input wire pin,
    input wire read_clear,
    output reg [7:0] data,
    output reg ready,
    output reg frame_error
);

parameter CLK_FREQ=50_000_000;
parameter BAUD_RATE=115200;

parameter IDLE=2'd0;
parameter START=2'd1;
parameter DATA=2'd2;
parameter STOP=2'd3;

localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
localparam integer HALF_CLKS_PER_BIT = CLKS_PER_BIT / 2;
localparam integer BAUD_COUNTER_BITS = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT + 1);

reg [1:0] state;
reg [2:0] Bit;
reg [7:0] data_reg;
reg [BAUD_COUNTER_BITS-1:0] counter;
reg read_clear_d;
wire read_clear_pulse=read_clear&&!read_clear_d;
reg pin_meta;
reg pin_sync;

wire _unused_tick = tick;

always @(posedge clk) begin
    if(rst) begin
        state<=IDLE;
        Bit<=0;
        data_reg<=0;
        data<=0;
        ready<=0;
        frame_error<=0;
        read_clear_d<=0;
        counter<=0;
        pin_meta<=1'b1;
        pin_sync<=1'b1;
    end else begin
        pin_meta<=pin;
        pin_sync<=pin_meta;
        read_clear_d<=read_clear;
        if(read_clear_pulse)
            ready<=0;

        case(state)
            IDLE:begin
                counter<=0;
                frame_error<=0;
                if(pin_sync==0) begin
                    counter<=HALF_CLKS_PER_BIT[BAUD_COUNTER_BITS-1:0];
                    state<=START;
                end
            end
            START:begin
                if(counter==0) begin
                    if(pin_sync==1'b0) begin
                        counter<=CLKS_PER_BIT[BAUD_COUNTER_BITS-1:0] - 1'b1;
                        Bit<=0;
                        state<=DATA;
                    end else begin
                        state<=IDLE;
                    end
                end else begin
                    counter<=counter-1'b1;
                end
            end
            DATA:begin
                if(counter==0) begin
                    data_reg[Bit]<=pin_sync;
                    counter<=CLKS_PER_BIT[BAUD_COUNTER_BITS-1:0] - 1'b1;
                    if(Bit==3'd7) begin
                        state<=STOP;
                    end else begin
                        Bit<=Bit+3'd1;
                    end
                end else begin
                    counter<=counter-1'b1;
                end
            end
            STOP:begin
                if(counter==0) begin
                    state<=IDLE;
                    counter<=0;
                    if(pin_sync==1'b1) begin
                        data<=data_reg;
                        ready<=1'b1;
                    end else begin
                        frame_error<=1'b1;
                    end
                end else begin
                    counter<=counter-1'b1;
                end
            end
        endcase
    end
end

endmodule
