`timescale 1ps/1ps

module tb_computer_ddr_smoke;

localparam integer CLKIN_PERIOD_PS = 10000;   // 100 MHz board clock
localparam integer RESET_PERIOD_PS = 200000;
localparam integer CPU_TIMEOUT_CYCLES = 200000;
localparam integer APP_TIMEOUT_CYCLES = 20000;
localparam [26:0] PROGRAM_ADDR0 = 27'd0;
localparam [26:0] PROGRAM_ADDR1 = 27'd16;
localparam [26:0] DATA_ADDR_40  = 27'd64;

localparam [2:0] CMD_WRITE = 3'b000;
localparam [2:0] CMD_READ  = 3'b001;

localparam [127:0] PROGRAM_LINE0 = {
    32'h05a00113,
    32'h04002183,
    32'h04102023,
    32'h02a00093
};

localparam [127:0] PROGRAM_LINE1 = {
    32'h00000000,
    32'h0000006f,
    32'h04100203,
    32'h042000a3
};

reg board_clk;
reg sys_rst_n;
wire clk_100;
wire clk_200;
wire clk_locked;
wire sys_rst = ~sys_rst_n || !clk_locked;

wire ui_clk;
wire ui_clk_sync_rst;
wire init_calib_complete;

wire [15:0] ddr3_dq_fpga;
wire [1:0] ddr3_dqs_n_fpga;
wire [1:0] ddr3_dqs_p_fpga;
wire [12:0] ddr3_addr_fpga;
wire [2:0] ddr3_ba_fpga;
wire ddr3_ras_n_fpga;
wire ddr3_cas_n_fpga;
wire ddr3_we_n_fpga;
wire ddr3_reset_n;
wire [0:0] ddr3_ck_p_fpga;
wire [0:0] ddr3_ck_n_fpga;
wire [0:0] ddr3_cke_fpga;
wire [1:0] ddr3_dm_fpga;
wire [0:0] ddr3_odt_fpga;

wire [15:0] ddr3_dq_sdram;
wire [1:0] ddr3_dqs_n_sdram;
wire [1:0] ddr3_dqs_p_sdram;
reg [12:0] ddr3_addr_sdram;
reg [2:0] ddr3_ba_sdram;
reg ddr3_ras_n_sdram;
reg ddr3_cas_n_sdram;
reg ddr3_we_n_sdram;
reg [0:0] ddr3_ck_p_sdram;
reg [0:0] ddr3_ck_n_sdram;
reg [0:0] ddr3_cke_sdram;
reg [1:0] ddr3_dm_sdram_tmp;
reg [0:0] ddr3_odt_sdram_tmp;
wire [1:0] ddr3_dm_sdram = ddr3_dm_sdram_tmp;
wire [0:0] ddr3_odt_sdram = ddr3_odt_sdram_tmp;

wire [26:0] comp_app_addr;
wire [2:0] comp_app_cmd;
wire comp_app_en;
wire [127:0] comp_app_wdf_data;
wire comp_app_wdf_end;
wire comp_app_wdf_wren;
wire [15:0] comp_app_wdf_mask;

reg tb_master_active;
reg [26:0] tb_app_addr;
reg [2:0] tb_app_cmd;
reg tb_app_en;
reg [127:0] tb_app_wdf_data;
reg tb_app_wdf_end;
reg tb_app_wdf_wren;
reg [15:0] tb_app_wdf_mask;

wire [26:0] app_addr = tb_master_active ? tb_app_addr : comp_app_addr;
wire [2:0] app_cmd = tb_master_active ? tb_app_cmd : comp_app_cmd;
wire app_en = tb_master_active ? tb_app_en : comp_app_en;
wire [127:0] app_wdf_data = tb_master_active ? tb_app_wdf_data : comp_app_wdf_data;
wire app_wdf_end = tb_master_active ? tb_app_wdf_end : comp_app_wdf_end;
wire app_wdf_wren = tb_master_active ? tb_app_wdf_wren : comp_app_wdf_wren;
wire [15:0] app_wdf_mask = tb_master_active ? tb_app_wdf_mask : comp_app_wdf_mask;

wire [127:0] app_rd_data;
wire app_rd_data_end;
wire app_rd_data_valid;
wire app_rdy;
wire app_wdf_rdy;

reg cpu_released;
wire computer_rst = ui_clk_sync_rst || !cpu_released || tb_master_active;

reg [4:0] test_addr;
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
wire [31:0] pad;

integer errors;

clk_wiz_0 u_clk_wiz (
    .clk_out1(clk_100),
    .clk_out2(clk_200),
    .reset(1'b0),
    .locked(clk_locked),
    .clk_in1(board_clk)
);

mig_7series_0 u_mig_7series_0 (
    .ddr3_dq(ddr3_dq_fpga),
    .ddr3_dqs_n(ddr3_dqs_n_fpga),
    .ddr3_dqs_p(ddr3_dqs_p_fpga),
    .ddr3_addr(ddr3_addr_fpga),
    .ddr3_ba(ddr3_ba_fpga),
    .ddr3_ras_n(ddr3_ras_n_fpga),
    .ddr3_cas_n(ddr3_cas_n_fpga),
    .ddr3_we_n(ddr3_we_n_fpga),
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_ck_p(ddr3_ck_p_fpga),
    .ddr3_ck_n(ddr3_ck_n_fpga),
    .ddr3_cke(ddr3_cke_fpga),
    .ddr3_dm(ddr3_dm_fpga),
    .ddr3_odt(ddr3_odt_fpga),
    .sys_clk_i(clk_200),
    .app_addr(app_addr),
    .app_cmd(app_cmd),
    .app_en(app_en),
    .app_wdf_data(app_wdf_data),
    .app_wdf_end(app_wdf_end),
    .app_wdf_mask(app_wdf_mask),
    .app_wdf_wren(app_wdf_wren),
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
    .init_calib_complete(init_calib_complete),
    .device_temp(),
    .sys_rst(sys_rst)
);

computer_ddr_bridge #(
    .CLK_FREQ(100_000_000),
    .BAUD_RATE(115200),
    .MMIO_BASE(32'h1000_0000),
    .TLB_ENTRIES(32),
    .MIG_ADDR_WIDTH(27)
) u_computer (
    .clk(ui_clk),
    .rst(computer_rst),
    .pad(pad),
    .ext_int(1'b0),
    .timer_int(1'b0),
    .soft_int(1'b0),
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
    .i_paddr_out(i_paddr_out),
    .d_paddr_out(d_paddr_out),
    .i_page_fault_out(i_page_fault_out),
    .d_page_fault_out(d_page_fault_out),
    .satp_out(satp_out),
    .ui_clk_sync_rst(ui_clk_sync_rst),
    .init_calib_complete(init_calib_complete),
    .app_addr(comp_app_addr),
    .app_cmd(comp_app_cmd),
    .app_en(comp_app_en),
    .app_wdf_data(comp_app_wdf_data),
    .app_wdf_end(comp_app_wdf_end),
    .app_wdf_wren(comp_app_wdf_wren),
    .app_wdf_mask(comp_app_wdf_mask),
    .app_rdy(app_rdy),
    .app_wdf_rdy(app_wdf_rdy),
    .app_rd_data(app_rd_data),
    .app_rd_data_end(app_rd_data_end),
    .app_rd_data_valid(app_rd_data_valid)
);

always @(*) begin
    ddr3_ck_p_sdram <= ddr3_ck_p_fpga;
    ddr3_ck_n_sdram <= ddr3_ck_n_fpga;
    ddr3_addr_sdram <= ddr3_addr_fpga;
    ddr3_ba_sdram <= ddr3_ba_fpga;
    ddr3_ras_n_sdram <= ddr3_ras_n_fpga;
    ddr3_cas_n_sdram <= ddr3_cas_n_fpga;
    ddr3_we_n_sdram <= ddr3_we_n_fpga;
    ddr3_cke_sdram <= ddr3_cke_fpga;
    ddr3_dm_sdram_tmp <= ddr3_dm_fpga;
    ddr3_odt_sdram_tmp <= ddr3_odt_fpga;
end

genvar dqwd;
generate
    for(dqwd = 0; dqwd < 16; dqwd = dqwd + 1) begin: dq_delay
        WireDelay #(
            .Delay_g(0),
            .Delay_rd(0),
            .ERR_INSERT("OFF")
        ) u_delay_dq (
            .A(ddr3_dq_fpga[dqwd]),
            .B(ddr3_dq_sdram[dqwd]),
            .reset(sys_rst_n),
            .phy_init_done(init_calib_complete)
        );
    end
endgenerate

genvar dqswd;
generate
    for(dqswd = 0; dqswd < 2; dqswd = dqswd + 1) begin: dqs_delay
        WireDelay #(
            .Delay_g(0),
            .Delay_rd(0),
            .ERR_INSERT("OFF")
        ) u_delay_dqs_p (
            .A(ddr3_dqs_p_fpga[dqswd]),
            .B(ddr3_dqs_p_sdram[dqswd]),
            .reset(sys_rst_n),
            .phy_init_done(init_calib_complete)
        );

        WireDelay #(
            .Delay_g(0),
            .Delay_rd(0),
            .ERR_INSERT("OFF")
        ) u_delay_dqs_n (
            .A(ddr3_dqs_n_fpga[dqswd]),
            .B(ddr3_dqs_n_sdram[dqswd]),
            .reset(sys_rst_n),
            .phy_init_done(init_calib_complete)
        );
    end
endgenerate

ddr3_model u_ddr3_model (
    .rst_n(ddr3_reset_n),
    .ck(ddr3_ck_p_sdram),
    .ck_n(ddr3_ck_n_sdram),
    .cke(ddr3_cke_sdram[0]),
    .cs_n(1'b0),
    .ras_n(ddr3_ras_n_sdram),
    .cas_n(ddr3_cas_n_sdram),
    .we_n(ddr3_we_n_sdram),
    .dm_tdqs(ddr3_dm_sdram),
    .ba(ddr3_ba_sdram),
    .addr(ddr3_addr_sdram),
    .dq(ddr3_dq_sdram),
    .dqs(ddr3_dqs_p_sdram),
    .dqs_n(ddr3_dqs_n_sdram),
    .tdqs_n(),
    .odt(ddr3_odt_sdram[0])
);

initial begin
    board_clk = 1'b0;
    forever #(CLKIN_PERIOD_PS/2) board_clk = ~board_clk;
end

initial begin
    sys_rst_n = 1'b0;
    #RESET_PERIOD_PS;
    sys_rst_n = 1'b1;
end

task automatic clear_tb_app;
    begin
        tb_app_addr = 27'b0;
        tb_app_cmd = CMD_READ;
        tb_app_en = 1'b0;
        tb_app_wdf_data = 128'b0;
        tb_app_wdf_end = 1'b0;
        tb_app_wdf_wren = 1'b0;
        tb_app_wdf_mask = 16'hffff;
    end
endtask

task automatic app_write_line;
    input [26:0] addr;
    input [127:0] data;
    integer n;
    reg cmd_done;
    reg wdf_done;
    begin
        cmd_done = 1'b0;
        wdf_done = 1'b0;

        tb_app_addr = addr;
        tb_app_cmd = CMD_WRITE;
        tb_app_wdf_data = data;
        tb_app_wdf_mask = 16'h0000;
        tb_app_wdf_end = 1'b1;
        tb_app_en = 1'b1;
        tb_app_wdf_wren = 1'b1;

        for(n = 0; n < APP_TIMEOUT_CYCLES && !(cmd_done && wdf_done); n = n + 1) begin
            @(posedge ui_clk);
            if(!cmd_done && app_rdy)
                cmd_done = 1'b1;
            if(!wdf_done && app_wdf_rdy)
                wdf_done = 1'b1;
            @(negedge ui_clk);
            if(cmd_done)
                tb_app_en = 1'b0;
            if(wdf_done) begin
                tb_app_wdf_wren = 1'b0;
                tb_app_wdf_end = 1'b0;
            end
        end

        tb_app_en = 1'b0;
        tb_app_wdf_wren = 1'b0;
        tb_app_wdf_end = 1'b0;

        if(!(cmd_done && wdf_done)) begin
            $display("FAIL: MIG app write timeout addr=%0d cmd_done=%b wdf_done=%b app_rdy=%b app_wdf_rdy=%b",
                     addr, cmd_done, wdf_done, app_rdy, app_wdf_rdy);
            errors = errors + 1;
        end

        repeat(10) @(posedge ui_clk);
    end
endtask

task automatic app_read_line;
    input [26:0] addr;
    output [127:0] data;
    integer n;
    reg cmd_done;
    reg rd_done;
    begin
        cmd_done = 1'b0;
        rd_done = 1'b0;
        data = 128'hx;

        tb_app_addr = addr;
        tb_app_cmd = CMD_READ;
        tb_app_wdf_data = 128'b0;
        tb_app_wdf_mask = 16'hffff;
        tb_app_wdf_end = 1'b0;
        tb_app_wdf_wren = 1'b0;
        tb_app_en = 1'b1;

        for(n = 0; n < APP_TIMEOUT_CYCLES && !cmd_done; n = n + 1) begin
            @(posedge ui_clk);
            if(app_rdy)
                cmd_done = 1'b1;
            @(negedge ui_clk);
            if(cmd_done)
                tb_app_en = 1'b0;
        end

        tb_app_en = 1'b0;

        if(!cmd_done) begin
            $display("FAIL: MIG app read command timeout addr=%0d app_rdy=%b", addr, app_rdy);
            errors = errors + 1;
        end

        for(n = 0; n < APP_TIMEOUT_CYCLES && !rd_done; n = n + 1) begin
            @(posedge ui_clk);
            if(app_rd_data_valid && app_rd_data_end) begin
                data = app_rd_data;
                rd_done = 1'b1;
            end
        end

        if(!rd_done) begin
            $display("FAIL: MIG app read data timeout addr=%0d app_rd_data_valid=%b app_rd_data_end=%b",
                     addr, app_rd_data_valid, app_rd_data_end);
            errors = errors + 1;
        end

        repeat(10) @(posedge ui_clk);
    end
endtask

task automatic check_line;
    input [127:0] actual;
    input [127:0] expected;
    input [8*32-1:0] message;
    begin
        if(actual !== expected) begin
            $display("FAIL: %0s expected %032h got %032h", message, expected, actual);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s = %032h", message, actual);
        end
    end
endtask

task automatic wait_reg;
    input [4:0] addr;
    input [31:0] expected;
    input [8*32-1:0] message;
    integer n;
    reg seen;
    begin
        test_addr = addr;
        seen = 1'b0;
        for(n = 0; n < CPU_TIMEOUT_CYCLES; n = n + 1) begin
            @(posedge ui_clk);
            #100;
            if(test_data === expected) begin
                seen = 1'b1;
                n = CPU_TIMEOUT_CYCLES;
            end
        end

        if(!seen) begin
            $display("FAIL: %0s expected %08h got %08h pc=%08h state=%0d", message, expected, test_data, pc_out, state);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s x%0d = %08h", message, addr, test_data);
        end
    end
endtask

reg [127:0] readback0;
reg [127:0] readback1;
reg [127:0] data_line;

initial begin
    errors = 0;
    test_addr = 5'd0;
    tb_master_active = 1'b1;
    cpu_released = 1'b0;
    clear_tb_app();

    $display("Waiting for MIG calibration...");
    wait(init_calib_complete === 1'b1);
    $display("PASS: MIG init_calib_complete asserted");
    repeat(20) @(posedge ui_clk);

    $display("Preloading smoke program through the MIG app interface...");
    app_write_line(PROGRAM_ADDR0, PROGRAM_LINE0);
    app_write_line(PROGRAM_ADDR1, PROGRAM_LINE1);
    app_read_line(PROGRAM_ADDR0, readback0);
    app_read_line(PROGRAM_ADDR1, readback1);
    check_line(readback0, PROGRAM_LINE0, "DDR program line 0");
    check_line(readback1, PROGRAM_LINE1, "DDR program line 1");

    @(negedge ui_clk);
    tb_master_active = 1'b0;
    cpu_released = 1'b1;
    clear_tb_app();
    $display("Released computer core; CPU fetches instructions from DDR3 through I-cache.");

    wait_reg(5'd3, 32'd42, "CPU load after DDR-backed store");
    wait_reg(5'd4, 32'd90, "CPU byte load after DDR-backed byte store");

    if(i_page_fault_out || d_page_fault_out) begin
        $display("FAIL: unexpected page fault i=%b d=%b", i_page_fault_out, d_page_fault_out);
        errors = errors + 1;
    end else begin
        $display("PASS: no page faults in bare-mode DDR smoke");
    end

    @(negedge ui_clk);
    cpu_released = 1'b0;
    tb_master_active = 1'b1;
    repeat(10) @(posedge ui_clk);

    app_read_line(DATA_ADDR_40, data_line);
    if(data_line[31:0] !== 32'h00005a2a) begin
        $display("FAIL: DDR line 0x40 word expected 00005a2a got %08h full_line=%032h", data_line[31:0], data_line);
        errors = errors + 1;
    end else begin
        $display("PASS: DDR line 0x40 word = %08h", data_line[31:0]);
    end

    if(errors == 0)
        $display("COMPUTER DDR SMOKE PASS");
    else
        $display("COMPUTER DDR SMOKE FAIL errors=%0d", errors);

    $finish;
end

endmodule
