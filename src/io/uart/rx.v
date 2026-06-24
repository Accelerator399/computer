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

parameter IDLE=2'd0;
parameter START=2'd1;
parameter DATA=2'd2;
parameter STOP=2'd3;

reg [1:0] state;
reg [2:0] Bit;
reg [7:0] data_reg;
reg [3:0] counter;
reg read_clear_d;
wire read_clear_pulse=read_clear&&!read_clear_d;

always @(posedge clk) begin
    if(rst) begin
        state<=IDLE;
        Bit<=0;
        data_reg<=0;
        data<=0;
        ready<=0;
        frame_error<=0;
        read_clear_d<=0;
    end else begin
        read_clear_d<=read_clear;
        case(state)
            IDLE:begin
                if(read_clear_pulse)
                    ready<=0;
                counter<=0;
                frame_error<=0;
                if(pin==0)
                    state<=START;
            end
            START:begin
                if(tick) begin
                    if(counter==4'd7) begin
                        if(pin==1'b0) begin
                            counter<=0;
                            Bit<=0;
                            state<=DATA;
                        end else begin
                            state<=IDLE;
                        end
                    end else begin
                        counter<=counter+4'd1;
                    end
                end
            end
            DATA:begin
                if(tick) begin
                    if(counter==4'd15) begin
                        data_reg[Bit]<=pin;  // ✅ 修复：先采样数据
                        if(Bit==3'd7) begin
                            state<=STOP;
                        end else begin
                            Bit<=Bit+3'd1;
                        end
                        counter<=0;  // ✅ 修复：只赋值一次
                    end else begin
                        counter<=counter+4'd1;
                    end
                end
            end
            STOP:begin
                if(tick) begin
                    if(counter==4'd15) begin
                        state<=IDLE;
                        counter<=0;
                        if(pin==1'b1) begin
                            data<=data_reg;
                            ready<=1'b1;
                        end else begin
                            frame_error<=1'b1;
                        end
                    end else begin
                        counter<=counter+4'd1;
                    end
                end
            end
        endcase
    end
end

endmodule
