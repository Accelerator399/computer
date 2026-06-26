`timescale 1ps/1ps

module tb_computer_ddr_linux_boot;

localparam integer CLKIN_PERIOD_PS = 10000;
localparam integer RESET_PERIOD_PS = 200000;
localparam integer APP_TIMEOUT_CYCLES = 20000;
localparam integer DEFAULT_TIMEOUT_CYCLES = 1200000;
localparam integer UART_BIT_CYCLES = 100000000 / 115200;
localparam integer LINUX_BANNER_LEN = 33;
localparam integer FW_BANNER_LEN = 4;
localparam integer BAD_BANNER_LEN = 7;

localparam [8*LINUX_BANNER_LEN-1:0] LINUX_BANNER = "Hello from RV32 Linux on computer";
localparam [8*FW_BANNER_LEN-1:0] FW_BANNER = "FWOK";
localparam [8*BAD_BANNER_LEN-1:0] BAD_BANNER = "BADBOOT";
localparam [2:0] CMD_WRITE = 3'b000;
localparam [2:0] CMD_READ  = 3'b001;

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
wire uart_tx_mon;
wire mmio_uart_write_mon;
wire [7:0] mmio_uart_data_mon;

integer errors;
integer uart_log_fh;
integer preload_fh;
integer preload_scan;
integer timeout_cycles;
integer run_timeout_cycles;
integer expect_banner;
integer verify_preload;
integer verify_preload_only;
integer plusarg_seen;
integer uart_sample_count;
integer uart_bit_index;
integer uart_match_pos;
integer uart_bad_match_pos;
integer uart_byte_count;
reg uart_sampling;
reg uart_prev;
reg banner_seen;
reg bad_banner_seen;
reg mmio_banner_seen;
reg mmio_bad_banner_seen;
reg [7:0] uart_sample_byte;
reg [1023:0] preload_path;
reg [1023:0] uart_log_path;
reg [31:0] preload_addr;
reg [127:0] preload_data;
reg [7:0] uart_banner_byte;
reg [31:0] debug_a0;
reg [31:0] debug_a1;
integer mmio_match_pos;
integer mmio_bad_match_pos;
integer mmio_byte_count;
reg mmio_uart_write_prev;

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

assign uart_tx_mon = u_computer.u_core.u_iomux.uart_tx_sig;
assign mmio_uart_write_mon = u_computer.u_core.u_iomux.tx_start;
assign mmio_uart_data_mon = u_computer.u_core.u_iomux.tx_data;

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

function automatic [7:0] banner_byte;
    input integer index;
    begin
        if(expect_banner == 2)
            banner_byte = FW_BANNER[(FW_BANNER_LEN-1-index)*8 +: 8];
        else
            banner_byte = LINUX_BANNER[(LINUX_BANNER_LEN-1-index)*8 +: 8];
    end
endfunction

function automatic integer banner_len;
    begin
        if(expect_banner == 2)
            banner_len = FW_BANNER_LEN;
        else
            banner_len = LINUX_BANNER_LEN;
    end
endfunction

function automatic integer next_match_pos;
    input integer pos;
    input [7:0] byte_value;
    begin
        if(pos >= banner_len())
            next_match_pos = banner_len();
        else if(byte_value == banner_byte(pos))
            next_match_pos = pos + 1;
        else if(byte_value == banner_byte(0))
            next_match_pos = 1;
        else
            next_match_pos = 0;
end
endfunction

function automatic [7:0] bad_banner_byte;
    input integer index;
    begin
        bad_banner_byte = BAD_BANNER[(BAD_BANNER_LEN-1-index)*8 +: 8];
    end
endfunction

function automatic integer next_bad_match_pos;
    input integer pos;
    input [7:0] byte_value;
    begin
        if(pos >= BAD_BANNER_LEN)
            next_bad_match_pos = BAD_BANNER_LEN;
        else if(byte_value == bad_banner_byte(pos))
            next_bad_match_pos = pos + 1;
        else if(byte_value == bad_banner_byte(0))
            next_bad_match_pos = 1;
        else
            next_bad_match_pos = 0;
    end
endfunction

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
    reg data_done;
    begin
        cmd_done = 1'b0;
        data_done = 1'b0;
        data = 128'b0;

        tb_app_addr = addr;
        tb_app_cmd = CMD_READ;
        tb_app_en = 1'b1;
        tb_app_wdf_data = 128'b0;
        tb_app_wdf_mask = 16'hffff;
        tb_app_wdf_end = 1'b0;
        tb_app_wdf_wren = 1'b0;

        for(n = 0; n < APP_TIMEOUT_CYCLES && !(cmd_done && data_done); n = n + 1) begin
            @(posedge ui_clk);
            if(!cmd_done && app_rdy)
                cmd_done = 1'b1;
            if(app_rd_data_valid) begin
                data = app_rd_data;
                data_done = 1'b1;
            end
            @(negedge ui_clk);
            if(cmd_done)
                tb_app_en = 1'b0;
        end

        tb_app_en = 1'b0;

        if(!(cmd_done && data_done)) begin
            $display("FAIL: MIG app read timeout addr=%0h cmd_done=%b data_done=%b app_rdy=%b app_rd_data_valid=%b",
                     addr, cmd_done, data_done, app_rdy, app_rd_data_valid);
            errors = errors + 1;
        end

        repeat(10) @(posedge ui_clk);
    end
endtask

task automatic verify_preload_line;
    input [31:0] addr;
    input [127:0] expected;
    reg [127:0] actual;
    begin
        app_read_line(addr[26:0], actual);
        if(actual !== expected) begin
            $display("FAIL: preload verify addr=%08h expected=%032h got=%032h",
                     addr, expected, actual);
            errors = errors + 1;
        end else begin
            $display("PASS: preload verify addr=%08h data=%032h", addr, actual);
        end
    end
endtask

task automatic preload_to_ddr_from_file;
    input [1023:0] path;
    integer fh;
    integer scan;
    begin
        fh = $fopen(path, "r");
        if(fh == 0) begin
            $display("FAIL: unable to open preload file %0s", path);
            errors = errors + 1;
        end else begin
            while(!$feof(fh)) begin
                scan = $fscanf(fh, "%h %h", preload_addr, preload_data);
                if(scan == 2) begin
                    if(preload_addr[3:0] != 4'b0000) begin
                        $display("WARN: preload line address not 16-byte aligned: %08h", preload_addr);
                    end
                    app_write_line(preload_addr[26:0], preload_data);
                end
            end
            $fclose(fh);
        end
    end
endtask

always @(posedge ui_clk) begin
    if(computer_rst) begin
        uart_prev <= 1'b1;
        uart_sampling <= 1'b0;
        uart_sample_count <= 0;
        uart_bit_index <= 0;
        uart_sample_byte <= 8'b0;
        uart_match_pos <= 0;
        uart_bad_match_pos <= 0;
        uart_byte_count <= 0;
        uart_banner_byte <= 8'b0;
    end else begin
        uart_prev <= uart_tx_mon;

        if(!uart_sampling) begin
            if(uart_prev && !uart_tx_mon) begin
                uart_sampling <= 1'b1;
                uart_sample_count <= UART_BIT_CYCLES + (UART_BIT_CYCLES / 2);
                uart_bit_index <= 0;
                uart_sample_byte <= 8'b0;
            end
        end else begin
            if(uart_sample_count > 0) begin
                uart_sample_count <= uart_sample_count - 1;
            end else begin
                if(uart_bit_index < 8) begin
                    uart_sample_byte[uart_bit_index] <= uart_tx_mon;
                    uart_bit_index <= uart_bit_index + 1;
                    uart_sample_count <= UART_BIT_CYCLES - 1;
                end else begin
                    uart_sampling <= 1'b0;
                    uart_byte_count <= uart_byte_count + 1;
                    if(uart_tx_mon !== 1'b1) begin
                        $display("FAIL: UART framing error after %0d bytes", uart_byte_count);
                        errors = errors + 1;
                    end else begin
                        if(uart_log_fh != 0) begin
                            $fwrite(uart_log_fh, "%c", uart_sample_byte);
                            $fflush(uart_log_fh);
                        end
                        $write("%c", uart_sample_byte);
                        uart_banner_byte = uart_sample_byte;
                        uart_match_pos <= next_match_pos(uart_match_pos, uart_sample_byte);
                        uart_bad_match_pos <= next_bad_match_pos(uart_bad_match_pos, uart_sample_byte);
                        if(next_match_pos(uart_match_pos, uart_sample_byte) == banner_len())
                            banner_seen <= 1'b1;
                        if(next_bad_match_pos(uart_bad_match_pos, uart_sample_byte) == BAD_BANNER_LEN)
                            bad_banner_seen <= 1'b1;
                    end
                end
            end
        end
    end
end

always @(posedge ui_clk) begin
    if(computer_rst) begin
        mmio_match_pos <= 0;
        mmio_bad_match_pos <= 0;
        mmio_byte_count <= 0;
        mmio_banner_seen <= 1'b0;
        mmio_bad_banner_seen <= 1'b0;
        mmio_uart_write_prev <= 1'b0;
    end else begin
        mmio_uart_write_prev <= mmio_uart_write_mon;
        if(mmio_uart_write_mon && !mmio_uart_write_prev) begin
            mmio_byte_count <= mmio_byte_count + 1;
            mmio_match_pos <= next_match_pos(mmio_match_pos, mmio_uart_data_mon);
            mmio_bad_match_pos <= next_bad_match_pos(mmio_bad_match_pos, mmio_uart_data_mon);
            if(next_match_pos(mmio_match_pos, mmio_uart_data_mon) == banner_len())
                mmio_banner_seen <= 1'b1;
            if(next_bad_match_pos(mmio_bad_match_pos, mmio_uart_data_mon) == BAD_BANNER_LEN)
                mmio_bad_banner_seen <= 1'b1;
        end
    end
end

initial begin
    board_clk = 1'b0;
    forever #(CLKIN_PERIOD_PS/2) board_clk = ~board_clk;
end

initial begin
    sys_rst_n = 1'b0;
    #RESET_PERIOD_PS;
    sys_rst_n = 1'b1;
end

initial begin
    errors = 0;
    test_addr = 5'd0;
    tb_master_active = 1'b1;
    cpu_released = 1'b0;
    banner_seen = 1'b0;
    bad_banner_seen = 1'b0;
    mmio_banner_seen = 1'b0;
    mmio_bad_banner_seen = 1'b0;
    uart_log_fh = 0;
    clear_tb_app();

    if(!$value$plusargs("PRELOAD=%s", preload_path))
        preload_path = "software/image/linux_preload.memh";
    if(!$value$plusargs("UART_LOG=%s", uart_log_path))
        uart_log_path = "software/image/uart.log";
    run_timeout_cycles = DEFAULT_TIMEOUT_CYCLES;
    expect_banner = 1;
    verify_preload = 0;
    verify_preload_only = 0;
    plusarg_seen = $value$plusargs("TIMEOUT_CYCLES=%d", run_timeout_cycles);
    plusarg_seen = $value$plusargs("EXPECT_BANNER=%d", expect_banner);
    plusarg_seen = $value$plusargs("VERIFY_PRELOAD=%d", verify_preload);
    plusarg_seen = $value$plusargs("VERIFY_PRELOAD_ONLY=%d", verify_preload_only);

    uart_log_fh = $fopen(uart_log_path, "w");
    if(uart_log_fh == 0)
        $display("WARN: unable to open UART log %0s", uart_log_path);

    wait(init_calib_complete === 1'b1);
    $display("PASS: MIG init_calib_complete asserted");
    repeat(20) @(posedge ui_clk);

    $display("Loading preload image from %0s", preload_path);
    $display("Preloading Linux payload through the MIG app interface...");
    preload_to_ddr_from_file(preload_path);
    if(errors != 0) begin
        $display("FAIL: preload failed; stopping before CPU release");
        $finish;
    end

    if(verify_preload != 0) begin
        verify_preload_line(32'h0000_0000, 128'h0000b2b7305290730f82829300000297);
        verify_preload_line(32'h0000_0010, 128'h3032907322200293302290731ff28293);
        verify_preload_line(32'h0040_0000, 128'h100102b702559663008002b702051a63);
        verify_preload_line(32'h0040_0010, 128'h00038863000343830443031300000317);
        verify_preload_line(32'h0040_0020, 128'h10500073ff1ff06f001303130072a023);
        verify_preload_line(32'h0040_0050, 128'h52206d6f7266206f6c6c6548ff1ff06f);
        if(errors != 0) begin
            $display("FAIL: preload readback verification failed; stopping before CPU release");
            $finish;
        end
        if(verify_preload_only != 0) begin
            $display("COMPUTER DDR PRELOAD VERIFY PASS");
            $finish;
        end
    end

    @(negedge ui_clk);
    tb_master_active = 1'b0;
    cpu_released = 1'b1;
    clear_tb_app();
    $display("Released computer core for Linux boot simulation.");
    $display("Waiting up to %0d ui_clk cycles; expect_banner=%0d banner_len=%0d",
             run_timeout_cycles, expect_banner, banner_len());

    for(timeout_cycles = 0;
        timeout_cycles < run_timeout_cycles &&
        !banner_seen && !mmio_banner_seen &&
        !bad_banner_seen && !mmio_bad_banner_seen;
        timeout_cycles = timeout_cycles + 1) begin
        @(posedge ui_clk);
    end

    if(bad_banner_seen || mmio_bad_banner_seen) begin
        test_addr = 5'd10;
        @(posedge ui_clk);
        debug_a0 = test_data;
        test_addr = 5'd11;
        @(posedge ui_clk);
        debug_a1 = test_data;
        $display("FAIL: Linux smoke entered bad_boot pc=%08h inst=%08h state=%0d priv=%0d satp=%08h i_pa=%08h d_pa=%08h i_pf=%b d_pf=%b uart_bytes=%0d mmio_uart_bytes=%0d mmio_match=%0d mmio_bad_match=%0d a0=%08h a1=%08h",
                 pc_out, inst_out, state, privilege_out, satp_out, i_paddr_out, d_paddr_out,
                 i_page_fault_out, d_page_fault_out, uart_byte_count, mmio_byte_count,
                 mmio_match_pos, mmio_bad_match_pos, debug_a0, debug_a1);
        $finish;
    end

    if(!banner_seen && !mmio_banner_seen && expect_banner != 0) begin
        test_addr = 5'd10;
        @(posedge ui_clk);
        debug_a0 = test_data;
        test_addr = 5'd11;
        @(posedge ui_clk);
        debug_a1 = test_data;
        $display("FAIL: Linux boot timeout pc=%08h inst=%08h state=%0d priv=%0d satp=%08h i_pa=%08h d_pa=%08h i_pf=%b d_pf=%b uart_bytes=%0d mmio_uart_bytes=%0d mmio_match=%0d mmio_bad_match=%0d a0=%08h a1=%08h",
                 pc_out, inst_out, state, privilege_out, satp_out, i_paddr_out, d_paddr_out,
                 i_page_fault_out, d_page_fault_out, uart_byte_count, mmio_byte_count,
                 mmio_match_pos, mmio_bad_match_pos, debug_a0, debug_a1);
        $finish;
    end

    if(expect_banner == 2) begin
        if(errors == 0)
            $display("COMPUTER DDR OPENSBI-LITE UART PASS pc=%08h inst=%08h state=%0d priv=%0d satp=%08h uart_bytes=%0d mmio_uart_bytes=%0d",
                     pc_out, inst_out, state, privilege_out, satp_out, uart_byte_count, mmio_byte_count);
        else
            $display("COMPUTER DDR OPENSBI-LITE UART FAIL errors=%0d", errors);
        $finish;
    end

    if(expect_banner == 0) begin
        if(errors == 0)
            $display("COMPUTER DDR LINUX PRELOAD SMOKE PASS pc=%08h inst=%08h state=%0d priv=%0d satp=%08h uart_bytes=%0d mmio_uart_bytes=%0d banner_seen=%b",
                     pc_out, inst_out, state, privilege_out, satp_out, uart_byte_count, mmio_byte_count, banner_seen);
        else
            $display("COMPUTER DDR LINUX PRELOAD SMOKE FAIL errors=%0d", errors);
        $finish;
    end

    if(privilege_out !== 2'b01) begin
        $display("FAIL: Linux banner seen but CPU is not in S-mode, priv=%0d", privilege_out);
        errors = errors + 1;
    end

    if(i_page_fault_out || d_page_fault_out) begin
        $display("FAIL: Linux banner seen but page fault flags are set i=%b d=%b", i_page_fault_out, d_page_fault_out);
        errors = errors + 1;
    end

    if(errors == 0)
        $display("COMPUTER DDR LINUX BOOT PASS");
    else
        $display("COMPUTER DDR LINUX BOOT FAIL errors=%0d", errors);

    $finish;
end

endmodule
