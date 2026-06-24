`timescale 1ps/1ps

module tb_computer_ddr_sv32;

localparam integer CLKIN_PERIOD_PS = 10000;   // 100 MHz board clock
localparam integer RESET_PERIOD_PS = 200000;
localparam integer CPU_TIMEOUT_CYCLES = 50000;
localparam integer APP_TIMEOUT_CYCLES = 20000;
localparam integer GLOBAL_TIMEOUT_CYCLES = 250000;

localparam [26:0] BOOT_ADDR0      = 27'h0000000;
localparam [26:0] BOOT_ADDR1      = 27'h0000010;
localparam [26:0] BOOT_ADDR2      = 27'h0000020;
localparam [26:0] TRAP_ADDR       = 27'h0000080;
localparam [26:0] S_TEXT_ADDR0    = 27'h0001000;
localparam [26:0] S_TEXT_ADDR1    = 27'h0001010;
localparam [26:0] S_TEXT_ADDR2    = 27'h0001020;
localparam [26:0] ROOT_LINE0_ADDR = 27'h0004000;
localparam [26:0] ROOT_VPN512_ADDR= 27'h0004800;
localparam [26:0] L0_LINE0_ADDR   = 27'h0005000;
localparam [26:0] S_DATA_DST_ADDR = 27'h0003040;
localparam [26:0] SUPER_DATA_ADDR = 27'h0400040;

localparam [31:0] SATP_SV32_ROOT4 = 32'h8000_0004;
localparam [31:0] SUPER_DATA_WORD = 32'h1234_5678;

localparam [2:0] CMD_WRITE = 3'b000;
localparam [2:0] CMD_READ  = 3'b001;

localparam [7:0] PTE_V = 8'h01;
localparam [7:0] PTE_R = 8'h02;
localparam [7:0] PTE_W = 8'h04;
localparam [7:0] PTE_X = 8'h08;
localparam [7:0] PTE_A = 8'h40;
localparam [7:0] PTE_D = 8'h80;

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

reg saw_i_page_fault;
reg saw_d_page_fault;
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

function automatic [31:0] addi;
    input [4:0] rd;
    input [4:0] rs1;
    input [11:0] imm;
    begin
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    end
endfunction

function automatic [31:0] lui;
    input [4:0] rd;
    input [19:0] imm;
    begin
        lui = {imm, rd, 7'b0110111};
    end
endfunction

function automatic [31:0] lw;
    input [4:0] rd;
    input [4:0] rs1;
    input [11:0] imm;
    begin
        lw = {imm, rs1, 3'b010, rd, 7'b0000011};
    end
endfunction

function automatic [31:0] sw;
    input [4:0] rs2;
    input [4:0] rs1;
    input [11:0] imm;
    begin
        sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    end
endfunction

function automatic [31:0] csrrw;
    input [11:0] csr;
    input [4:0] rs1;
    begin
        csrrw = {csr, rs1, 3'b001, 5'd0, 7'b1110011};
    end
endfunction

function automatic [31:0] mret;
    begin
        mret = 32'h3020_0073;
    end
endfunction

function automatic [31:0] inst_sfence_vma;
    begin
        inst_sfence_vma = 32'h1200_0073;
    end
endfunction

function automatic [31:0] inst_fence_i;
    begin
        inst_fence_i = 32'h0000_100f;
    end
endfunction

function automatic [31:0] wfi;
    begin
        wfi = 32'h1050_0073;
    end
endfunction

function automatic [31:0] jal_zero;
    input [20:0] imm;
    begin
        jal_zero = {imm[20], imm[10:1], imm[11], imm[19:12], 5'd0, 7'b1101111};
    end
endfunction

function automatic [31:0] make_pte;
    input [21:0] ppn;
    input [7:0] flags;
    begin
        make_pte = {ppn, 10'b0} | {24'b0, flags};
    end
endfunction

function automatic [127:0] line4;
    input [31:0] w0;
    input [31:0] w1;
    input [31:0] w2;
    input [31:0] w3;
    begin
        line4 = {w3, w2, w1, w0};
    end
endfunction

initial begin
    board_clk = 1'b0;
    forever #(CLKIN_PERIOD_PS/2) board_clk = ~board_clk;
end

initial begin
    sys_rst_n = 1'b0;
    #RESET_PERIOD_PS;
    sys_rst_n = 1'b1;
end

always @(posedge ui_clk) begin
    if(computer_rst) begin
        saw_i_page_fault <= 1'b0;
        saw_d_page_fault <= 1'b0;
    end else begin
        if(i_page_fault_out)
            saw_i_page_fault <= 1'b1;
        if(d_page_fault_out)
            saw_d_page_fault <= 1'b1;
    end
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
            $display("FAIL: MIG app write timeout addr=%0h cmd_done=%b wdf_done=%b app_rdy=%b app_wdf_rdy=%b",
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
            $display("FAIL: MIG app read command timeout addr=%0h app_rdy=%b", addr, app_rdy);
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
            $display("FAIL: MIG app read data timeout addr=%0h app_rd_data_valid=%b app_rd_data_end=%b",
                     addr, app_rd_data_valid, app_rd_data_end);
            errors = errors + 1;
        end

        repeat(10) @(posedge ui_clk);
    end
endtask

task automatic check_line;
    input [127:0] actual;
    input [127:0] expected;
    input [8*48-1:0] message;
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
    input [8*48-1:0] message;
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
            $display("FAIL: %0s expected %08h got %08h pc=%08h inst=%08h state=%0d priv=%0d satp=%08h i_pf=%b d_pf=%b",
                     message, expected, test_data, pc_out, inst_out, state, privilege_out, satp_out,
                     saw_i_page_fault, saw_d_page_fault);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s x%0d = %08h", message, addr, test_data);
        end
    end
endtask

task automatic wait_done;
    integer n;
    reg seen;
    begin
        test_addr = 5'd7;
        seen = 1'b0;
        for(n = 0; n < CPU_TIMEOUT_CYCLES; n = n + 1) begin
            @(posedge ui_clk);
            #100;
            if(test_data === 32'h0000_005a) begin
                seen = 1'b1;
                n = CPU_TIMEOUT_CYCLES;
            end
        end

        if(!seen) begin
            $display("FAIL: S-mode payload did not complete expected x7=%08h got %08h pc=%08h inst=%08h state=%0d priv=%0d satp=%08h i_pa=%08h d_pa=%08h i_pf=%b d_pf=%b",
                     32'h0000_005a, test_data, pc_out, inst_out, state, privilege_out, satp_out,
                     i_paddr_out, d_paddr_out, saw_i_page_fault, saw_d_page_fault);
            errors = errors + 1;
        end else begin
            $display("PASS: S-mode payload completed after DDR Sv32 walks x7 = %08h", test_data);
        end
    end
endtask

task automatic check_bool;
    input condition;
    input [8*56-1:0] message;
    begin
        if(!condition) begin
            $display("FAIL: %0s", message);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s", message);
        end
    end
endtask

task automatic wait_app_read_quiet;
    integer n;
    integer quiet_cycles;
    begin
        quiet_cycles = 0;
        for(n = 0; n < APP_TIMEOUT_CYCLES && quiet_cycles < 512; n = n + 1) begin
            @(posedge ui_clk);
            if(app_rd_data_valid)
                quiet_cycles = 0;
            else
                quiet_cycles = quiet_cycles + 1;
        end

        if(quiet_cycles < 512) begin
            $display("FAIL: MIG app read response did not become quiet before TB takeover");
            errors = errors + 1;
        end
    end
endtask

reg [127:0] dst_line;
reg [127:0] verify_line;

initial begin
    wait(init_calib_complete === 1'b1);
    repeat(GLOBAL_TIMEOUT_CYCLES) @(posedge ui_clk);
    $display("FAIL: global timeout pc=%08h inst=%08h state=%0d priv=%0d satp=%08h i_pa=%08h d_pa=%08h i_pf=%b d_pf=%b test_addr=%0d test_data=%08h",
             pc_out, inst_out, state, privilege_out, satp_out, i_paddr_out, d_paddr_out,
             saw_i_page_fault, saw_d_page_fault, test_addr, test_data);
    $finish;
end

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

    $display("Preloading M-mode boot, S-mode payload, and Sv32 page tables into DDR3...");
    app_write_line(BOOT_ADDR0, line4(
        addi(5'd1, 5'd0, 12'h080),
        csrrw(12'h305, 5'd1),
        lui(5'd1, 20'h80000),
        csrrw(12'h341, 5'd1)
    ));
    app_write_line(BOOT_ADDR1, line4(
        addi(5'd1, 5'd1, 12'h004),
        csrrw(12'h180, 5'd1),
        inst_sfence_vma(),
        lui(5'd1, 20'h00001)
    ));
    app_write_line(BOOT_ADDR2, line4(
        addi(5'd1, 5'd1, 12'h800),
        csrrw(12'h300, 5'd1),
        mret(),
        jal_zero(21'h0)
    ));
    app_write_line(TRAP_ADDR, line4(jal_zero(21'h0), jal_zero(21'h0), jal_zero(21'h0), jal_zero(21'h0)));

    app_write_line(S_TEXT_ADDR0, line4(
        lui(5'd10, 20'h00400),
        addi(5'd10, 5'd10, 12'h040),
        lw(5'd5, 5'd10, 12'h000),
        lui(5'd11, 20'h80001)
    ));
    app_write_line(S_TEXT_ADDR1, line4(
        addi(5'd11, 5'd11, 12'h040),
        sw(5'd5, 5'd11, 12'h000),
        lw(5'd6, 5'd11, 12'h000),
        inst_fence_i()
    ));
    app_write_line(S_TEXT_ADDR2, line4(
        wfi(),
        addi(5'd7, 5'd0, 12'h05a),
        jal_zero(21'h0),
        jal_zero(21'h0)
    ));

    app_write_line(ROOT_LINE0_ADDR, line4(
        32'b0,
        make_pte(22'h000400, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D),
        32'b0,
        32'b0
    ));
    app_write_line(ROOT_VPN512_ADDR, line4(
        make_pte(22'd5, PTE_V),
        32'b0,
        32'b0,
        32'b0
    ));
    app_write_line(L0_LINE0_ADDR, line4(
        make_pte(22'd1, PTE_V | PTE_R | PTE_X | PTE_A | PTE_D),
        make_pte(22'd3, PTE_V | PTE_R | PTE_W | PTE_A | PTE_D),
        32'b0,
        32'b0
    ));
    app_write_line(SUPER_DATA_ADDR, line4(SUPER_DATA_WORD, 32'b0, 32'b0, 32'b0));
    app_write_line(S_DATA_DST_ADDR, line4(32'b0, 32'b0, 32'b0, 32'b0));

    $display("Read back DDR3 preload lines before releasing the CPU...");
    app_read_line(BOOT_ADDR0, verify_line);
    check_line(verify_line, line4(
        addi(5'd1, 5'd0, 12'h080),
        csrrw(12'h305, 5'd1),
        lui(5'd1, 20'h80000),
        csrrw(12'h341, 5'd1)
    ), "DDR boot line 0");
    app_read_line(S_TEXT_ADDR0, verify_line);
    check_line(verify_line, line4(
        lui(5'd10, 20'h00400),
        addi(5'd10, 5'd10, 12'h040),
        lw(5'd5, 5'd10, 12'h000),
        lui(5'd11, 20'h80001)
    ), "DDR S-mode text line 0");
    app_read_line(ROOT_LINE0_ADDR, verify_line);
    check_line(verify_line, line4(
        32'b0,
        make_pte(22'h000400, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D),
        32'b0,
        32'b0
    ), "DDR root page-table line 0");
    app_read_line(ROOT_VPN512_ADDR, verify_line);
    check_line(verify_line, line4(
        make_pte(22'd5, PTE_V),
        32'b0,
        32'b0,
        32'b0
    ), "DDR root page-table VPN512 line");
    app_read_line(L0_LINE0_ADDR, verify_line);
    check_line(verify_line, line4(
        make_pte(22'd1, PTE_V | PTE_R | PTE_X | PTE_A | PTE_D),
        make_pte(22'd3, PTE_V | PTE_R | PTE_W | PTE_A | PTE_D),
        32'b0,
        32'b0
    ), "DDR L0 page-table line 0");
    app_read_line(SUPER_DATA_ADDR, verify_line);
    check_line(verify_line, line4(SUPER_DATA_WORD, 32'b0, 32'b0, 32'b0),
               "DDR superpage source data line");

    @(negedge ui_clk);
    tb_master_active = 1'b0;
    cpu_released = 1'b1;
    clear_tb_app();
    $display("Released computer core; CPU enables Sv32 and walks DDR3-backed page tables.");

    wait_done();
    wait_reg(5'd5, SUPER_DATA_WORD, "S-mode load through 4MiB superpage");
    wait_reg(5'd6, SUPER_DATA_WORD, "S-mode store/load through 4KiB page");

    check_bool(privilege_out == 2'b01, "CPU remains in S-mode after M-mode handoff");
    check_bool(satp_out == SATP_SV32_ROOT4, "satp points at DDR3 root page table");
    check_bool(!saw_i_page_fault && !saw_d_page_fault, "DDR3 Sv32 run has no page faults");

    @(negedge ui_clk);
    cpu_released = 1'b0;
    tb_master_active = 1'b1;
    repeat(10) @(posedge ui_clk);
    wait_app_read_quiet();

    app_read_line(S_DATA_DST_ADDR, dst_line);
    check_line(dst_line, line4(SUPER_DATA_WORD, 32'b0, 32'b0, 32'b0),
               "DDR3 destination line contains S-mode store data");

    if(errors == 0)
        $display("COMPUTER DDR SV32 PASS");
    else
        $display("COMPUTER DDR SV32 FAIL errors=%0d", errors);

    $finish;
end

endmodule
