module computer_ddr_bridge #(
    parameter CLK_FREQ      = 100_000_000,
    parameter BAUD_RATE     = 115200,
    parameter RESET_VECTOR  = 32'h0000_0000,
    parameter DDR_BASE      = 32'h8000_0000,
    parameter MMIO_BASE     = 32'h1000_0000,
    parameter ETH_BASE      = 32'h1044_0000,
    parameter TLB_ENTRIES   = 32,
    parameter MIG_ADDR_WIDTH = 27,
    parameter BOOT_ROM_ENABLE = 0,
    parameter BOOT_ROM_BASE = 32'h0000_0000,
    parameter BOOT_ROM_WORDS = 64,
    parameter BOOT_ROM_INIT_FILE = "",
    parameter BOOT_RAM_ENABLE = 0,
    parameter BOOT_RAM_BASE = 32'h0000_8000,
    parameter BOOT_RAM_WORDS = 8192,
    parameter BOOT_RAM_INIT_FILE = "",
    parameter ENABLE_FPU    = 1
)(
    input clk,
    input rst,

    inout [31:0] pad,
    input uart_rx_in,

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
    output [31:0] satp_out,
    output uart_tx_out,

    output eth_mmio_req,
    output eth_mmio_we,
    output [12:0] eth_mmio_addr,
    output [31:0] eth_mmio_wdata,
    output [3:0] eth_mmio_wstrb,
    input [31:0] eth_mmio_rdata,
    input eth_mmio_ready,

    input ui_clk_sync_rst,
    input init_calib_complete,

    output [MIG_ADDR_WIDTH-1:0] app_addr,
    output [2:0] app_cmd,
    output app_en,
    output [127:0] app_wdf_data,
    output app_wdf_end,
    output app_wdf_wren,
    output [15:0] app_wdf_mask,
    input app_rdy,
    input app_wdf_rdy,
    input [127:0] app_rd_data,
    input app_rd_data_end,
    input app_rd_data_valid
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
    .BAUD_RATE(BAUD_RATE),
    .RESET_VECTOR(RESET_VECTOR),
    .MMIO_BASE(MMIO_BASE),
    .ETH_BASE(ETH_BASE),
    .BOOT_ROM_ENABLE(BOOT_ROM_ENABLE),
    .BOOT_ROM_BASE(BOOT_ROM_BASE),
    .BOOT_ROM_WORDS(BOOT_ROM_WORDS),
    .BOOT_ROM_INIT_FILE(BOOT_ROM_INIT_FILE),
    .BOOT_RAM_ENABLE(BOOT_RAM_ENABLE),
    .BOOT_RAM_BASE(BOOT_RAM_BASE),
    .BOOT_RAM_WORDS(BOOT_RAM_WORDS),
    .BOOT_RAM_INIT_FILE(BOOT_RAM_INIT_FILE),
    .TLB_ENTRIES(TLB_ENTRIES),
    .ENABLE_FPU(ENABLE_FPU)
) u_core (
    .clk(clk),
    .rst(rst),
    .pad(pad),
    .uart_rx_in(uart_rx_in),
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
    .uart_tx_out(uart_tx_out),
    .eth_mmio_req(eth_mmio_req),
    .eth_mmio_we(eth_mmio_we),
    .eth_mmio_addr(eth_mmio_addr),
    .eth_mmio_wdata(eth_mmio_wdata),
    .eth_mmio_wstrb(eth_mmio_wstrb),
    .eth_mmio_rdata(eth_mmio_rdata),
    .eth_mmio_ready(eth_mmio_ready),
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

mmu_ddr_adapter #(
    .ADDR_WIDTH(MIG_ADDR_WIDTH),
    .DATA_WIDTH(128),
    .DDR_BASE(DDR_BASE)
) u_ddr_adapter (
    .clk(clk),
    .rst(rst),
    .icache_req(icache_mem_req),
    .icache_we(icache_mem_we),
    .icache_addr(icache_mem_addr),
    .icache_wdata(icache_mem_wdata),
    .icache_wstrb(icache_mem_wstrb),
    .icache_rdata(icache_mem_rdata),
    .icache_ready(icache_mem_ready),
    .dcache_req(dcache_mem_req),
    .dcache_we(dcache_mem_we),
    .dcache_addr(dcache_mem_addr),
    .dcache_wdata(dcache_mem_wdata),
    .dcache_wstrb(dcache_mem_wstrb),
    .dcache_rdata(dcache_mem_rdata),
    .dcache_ready(dcache_mem_ready),
    .walker_req(walker_mem_req),
    .walker_addr(walker_mem_addr),
    .walker_rdata(walker_mem_rdata),
    .walker_ready(walker_mem_ready),
    .ui_clk_sync_rst(ui_clk_sync_rst),
    .init_calib_complete(init_calib_complete),
    .app_addr(app_addr),
    .app_cmd(app_cmd),
    .app_en(app_en),
    .app_wdf_data(app_wdf_data),
    .app_wdf_end(app_wdf_end),
    .app_wdf_wren(app_wdf_wren),
    .app_wdf_mask(app_wdf_mask),
    .app_rdy(app_rdy),
    .app_wdf_rdy(app_wdf_rdy),
    .app_rd_data(app_rd_data),
    .app_rd_data_end(app_rd_data_end),
    .app_rd_data_valid(app_rd_data_valid)
);

endmodule
