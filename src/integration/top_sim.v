module top_sim #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200,
    parameter MEM_WORDS = 4096,
    parameter INIT_FILE = ""
)(
    input clk,
    input rst,

    inout [31:0] pad,

    input ext_int,
    input timer_int,
    input soft_int,

    input [4:0] test_addr,
    output [31:0] test_data,
    output [2:0] state,

    output [31:0] pc_out,
    output [31:0] inst_out,
    output [31:0] mem_addr_out,
    output [31:0] mem_wdata_out,
    output [3:0] mem_wstrb_out,
    output mem_write_out,
    output [1:0] privilege_out,

    output [31:0] i_paddr_out,
    output [31:0] d_paddr_out,
    output i_page_fault_out,
    output d_page_fault_out,
    output [31:0] satp_out
);

wire icache_mem_req;
wire icache_mem_we;
wire [31:0] icache_mem_addr;
wire [127:0] icache_mem_wdata;
wire [15:0] icache_mem_wstrb;
wire [127:0] icache_mem_rdata;
wire icache_mem_ready;

wire dcache_mem_req;
wire dcache_mem_we;
wire [31:0] dcache_mem_addr;
wire [127:0] dcache_mem_wdata;
wire [15:0] dcache_mem_wstrb;
wire [127:0] dcache_mem_rdata;
wire dcache_mem_ready;
wire walker_mem_req;
wire [31:0] walker_mem_addr;
wire [127:0] walker_mem_rdata;
wire walker_mem_ready;

computer_core #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) u_core (
    .clk(clk),
    .rst(rst),
    .pad(pad),
    .uart_rx_in(pad[10]),
    .ext_int(ext_int),
    .timer_int(timer_int),
    .soft_int(soft_int),
    .test_addr(test_addr),
    .test_data(test_data),
    .state(state),
    .pc_out(pc_out),
    .inst_out(inst_out),
    .mem_addr_out(mem_addr_out),
    .mem_wdata_out(mem_wdata_out),
    .mem_wstrb_out(mem_wstrb_out),
    .mem_write_out(mem_write_out),
    .privilege_out(privilege_out),
    .i_vaddr_out(),
    .d_vaddr_out(),
    .i_paddr_out(i_paddr_out),
    .d_paddr_out(d_paddr_out),
    .i_page_fault_out(i_page_fault_out),
    .d_page_fault_out(d_page_fault_out),
    .satp_out(satp_out),
    .i_tlb_miss_count_out(),
    .d_tlb_miss_count_out(),
    .uart_tx_out(),
    .eth_mmio_req(),
    .eth_mmio_we(),
    .eth_mmio_addr(),
    .eth_mmio_wdata(),
    .eth_mmio_wstrb(),
    .eth_mmio_rdata(32'b0),
    .eth_mmio_ready(1'b1),
    .icache_mem_req(icache_mem_req),
    .icache_mem_we(icache_mem_we),
    .icache_mem_addr(icache_mem_addr),
    .icache_mem_wdata(icache_mem_wdata),
    .icache_mem_wstrb(icache_mem_wstrb),
    .icache_mem_rdata(icache_mem_rdata),
    .icache_mem_ready(icache_mem_ready),
    .dcache_mem_req(dcache_mem_req),
    .dcache_mem_we(dcache_mem_we),
    .dcache_mem_addr(dcache_mem_addr),
    .dcache_mem_wdata(dcache_mem_wdata),
    .dcache_mem_wstrb(dcache_mem_wstrb),
    .dcache_mem_rdata(dcache_mem_rdata),
    .dcache_mem_ready(dcache_mem_ready),
    .walker_mem_req(walker_mem_req),
    .walker_mem_addr(walker_mem_addr),
    .walker_mem_rdata(walker_mem_rdata),
    .walker_mem_ready(walker_mem_ready)
);

simple_mem128 #(
    .WORDS(MEM_WORDS),
    .INIT_FILE(INIT_FILE)
) u_mem (
    .clk(clk),
    .rst(rst),
    .i_req(icache_mem_req),
    .i_we(icache_mem_we),
    .i_addr(icache_mem_addr),
    .i_wdata(icache_mem_wdata),
    .i_wstrb(icache_mem_wstrb),
    .i_rdata(icache_mem_rdata),
    .i_ready(icache_mem_ready),
    .d_req(dcache_mem_req),
    .d_we(dcache_mem_we),
    .d_addr(dcache_mem_addr),
    .d_wdata(dcache_mem_wdata),
    .d_wstrb(dcache_mem_wstrb),
    .d_rdata(dcache_mem_rdata),
    .d_ready(dcache_mem_ready),
    .w_req(walker_mem_req),
    .w_addr(walker_mem_addr),
    .w_rdata(walker_mem_rdata),
    .w_ready(walker_mem_ready)
);

endmodule
