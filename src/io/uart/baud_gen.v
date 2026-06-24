module baud_gen#(
    parameter CLK_FREQ=50_000_000,
    parameter BAUD_RATE=115200
)(
    input wire clk,
    input wire rst,
    input wire tx_en,
    output wire tx_tick,
    output wire rx_tick
);

parameter TDBIT=$clog2(CLK_FREQ/BAUD_RATE);
parameter RDBIT=$clog2(CLK_FREQ/BAUD_RATE/16);
localparam [TDBIT:0] TX_DIVIDER=CLK_FREQ/BAUD_RATE;
localparam [RDBIT:0] RX_DIVIDER=CLK_FREQ/BAUD_RATE/16;

reg [TDBIT:0] tx_counter;
reg [RDBIT:0] rx_counter;
reg tx_tick_reg,rx_tick_reg;

always @(posedge clk) begin
    if(rst) begin
        tx_counter<=0;
        rx_counter<=0;
        tx_tick_reg<=1'b0;
        rx_tick_reg<=1'b0;
    end else begin
        if(tx_en) begin
            if(tx_counter==TX_DIVIDER-1) begin
                tx_counter<=0;
                tx_tick_reg<=1'b1;
            end else begin
                tx_counter<=tx_counter+1'b1;
                tx_tick_reg<=1'b0;
            end
        end else begin
            tx_counter<=0;
            tx_tick_reg<=1'b0;
        end

        if(rx_counter==RX_DIVIDER-1) begin
            rx_counter<=0;
            rx_tick_reg<=1'b1;
        end else begin
            rx_counter<=rx_counter+1'b1;
            rx_tick_reg<=1'b0;
        end

    end
end

assign tx_tick=tx_tick_reg;
assign rx_tick=rx_tick_reg;

endmodule