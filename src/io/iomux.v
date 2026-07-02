module iomux(
    input clk,
    input rst,

    //CPU接口
    input [31:0] addr,
    input [31:0] wdata,
    input we,
    output [31:0] rdata,

    //物理引脚
    inout [31:0] pad,
    input uart_rx_in,

    output uart_irq,
    output uart_tx_out
);

parameter CLK_FREQ=50_000_000;
parameter BAUD_RATE=115200;
parameter GPIO_BASE=32'h10020000;
parameter UART_BASE=32'h10010000;

wire tx_start,tx_busy,rx_ready,frame_error;
wire [7:0] tx_data,rx_data;
wire rx_ready_clear;
wire uart_tx_sig,uart_rx_sig;

reg [31:0] gpio_dir;
reg [31:0] gpio_out;
reg [31:0] gpio_afen;
reg [7:0] uart_ier;
reg [7:0] uart_lcr;
reg [7:0] uart_mcr;
reg [7:0] uart_scr;
reg [7:0] uart_dll;
reg [7:0] uart_dlm;

wire is_uart=(addr>=UART_BASE)&&(addr<UART_BASE+32'h100);
wire is_gpio=(addr>=GPIO_BASE)&&(addr<GPIO_BASE+32'h10);
wire [7:0] offset=addr[7:0];
wire uart_dlab=uart_lcr[7];
wire uart_rx_irq=uart_ier[0]&&rx_ready;
wire uart_tx_irq=uart_ier[1]&&!tx_busy;
wire [7:0] uart_lsr={1'b0,!tx_busy,!tx_busy,1'b0,frame_error,2'b00,rx_ready};
wire [7:0] uart_iir=uart_rx_irq ? 8'h04 :
                    uart_tx_irq ? 8'h02 :
                                  8'h01;

always @(posedge clk) begin
    if(rst) begin
        gpio_dir<=32'b0;
        gpio_out<=32'b0;
        gpio_afen<=32'b0;
        uart_ier<=8'b0;
        uart_lcr<=8'b0;
        uart_mcr<=8'b0;
        uart_scr<=8'b0;
        uart_dll<=8'b0;
        uart_dlm<=8'b0;
    end else begin
        if(we&&is_gpio) begin
            case(offset)
                4'h0: gpio_dir<=wdata;
                4'h4: gpio_out<=wdata;
                4'hc: gpio_afen<=wdata;
            endcase
        end

        if(we&&is_uart) begin
            case(offset)
                8'h00: begin
                    if(uart_dlab)
                        uart_dll<=wdata[7:0];
                end
                8'h04: begin
                    if(uart_dlab)
                        uart_dlm<=wdata[7:0];
                    else
                        uart_ier<=wdata[7:0];
                end
                8'h08: begin
                    // FCR is accepted for ns16550-style software but this UART has no FIFO.
                end
                8'h0c: uart_lcr<=wdata[7:0];
                8'h10: uart_mcr<=wdata[7:0];
                8'h1c: uart_scr<=wdata[7:0];
            endcase
        end
    end
end

assign tx_start=we&&is_uart&&(offset==8'h00)&&!uart_dlab;
assign tx_data=wdata[7:0];
assign rx_ready_clear=!we&&is_uart&&(offset==8'h00)&&!uart_dlab;

wire [31:0] uart_rdata= (offset==8'h00)? {24'b0,(uart_dlab?uart_dll:rx_data)}:
                        (offset==8'h04)? {24'b0,(uart_dlab?uart_dlm:uart_ier)}:
                        (offset==8'h08)? {24'b0,uart_iir}:
                        (offset==8'h0c)? {24'b0,uart_lcr}:
                        (offset==8'h10)? {24'b0,uart_mcr}:
                        (offset==8'h14)? {24'b0,uart_lsr}:
                        (offset==8'h18)? 32'b0:
                        (offset==8'h1c)? {24'b0,uart_scr}:
                        32'b0;
wire [31:0] gpio_rdata= (offset==4'h0)? gpio_dir:
                        (offset==4'h4)? gpio_out:
                        (offset==4'h8)? pad:
                        (offset==4'hc)? gpio_afen:
                        32'b0;

assign rdata=   is_uart? uart_rdata:
                is_gpio? gpio_rdata:
                32'b0;

assign uart_rx_sig=gpio_afen[10]? uart_rx_in:1'b1;
assign uart_irq=uart_rx_irq||uart_tx_irq;
assign uart_tx_out=uart_tx_sig;

genvar i;
generate
    for(i=0;i<32;i=i+1) begin:pad_drive
        if(i==9) begin
            assign pad[i]=gpio_afen[i]? uart_tx_sig:
                          gpio_dir[i]? gpio_out[i]:
                          1'bz;
        end else if(i==10) begin
            assign pad[i]=(!gpio_afen[10]&&gpio_dir[10])? gpio_out[10]:1'bz;
        end else begin
            assign pad[i]=gpio_dir[i]? gpio_out[i]:1'bz;
        end
    end
endgenerate

uart #(
    .CLK_FREQ (CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) uart_inst(
    .clk(clk),
    .rst(rst),
    .tx_start(tx_start),
    .tx_data(tx_data),
    .tx_busy(tx_busy),
    .rx_data(rx_data),
    .rx_ready(rx_ready),
    .frame_error(frame_error),
    .rx_read_clear(rx_ready_clear),
    .uart_rx(uart_rx_sig),
    .uart_tx(uart_tx_sig)
);

endmodule
