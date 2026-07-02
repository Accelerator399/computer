`timescale 1ns/1ps

module tb_core_linux_smoke_preload;

localparam integer LINUX_BANNER_LEN = 33;
localparam integer BAD_BANNER_LEN = 7;
localparam integer LINE_ADDR_BITS = 20;
localparam integer LINE_COUNT = 1 << LINE_ADDR_BITS;

localparam [8*LINUX_BANNER_LEN-1:0] LINUX_BANNER = "Hello from RV32 Linux on computer";
localparam [8*BAD_BANNER_LEN-1:0] BAD_BANNER = "BADBOOT";

reg clk;
reg rst;
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
wire [31:0] i_vaddr_out;
wire [31:0] d_vaddr_out;
wire [31:0] i_paddr_out;
wire [31:0] d_paddr_out;
wire i_page_fault_out;
wire d_page_fault_out;
wire [31:0] satp_out;
wire [31:0] i_tlb_miss_count_out;
wire [31:0] d_tlb_miss_count_out;
wire [31:0] pad;

wire icache_mem_req;
wire icache_mem_we;
wire [31:0] icache_mem_addr;
wire [127:0] icache_mem_wdata;
wire [15:0] icache_mem_wstrb;
reg [127:0] icache_mem_rdata;
reg icache_mem_ready;

wire dcache_mem_req;
wire dcache_mem_we;
wire [31:0] dcache_mem_addr;
wire [127:0] dcache_mem_wdata;
wire [15:0] dcache_mem_wstrb;
reg [127:0] dcache_mem_rdata;
reg dcache_mem_ready;

wire walker_mem_req;
wire [31:0] walker_mem_addr;
reg [127:0] walker_mem_rdata;
reg walker_mem_ready;

reg [127:0] line_mem [0:LINE_COUNT-1];
reg [1023:0] preload_path;
reg [31:0] preload_addr;
reg [127:0] preload_data;

integer cycle;
integer errors;
integer run_timeout_cycles;
integer preload_fh;
integer preload_scan;
integer preload_count;
integer linux_match_pos;
integer bad_match_pos;
integer mmio_byte_count;
integer k;
reg linux_banner_seen;
reg bad_banner_seen;
reg mmio_uart_write_prev;

computer_core #(
    .CLK_FREQ(100_000_000),
    .BAUD_RATE(115200)
) u_core (
    .clk(clk),
    .rst(rst),
    .pad(pad),
    .uart_rx_in(pad[10]),
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
    .i_vaddr_out(i_vaddr_out),
    .d_vaddr_out(d_vaddr_out),
    .i_paddr_out(i_paddr_out),
    .d_paddr_out(d_paddr_out),
    .i_page_fault_out(i_page_fault_out),
    .d_page_fault_out(d_page_fault_out),
    .satp_out(satp_out),
    .i_tlb_miss_count_out(i_tlb_miss_count_out),
    .d_tlb_miss_count_out(d_tlb_miss_count_out),
    .uart_tx_out(),
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

wire mmio_uart_write = u_core.u_iomux.tx_start;
wire [7:0] mmio_uart_data = u_core.u_iomux.tx_data;

function automatic [LINE_ADDR_BITS-1:0] line_index;
    input [31:0] addr;
    begin
        line_index = addr[LINE_ADDR_BITS+3:4];
    end
endfunction

function automatic [7:0] linux_banner_byte;
    input integer index;
    begin
        linux_banner_byte = LINUX_BANNER[(LINUX_BANNER_LEN-1-index)*8 +: 8];
    end
endfunction

function automatic [7:0] bad_banner_byte;
    input integer index;
    begin
        bad_banner_byte = BAD_BANNER[(BAD_BANNER_LEN-1-index)*8 +: 8];
    end
endfunction

task automatic write_line;
    input [31:0] addr;
    input [127:0] data;
    input [15:0] wstrb;
    integer b;
    reg [LINE_ADDR_BITS-1:0] idx;
    begin
        idx = line_index(addr);
        for(b = 0; b < 16; b = b + 1) begin
            if(wstrb[b])
                line_mem[idx][b*8 +: 8] = data[b*8 +: 8];
        end
    end
endtask

task automatic check;
    input condition;
    input [160*8-1:0] message;
    begin
        if(!condition) begin
            $display("FAIL: %0s", message);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s", message);
        end
    end
endtask

task automatic check_reg;
    input [4:0] reg_addr;
    input [31:0] expected;
    input [160*8-1:0] message;
    begin
        test_addr = reg_addr;
        #1;
        if(test_data !== expected) begin
            $display("FAIL: %0s expected=%08h got=%08h pc=%08h inst=%08h state=%0d priv=%0d i_pa=%08h d_pa=%08h",
                     message, expected, test_data, pc_out, inst_out, state,
                     privilege_out, i_paddr_out, d_paddr_out);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s x%0d=%08h", message, reg_addr, test_data);
        end
    end
endtask

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

initial begin
    if(!$value$plusargs("PRELOAD=%s", preload_path))
        preload_path = "software/image/linux_smoke_preload.memh";

    for(k = 0; k < LINE_COUNT; k = k + 1)
        line_mem[k] = 128'b0;

    preload_count = 0;
    preload_fh = $fopen(preload_path, "r");
    if(preload_fh == 0) begin
        $display("FAIL: unable to open preload file %0s", preload_path);
        $fatal(1);
    end

    while(!$feof(preload_fh)) begin
        preload_scan = $fscanf(preload_fh, "%h %h", preload_addr, preload_data);
        if(preload_scan == 2) begin
            line_mem[line_index(preload_addr)] = preload_data;
            preload_count = preload_count + 1;
        end
    end
    $fclose(preload_fh);
    $display("Loaded %0d preload lines from %0s", preload_count, preload_path);
end

always @(posedge clk) begin
    if(rst) begin
        icache_mem_rdata <= 128'b0;
        icache_mem_ready <= 1'b0;
        dcache_mem_rdata <= 128'b0;
        dcache_mem_ready <= 1'b0;
        walker_mem_rdata <= 128'b0;
        walker_mem_ready <= 1'b0;
    end else begin
        icache_mem_ready <= icache_mem_req;
        dcache_mem_ready <= dcache_mem_req;
        walker_mem_ready <= walker_mem_req;

        if(icache_mem_req)
            icache_mem_rdata <= line_mem[line_index(icache_mem_addr)];
        if(dcache_mem_req) begin
            dcache_mem_rdata <= line_mem[line_index(dcache_mem_addr)];
            if(dcache_mem_we)
                write_line(dcache_mem_addr, dcache_mem_wdata, dcache_mem_wstrb);
        end
        if(walker_mem_req)
            walker_mem_rdata <= line_mem[line_index(walker_mem_addr)];
    end
end

always @(posedge clk) begin
    if(rst) begin
        linux_match_pos <= 0;
        bad_match_pos <= 0;
        mmio_byte_count <= 0;
        linux_banner_seen <= 1'b0;
        bad_banner_seen <= 1'b0;
        mmio_uart_write_prev <= 1'b0;
    end else begin
        mmio_uart_write_prev <= mmio_uart_write;
        if(mmio_uart_write && !mmio_uart_write_prev) begin
            mmio_byte_count <= mmio_byte_count + 1;
            $display("MMIO_UART byte[%0d]=%02h '%c' pc=%08h inst=%08h priv=%0d i_pa=%08h d_pa=%08h",
                     mmio_byte_count, mmio_uart_data, mmio_uart_data,
                     pc_out, inst_out, privilege_out, i_paddr_out, d_paddr_out);

            if(linux_match_pos < LINUX_BANNER_LEN && mmio_uart_data == linux_banner_byte(linux_match_pos))
                linux_match_pos <= linux_match_pos + 1;
            else if(mmio_uart_data == linux_banner_byte(0))
                linux_match_pos <= 1;
            else
                linux_match_pos <= 0;

            if(bad_match_pos < BAD_BANNER_LEN && mmio_uart_data == bad_banner_byte(bad_match_pos))
                bad_match_pos <= bad_match_pos + 1;
            else if(mmio_uart_data == bad_banner_byte(0))
                bad_match_pos <= 1;
            else
                bad_match_pos <= 0;

            if((linux_match_pos == LINUX_BANNER_LEN - 1) && (mmio_uart_data == linux_banner_byte(LINUX_BANNER_LEN - 1)))
                linux_banner_seen <= 1'b1;
            if((bad_match_pos == BAD_BANNER_LEN - 1) && (mmio_uart_data == bad_banner_byte(BAD_BANNER_LEN - 1)))
                bad_banner_seen <= 1'b1;
        end
    end
end

initial begin
    rst = 1'b1;
    test_addr = 5'd0;
    errors = 0;
    run_timeout_cycles = 500000;
    if(!$value$plusargs("TIMEOUT_CYCLES=%d", run_timeout_cycles))
        run_timeout_cycles = 500000;

    repeat(5) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < run_timeout_cycles; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if(linux_banner_seen || bad_banner_seen)
            cycle = run_timeout_cycles;
    end

    check(linux_banner_seen, "preloaded OpenSBI-lite hands off to linux-smoke banner");
    check(!bad_banner_seen, "preloaded OpenSBI-lite linux-smoke does not take bad_boot");
    check(privilege_out == 2'b01, "preloaded linux-smoke runs in S-mode");
    check(satp_out == 32'h0000_0000, "preloaded linux-smoke remains in bare mode");
    check(!i_page_fault_out && !d_page_fault_out, "preloaded linux-smoke has no page faults");
    check_reg(5'd10, 32'h0000_0000, "preloaded linux-smoke a0 remains hartid");
    check_reg(5'd11, 32'h0080_0000, "preloaded linux-smoke a1 remains dtb address");

    if(errors == 0) begin
        $display("CORE LINUX PRELOAD SMOKE PASS");
        $finish;
    end else begin
        $display("CORE LINUX PRELOAD SMOKE FAIL errors=%0d pc=%08h inst=%08h state=%0d priv=%0d i_pa=%08h d_pa=%08h mmio_bytes=%0d linux_match=%0d bad_match=%0d",
                 errors, pc_out, inst_out, state, privilege_out, i_paddr_out,
                 d_paddr_out, mmio_byte_count, linux_match_pos, bad_match_pos);
        $fatal(1);
    end
end

endmodule
