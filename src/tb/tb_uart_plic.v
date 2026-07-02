`timescale 1ns/1ps

module tb_uart_plic;

localparam UART_BASE = 32'h1001_0000;
localparam GPIO_BASE = 32'h1002_0000;
localparam PLIC_BASE = 32'h1003_0000;

reg clk;
reg rst;

reg [31:0] io_addr;
reg [31:0] io_wdata;
reg io_we;
wire [31:0] io_rdata;
wire uart_irq;

reg ext_irq;
reg [31:0] plic_addr;
reg [31:0] plic_wdata;
reg [3:0] plic_wstrb;
reg plic_we;
wire [31:0] plic_rdata;
wire plic_irq_out;

wire [31:0] pad;
reg uart_rx_drive;

assign pad[10] = uart_rx_drive;
assign pad[9] = 1'bz;
assign pad[8:0] = 9'bz;
assign pad[31:11] = 21'bz;

iomux #(
    .CLK_FREQ(160),
    .BAUD_RATE(10)
) u_iomux (
    .clk(clk),
    .rst(rst),
    .addr(io_addr),
    .wdata(io_wdata),
    .we(io_we),
    .rdata(io_rdata),
    .pad(pad),
    .uart_rx_in(pad[10]),
    .uart_irq(uart_irq)
);

plic #(
    .BASE_ADDR(PLIC_BASE),
    .NUM_SOURCES(2)
) u_plic (
    .clk(clk),
    .rst(rst),
    .irq_sources({uart_irq, ext_irq}),
    .addr(plic_addr),
    .wdata(plic_wdata),
    .wstrb(plic_wstrb),
    .we(plic_we),
    .rdata(plic_rdata),
    .irq_out(plic_irq_out)
);

task automatic check;
    input condition;
    input string message;
    begin
        if(!condition) begin
            $display("FAIL: %s", message);
            $fatal(1);
        end else begin
            $display("PASS: %s", message);
        end
    end
endtask

task automatic io_write;
    input [31:0] write_addr;
    input [31:0] value;
    begin
        @(negedge clk);
        io_addr = write_addr;
        io_wdata = value;
        io_we = 1'b1;
        @(negedge clk);
        io_we = 1'b0;
        io_wdata = 32'b0;
        @(posedge clk);
        #1;
    end
endtask

task automatic io_read;
    input [31:0] read_addr;
    output [31:0] value;
    begin
        @(negedge clk);
        io_addr = read_addr;
        io_we = 1'b0;
        #1;
        value = io_rdata;
        @(posedge clk);
        #1;
    end
endtask

task automatic plic_write;
    input [31:0] write_addr;
    input [31:0] value;
    begin
        @(negedge clk);
        plic_addr = write_addr;
        plic_wdata = value;
        plic_wstrb = 4'b1111;
        plic_we = 1'b1;
        @(negedge clk);
        plic_we = 1'b0;
        plic_wdata = 32'b0;
        plic_wstrb = 4'b0;
        @(posedge clk);
        #1;
    end
endtask

task automatic plic_read_check;
    input [31:0] read_addr;
    input [31:0] expected;
    input string message;
    begin
        plic_addr = read_addr;
        #1;
        check(plic_rdata == expected, message);
    end
endtask

task automatic drive_uart_bit;
    input bit_value;
    integer n;
    begin
        uart_rx_drive = bit_value;
        for(n = 0; n < 16; n = n + 1)
            @(posedge clk);
    end
endtask

task automatic send_uart_byte;
    input [7:0] value;
    integer bit_idx;
    begin
        drive_uart_bit(1'b0);
        for(bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1)
            drive_uart_bit(value[bit_idx]);
        drive_uart_bit(1'b1);
        repeat(4) @(posedge clk);
        #1;
    end
endtask

reg [31:0] read_value;
integer wait_cycle;

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

initial begin
    rst = 1'b1;
    io_addr = 32'b0;
    io_wdata = 32'b0;
    io_we = 1'b0;
    ext_irq = 1'b0;
    plic_addr = PLIC_BASE;
    plic_wdata = 32'b0;
    plic_wstrb = 4'b0;
    plic_we = 1'b0;
    uart_rx_drive = 1'b1;

    repeat(5) @(posedge clk);
    rst = 1'b0;

    io_write(GPIO_BASE + 32'h0000_000c, 32'h0000_0400);
    io_write(UART_BASE + 32'h0000_000c, 32'h0000_0080);
    io_write(UART_BASE + 32'h0000_0000, 32'h0000_0007);
    io_write(UART_BASE + 32'h0000_0004, 32'h0000_0000);
    io_read(UART_BASE + 32'h0000_0000, read_value);
    check(read_value == 32'h0000_0007, "UART DLL is readable while DLAB is set");
    io_read(UART_BASE + 32'h0000_0004, read_value);
    check(read_value == 32'h0000_0000, "UART DLM is readable while DLAB is set");
    io_write(UART_BASE + 32'h0000_000c, 32'h0000_0003);
    io_read(UART_BASE + 32'h0000_000c, read_value);
    check(read_value == 32'h0000_0003, "UART LCR stores 8N1 mode with DLAB clear");
    io_write(UART_BASE + 32'h0000_0004, 32'h0000_0001);
    plic_write(PLIC_BASE + 32'h0000_0008, 32'h0000_0001);
    plic_write(PLIC_BASE + 32'h0000_2000, 32'h0000_0004);
    plic_write(PLIC_BASE + 32'h0020_0000, 32'h0000_0000);

    check(!uart_irq, "UART IRQ is low before RX data");
    check(!plic_irq_out, "PLIC output is low before UART RX data");
    io_read(UART_BASE + 32'h0000_0014, read_value);
    check(read_value[0] == 1'b0, "UART LSR reports no RX data before serial input");
    check(read_value[5] == 1'b1 && read_value[6] == 1'b1, "UART LSR reports transmitter empty");

    send_uart_byte(8'ha5);

    for(wait_cycle = 0; wait_cycle < 80 && !uart_irq; wait_cycle = wait_cycle + 1) begin
        @(posedge clk);
        #1;
    end

    check(uart_irq, "UART asserts IRQ when RX data is ready");
    plic_read_check(PLIC_BASE + 32'h0000_1000, 32'h0000_0004, "PLIC latches pending UART source 2");
    check(plic_irq_out, "PLIC asserts external IRQ for enabled UART source");
    plic_read_check(PLIC_BASE + 32'h0020_0004, 32'h0000_0002, "PLIC claim returns UART source 2");
    io_read(UART_BASE + 32'h0000_0014, read_value);
    check(read_value[0] == 1'b1, "UART LSR data-ready bit follows received data");

    io_read(UART_BASE + 32'h0000_0000, read_value);
    check(read_value == 32'h0000_00a5, "UART RBR returns the received byte");
    repeat(3) @(posedge clk);
    #1;
    check(!uart_irq, "UART IRQ clears after RX data is read");
    io_read(UART_BASE + 32'h0000_0014, read_value);
    check(read_value[0] == 1'b0, "UART LSR data-ready bit clears after RBR read");

    plic_write(PLIC_BASE + 32'h0020_0004, 32'h0000_0002);
    repeat(2) @(posedge clk);
    #1;
    plic_read_check(PLIC_BASE + 32'h0000_1000, 32'h0000_0000, "PLIC pending clears after UART completion");
    check(!plic_irq_out, "PLIC output clears after UART completion");

    $display("UART PLIC PASS");
    $finish;
end

endmodule
