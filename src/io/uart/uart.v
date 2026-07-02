module uart#(
    parameter CLK_FREQ=50_000_000,
    parameter BAUD_RATE=115200
)(
    input wire clk,
    input wire rst,

    // CPU 接口
    input wire tx_start,
    input wire [7:0] tx_data,
    output wire tx_busy,
    output wire [7:0] rx_data,
    output wire rx_ready,
    output wire frame_error,
    input wire rx_read_clear,

    // 外部引脚
    input wire uart_rx,
    output wire uart_tx
);

wire tx_tick,rx_tick;

baud_gen #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) baud_inst (
    .clk(clk),
    .rst(rst),
    .tx_en(tx_busy),
    .tx_tick(tx_tick),
    .rx_tick(rx_tick)
);

tx tx_inst(
    .clk(clk),
    .rst(rst),
    .start(tx_start),
    .tick(tx_tick),
    .data(tx_data),
    .busy(tx_busy),
    .pin(uart_tx)
);

rx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) rx_inst(
    .clk(clk),
    .rst(rst),
    .tick(rx_tick),
    .pin(uart_rx),
    .read_clear(rx_read_clear),
    .data(rx_data),
    .ready(rx_ready),
    .frame_error(frame_error)
);

endmodule
