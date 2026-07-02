`ifndef COMPUTER_CLK_FREQ
`define COMPUTER_CLK_FREQ 100000000
`endif

`ifndef COMPUTER_UI_CLK_FREQ
`define COMPUTER_UI_CLK_FREQ 100000000
`endif

`ifndef COMPUTER_ENABLE_FPU
`define COMPUTER_ENABLE_FPU 1
`endif

`ifndef COMPUTER_LOADER_BAUD_RATE
`define COMPUTER_LOADER_BAUD_RATE 230400
`endif

`ifndef COMPUTER_USE_UART_DDR_LOADER
`define COMPUTER_USE_UART_DDR_LOADER 1
`endif

`ifndef COMPUTER_BOOT_ROM_ENABLE
`define COMPUTER_BOOT_ROM_ENABLE 0
`endif

`ifndef COMPUTER_BOOT_ROM_WORDS
`define COMPUTER_BOOT_ROM_WORDS 64
`endif

`ifndef COMPUTER_BOOT_ROM_INIT_FILE
`define COMPUTER_BOOT_ROM_INIT_FILE ""
`endif

`ifndef COMPUTER_BOOT_RAM_ENABLE
`define COMPUTER_BOOT_RAM_ENABLE 0
`endif

`ifndef COMPUTER_BOOT_RAM_WORDS
`define COMPUTER_BOOT_RAM_WORDS 8192
`endif

`ifndef COMPUTER_BOOT_RAM_INIT_FILE
`define COMPUTER_BOOT_RAM_INIT_FILE ""
`endif

`ifndef COMPUTER_ENABLE_ETHERNET_LITE
`define COMPUTER_ENABLE_ETHERNET_LITE 0
`endif

module computer_top_fpga #(
    parameter CLK_FREQ = `COMPUTER_CLK_FREQ,
    parameter UI_CLK_FREQ = `COMPUTER_UI_CLK_FREQ,
    parameter ENABLE_FPU = `COMPUTER_ENABLE_FPU,
    parameter LOADER_BAUD_RATE = `COMPUTER_LOADER_BAUD_RATE,
    parameter USE_UART_DDR_LOADER = `COMPUTER_USE_UART_DDR_LOADER,
    parameter BOOT_ROM_ENABLE = `COMPUTER_BOOT_ROM_ENABLE,
    parameter BOOT_ROM_WORDS = `COMPUTER_BOOT_ROM_WORDS,
    parameter BOOT_ROM_INIT_FILE = `COMPUTER_BOOT_ROM_INIT_FILE,
    parameter BOOT_RAM_ENABLE = `COMPUTER_BOOT_RAM_ENABLE,
    parameter BOOT_RAM_WORDS = `COMPUTER_BOOT_RAM_WORDS,
    parameter BOOT_RAM_INIT_FILE = `COMPUTER_BOOT_RAM_INIT_FILE,
    parameter ENABLE_ETHERNET_LITE = `COMPUTER_ENABLE_ETHERNET_LITE
)(
    input clk,
    input rst,

    input uart_rx,
    output uart_tx,

    input mtxclk_0,
    input mrxclk_0,
    output mtxen_0,
    output [3:0] mtxd_0,
    output mtxerr_0,
    input mrxdv_0,
    input [3:0] mrxd_0,
    input mrxerr_0,
    input mcoll_0,
    input mcrs_0,
    output mdc_0,
    inout mdio_0,
    output phy_rstn,

    inout [15:0] ddr3_dq,
    inout [1:0] ddr3_dqs_n,
    inout [1:0] ddr3_dqs_p,
    output [12:0] ddr3_addr,
    output [2:0] ddr3_ba,
    output ddr3_ras_n,
    output ddr3_cas_n,
    output ddr3_we_n,
    output ddr3_reset_n,
    output [0:0] ddr3_ck_p,
    output [0:0] ddr3_ck_n,
    output [0:0] ddr3_cke,
    output [1:0] ddr3_dm,
    output [0:0] ddr3_odt
);

localparam CPU_BAUD_RATE = 115200;
localparam MIG_ADDR_WIDTH = 27;
localparam DDR_BASE = 32'h8000_0000;

wire clk_cpu;
wire clk_200;
wire clkwiz_locked;

clk_wiz_0 u_clk_wiz (
    .clk_in1(clk),
    .clk_out1(clk_cpu),
    .clk_out2(clk_200),
    .reset(1'b0),
    .locked(clkwiz_locked)
);

wire ui_clk;
wire ui_clk_sync_rst;
wire init_calib_complete;

wire [MIG_ADDR_WIDTH-1:0] app_addr;
wire [2:0] app_cmd;
wire app_en;
wire [127:0] app_wdf_data;
wire app_wdf_end;
wire app_wdf_wren;
wire [15:0] app_wdf_mask;
wire [127:0] app_rd_data;
wire app_rd_data_end;
wire app_rd_data_valid;
wire app_rdy;
wire app_wdf_rdy;

wire sys_rst = ~rst || !clkwiz_locked;

mig_7series_0 u_mig_7series_0 (
    .ddr3_addr(ddr3_addr),
    .ddr3_ba(ddr3_ba),
    .ddr3_cas_n(ddr3_cas_n),
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_ck_p(ddr3_ck_p),
    .ddr3_cke(ddr3_cke),
    .ddr3_ras_n(ddr3_ras_n),
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_we_n(ddr3_we_n),
    .ddr3_dq(ddr3_dq),
    .ddr3_dqs_n(ddr3_dqs_n),
    .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_dm(ddr3_dm),
    .ddr3_odt(ddr3_odt),
    .init_calib_complete(init_calib_complete),
    .app_addr(app_addr),
    .app_cmd(app_cmd),
    .app_en(app_en),
    .app_wdf_data(app_wdf_data),
    .app_wdf_end(app_wdf_end),
    .app_wdf_wren(app_wdf_wren),
    .app_wdf_mask(app_wdf_mask),
    .app_rd_data(app_rd_data),
    .app_rd_data_end(app_rd_data_end),
    .app_rd_data_valid(app_rd_data_valid),
    .app_rdy(app_rdy),
    .app_wdf_rdy(app_wdf_rdy),
    .app_sr_req(1'b0),
    .app_ref_req(1'b0),
    .app_zq_req(1'b0),
    .app_sr_active(),
    .app_ref_ack(),
    .app_zq_ack(),
    .ui_clk(ui_clk),
    .ui_clk_sync_rst(ui_clk_sync_rst),
    .device_temp(),
    .sys_clk_i(clk_200),
    .sys_rst(sys_rst)
);

wire [MIG_ADDR_WIDTH-1:0] comp_app_addr;
wire [2:0] comp_app_cmd;
wire comp_app_en;
wire [127:0] comp_app_wdf_data;
wire comp_app_wdf_end;
wire comp_app_wdf_wren;
wire [15:0] comp_app_wdf_mask;

wire [MIG_ADDR_WIDTH-1:0] loader_app_addr;
wire [2:0] loader_app_cmd;
wire loader_app_en;
wire [127:0] loader_app_wdf_data;
wire loader_app_wdf_end;
wire loader_app_wdf_wren;
wire [15:0] loader_app_wdf_mask;

wire loader_done;
wire loader_error;
wire [31:0] loader_line_count;
wire loader_active = (USE_UART_DDR_LOADER != 0) && !loader_done;
wire loader_done_effective = (USE_UART_DDR_LOADER != 0) ? loader_done : 1'b1;

assign app_addr = loader_active ? loader_app_addr : comp_app_addr;
assign app_cmd = loader_active ? loader_app_cmd : comp_app_cmd;
assign app_en = loader_active ? loader_app_en : comp_app_en;
assign app_wdf_data = loader_active ? loader_app_wdf_data : comp_app_wdf_data;
assign app_wdf_end = loader_active ? loader_app_wdf_end : comp_app_wdf_end;
assign app_wdf_wren = loader_active ? loader_app_wdf_wren : comp_app_wdf_wren;
assign app_wdf_mask = loader_active ? loader_app_wdf_mask : comp_app_wdf_mask;

wire loader_rst = ui_clk_sync_rst || !init_calib_complete;
wire raw_computer_rst = ui_clk_sync_rst || !init_calib_complete || !loader_done_effective || !clkwiz_locked;
reg [2:0] computer_rst_sync = 3'b111;

always @(posedge clk_cpu or posedge raw_computer_rst) begin
    if (raw_computer_rst)
        computer_rst_sync <= 3'b111;
    else
        computer_rst_sync <= {computer_rst_sync[1:0], 1'b0};
end

wire computer_rst = computer_rst_sync[2];

wire loader_uart_tx;
uart_ddr_loader #(
    .CLK_FREQ(UI_CLK_FREQ),
    .BAUD_RATE(LOADER_BAUD_RATE),
    .ADDR_WIDTH(MIG_ADDR_WIDTH)
) u_uart_ddr_loader (
    .clk(ui_clk),
    .rst(loader_rst),
    .uart_rx(uart_rx),
    .uart_tx(loader_uart_tx),
    .done(loader_done),
    .error(loader_error),
    .line_count(loader_line_count),
    .app_addr(loader_app_addr),
    .app_cmd(loader_app_cmd),
    .app_en(loader_app_en),
    .app_wdf_data(loader_app_wdf_data),
    .app_wdf_end(loader_app_wdf_end),
    .app_wdf_wren(loader_app_wdf_wren),
    .app_wdf_mask(loader_app_wdf_mask),
    .app_rdy(app_rdy),
    .app_wdf_rdy(app_wdf_rdy)
);

wire [31:0] pad;
wire cpu_uart_tx;
assign pad[10:0] = 11'bz;
assign pad[31:11] = 21'bz;
assign uart_tx = loader_active ? loader_uart_tx : cpu_uart_tx;

wire [31:0] test_data;
wire [2:0] state;
wire [31:0] pc_out;
wire [31:0] inst_out;
wire [31:0] mem_addr_out;
wire [31:0] mem_wdata_out;
wire [3:0] mem_wstrb_out;
wire mem_write_out;
wire [1:0] privilege_out;
wire [31:0] i_paddr_out;
wire [31:0] d_paddr_out;
wire i_page_fault_out;
wire d_page_fault_out;
wire [31:0] satp_out;

wire [MIG_ADDR_WIDTH-1:0] cpu_app_addr;
wire [2:0] cpu_app_cmd;
wire cpu_app_en;
wire [127:0] cpu_app_wdf_data;
wire cpu_app_wdf_end;
wire cpu_app_wdf_wren;
wire [15:0] cpu_app_wdf_mask;
wire [127:0] cpu_app_rd_data;
wire cpu_app_rd_data_end;
wire cpu_app_rd_data_valid;
wire cpu_app_rdy;
wire cpu_app_wdf_rdy;

wire eth_mmio_req;
wire eth_mmio_we;
wire [12:0] eth_mmio_addr;
wire [31:0] eth_mmio_wdata;
wire [3:0] eth_mmio_wstrb;
wire [31:0] eth_mmio_rdata;
wire eth_mmio_ready;

wire [12:0] eth_axi_awaddr;
wire eth_axi_awvalid;
wire eth_axi_awready;
wire [31:0] eth_axi_wdata;
wire [3:0] eth_axi_wstrb;
wire eth_axi_wvalid;
wire eth_axi_wready;
wire [1:0] eth_axi_bresp;
wire eth_axi_bvalid;
wire eth_axi_bready;
wire [12:0] eth_axi_araddr;
wire eth_axi_arvalid;
wire eth_axi_arready;
wire [31:0] eth_axi_rdata;
wire [1:0] eth_axi_rresp;
wire eth_axi_rvalid;
wire eth_axi_rready;
wire eth_irq_unused;
wire phy_mdio_i;
wire phy_mdio_o;
wire phy_mdio_t;

wire bridge_mig_rst = ui_clk_sync_rst || !init_calib_complete || loader_active;

mig_app_cdc_bridge #(
    .ADDR_WIDTH(MIG_ADDR_WIDTH),
    .DATA_WIDTH(128)
) u_mig_app_cdc_bridge (
    .cpu_clk(clk_cpu),
    .cpu_rst(computer_rst),
    .cpu_app_addr(cpu_app_addr),
    .cpu_app_cmd(cpu_app_cmd),
    .cpu_app_en(cpu_app_en),
    .cpu_app_wdf_data(cpu_app_wdf_data),
    .cpu_app_wdf_end(cpu_app_wdf_end),
    .cpu_app_wdf_wren(cpu_app_wdf_wren),
    .cpu_app_wdf_mask(cpu_app_wdf_mask),
    .cpu_app_rdy(cpu_app_rdy),
    .cpu_app_wdf_rdy(cpu_app_wdf_rdy),
    .cpu_app_rd_data(cpu_app_rd_data),
    .cpu_app_rd_data_end(cpu_app_rd_data_end),
    .cpu_app_rd_data_valid(cpu_app_rd_data_valid),
    .mig_clk(ui_clk),
    .mig_rst(bridge_mig_rst),
    .mig_app_addr(comp_app_addr),
    .mig_app_cmd(comp_app_cmd),
    .mig_app_en(comp_app_en),
    .mig_app_wdf_data(comp_app_wdf_data),
    .mig_app_wdf_end(comp_app_wdf_end),
    .mig_app_wdf_wren(comp_app_wdf_wren),
    .mig_app_wdf_mask(comp_app_wdf_mask),
    .mig_app_rdy(app_rdy),
    .mig_app_wdf_rdy(app_wdf_rdy),
    .mig_app_rd_data(app_rd_data),
    .mig_app_rd_data_end(app_rd_data_end),
    .mig_app_rd_data_valid(app_rd_data_valid)
);

computer_ddr_bridge #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(CPU_BAUD_RATE),
    .DDR_BASE(DDR_BASE),
    .MIG_ADDR_WIDTH(MIG_ADDR_WIDTH),
    .BOOT_ROM_ENABLE(BOOT_ROM_ENABLE),
    .BOOT_ROM_BASE(32'h0000_0000),
    .BOOT_ROM_WORDS(BOOT_ROM_WORDS),
    .BOOT_ROM_INIT_FILE(BOOT_ROM_INIT_FILE),
    .BOOT_RAM_ENABLE(BOOT_RAM_ENABLE),
    .BOOT_RAM_BASE(32'h0000_8000),
    .BOOT_RAM_WORDS(BOOT_RAM_WORDS),
    .BOOT_RAM_INIT_FILE(BOOT_RAM_INIT_FILE),
    .ENABLE_FPU(ENABLE_FPU)
) u_computer (
    .clk(clk_cpu),
    .rst(computer_rst),
    .pad(pad),
    .uart_rx_in(uart_rx),
    .ext_int(1'b0),
    .timer_int(1'b0),
    .soft_int(1'b0),
    .test_addr(5'd0),
    .test_data(test_data),
    .state(state),
    .pc_out(pc_out),
    .inst_out(inst_out),
    .mem_addr_out(mem_addr_out),
    .mem_wdata_out(mem_wdata_out),
    .mem_wstrb_out(mem_wstrb_out),
    .mem_write_out(mem_write_out),
    .privilege_out(privilege_out),
    .i_paddr_out(i_paddr_out),
    .d_paddr_out(d_paddr_out),
    .i_page_fault_out(i_page_fault_out),
    .d_page_fault_out(d_page_fault_out),
    .satp_out(satp_out),
    .uart_tx_out(cpu_uart_tx),
    .eth_mmio_req(eth_mmio_req),
    .eth_mmio_we(eth_mmio_we),
    .eth_mmio_addr(eth_mmio_addr),
    .eth_mmio_wdata(eth_mmio_wdata),
    .eth_mmio_wstrb(eth_mmio_wstrb),
    .eth_mmio_rdata(eth_mmio_rdata),
    .eth_mmio_ready(eth_mmio_ready),
    .ui_clk_sync_rst(computer_rst),
    .init_calib_complete(init_calib_complete),
    .app_addr(cpu_app_addr),
    .app_cmd(cpu_app_cmd),
    .app_en(cpu_app_en),
    .app_wdf_data(cpu_app_wdf_data),
    .app_wdf_end(cpu_app_wdf_end),
    .app_wdf_wren(cpu_app_wdf_wren),
    .app_wdf_mask(cpu_app_wdf_mask),
    .app_rdy(cpu_app_rdy),
    .app_wdf_rdy(cpu_app_wdf_rdy),
    .app_rd_data(cpu_app_rd_data),
    .app_rd_data_end(cpu_app_rd_data_end),
    .app_rd_data_valid(cpu_app_rd_data_valid)
);

generate
    if(ENABLE_ETHERNET_LITE != 0) begin: gen_ethernet_lite
        assign mtxerr_0 = 1'b0;
        assign phy_mdio_i = mdio_0;
        assign mdio_0 = phy_mdio_t ? 1'bz : phy_mdio_o;

        axi_lite_mmio_bridge #(
            .ADDR_WIDTH(13)
        ) u_eth_axi_bridge (
            .clk(clk_cpu),
            .rst(computer_rst),
            .req_valid(eth_mmio_req),
            .req_write(eth_mmio_we),
            .req_addr(eth_mmio_addr),
            .req_wdata(eth_mmio_wdata),
            .req_wstrb(eth_mmio_wstrb),
            .req_ready(eth_mmio_ready),
            .req_rdata(eth_mmio_rdata),
            .m_axi_awaddr(eth_axi_awaddr),
            .m_axi_awvalid(eth_axi_awvalid),
            .m_axi_awready(eth_axi_awready),
            .m_axi_wdata(eth_axi_wdata),
            .m_axi_wstrb(eth_axi_wstrb),
            .m_axi_wvalid(eth_axi_wvalid),
            .m_axi_wready(eth_axi_wready),
            .m_axi_bresp(eth_axi_bresp),
            .m_axi_bvalid(eth_axi_bvalid),
            .m_axi_bready(eth_axi_bready),
            .m_axi_araddr(eth_axi_araddr),
            .m_axi_arvalid(eth_axi_arvalid),
            .m_axi_arready(eth_axi_arready),
            .m_axi_rdata(eth_axi_rdata),
            .m_axi_rresp(eth_axi_rresp),
            .m_axi_rvalid(eth_axi_rvalid),
            .m_axi_rready(eth_axi_rready)
        );

        axi_ethernetlite_0 u_axi_ethernetlite (
            .s_axi_aclk(clk_cpu),
            .s_axi_aresetn(!computer_rst),
            .ip2intc_irpt(eth_irq_unused),
            .s_axi_awaddr(eth_axi_awaddr),
            .s_axi_awvalid(eth_axi_awvalid),
            .s_axi_awready(eth_axi_awready),
            .s_axi_wdata(eth_axi_wdata),
            .s_axi_wstrb(eth_axi_wstrb),
            .s_axi_wvalid(eth_axi_wvalid),
            .s_axi_wready(eth_axi_wready),
            .s_axi_bresp(eth_axi_bresp),
            .s_axi_bvalid(eth_axi_bvalid),
            .s_axi_bready(eth_axi_bready),
            .s_axi_araddr(eth_axi_araddr),
            .s_axi_arvalid(eth_axi_arvalid),
            .s_axi_arready(eth_axi_arready),
            .s_axi_rdata(eth_axi_rdata),
            .s_axi_rresp(eth_axi_rresp),
            .s_axi_rvalid(eth_axi_rvalid),
            .s_axi_rready(eth_axi_rready),
            .phy_tx_clk(mtxclk_0),
            .phy_rx_clk(mrxclk_0),
            .phy_crs(mcrs_0),
            .phy_dv(mrxdv_0),
            .phy_rx_data(mrxd_0),
            .phy_col(mcoll_0),
            .phy_rx_er(mrxerr_0),
            .phy_rst_n(phy_rstn),
            .phy_tx_en(mtxen_0),
            .phy_tx_data(mtxd_0),
            .phy_mdio_i(phy_mdio_i),
            .phy_mdio_o(phy_mdio_o),
            .phy_mdio_t(phy_mdio_t),
            .phy_mdc(mdc_0)
        );
    end else begin: gen_no_ethernet_lite
        assign eth_mmio_rdata = 32'b0;
        assign eth_mmio_ready = 1'b1;
        assign mtxen_0 = 1'b0;
        assign mtxd_0 = 4'b0;
        assign mtxerr_0 = 1'b0;
        assign mdc_0 = 1'b0;
        assign mdio_0 = 1'bz;
        assign phy_rstn = 1'b0;
    end
endgenerate

endmodule
