`timescale 1ns/1ps

module tb_core_linux_smoke;

localparam integer LINUX_BANNER_LEN = 33;
localparam integer BAD_BANNER_LEN = 7;
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

integer cycle;
integer errors;
integer linux_match_pos;
integer bad_match_pos;
integer mmio_byte_count;
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

function automatic [31:0] word_at;
    input [31:0] addr;
    begin
        case(addr)
            32'h0000_0000: word_at = 32'h0000_0513; // li a0,0
            32'h0000_0004: word_at = 32'h0080_05b7; // lui a1,0x800
            32'h0000_0008: word_at = 32'h0040_02b7; // lui t0,0x400
            32'h0000_000c: word_at = 32'h3412_9073; // csrw mepc,t0
            32'h0000_0010: word_at = 32'h0000_12b7; // lui t0,0x1
            32'h0000_0014: word_at = 32'h8002_8293; // addi t0,t0,-2048
            32'h0000_0018: word_at = 32'h3002_9073; // csrw mstatus,t0
            32'h0000_001c: word_at = 32'h3020_0073; // mret

            32'h0040_0000: word_at = 32'h0205_1a63; // bnez a0,bad_boot
            32'h0040_0004: word_at = 32'h0080_02b7; // lui t0,0x800
            32'h0040_0008: word_at = 32'h0255_9663; // bne a1,t0,bad_boot
            32'h0040_000c: word_at = 32'h1001_02b7; // lui t0,0x10010
            32'h0040_0010: word_at = 32'h0000_0317; // auipc t1,0
            32'h0040_0014: word_at = 32'h0443_0313; // addi t1,t1,68
            32'h0040_0018: word_at = 32'h0003_4383; // lbu t2,0(t1)
            32'h0040_001c: word_at = 32'h0003_8863; // beqz t2,done
            32'h0040_0020: word_at = 32'h0072_a023; // sw t2,0(t0)
            32'h0040_0024: word_at = 32'h0013_0313; // addi t1,t1,1
            32'h0040_0028: word_at = 32'hff1f_f06f; // j loop
            32'h0040_002c: word_at = 32'h1050_0073; // wfi
            32'h0040_0030: word_at = 32'hffdf_f06f; // j done
            32'h0040_0034: word_at = 32'h1001_02b7; // bad_boot: lui t0,0x10010
            32'h0040_0038: word_at = 32'h0000_0317; // auipc t1,0
            32'h0040_003c: word_at = 32'h03e3_0313; // addi t1,t1,62
            32'h0040_0040: word_at = 32'h0003_4383; // lbu t2,0(t1)
            32'h0040_0044: word_at = 32'hfe03_84e3; // beqz t2,done
            32'h0040_0048: word_at = 32'h0072_a023; // sw t2,0(t0)
            32'h0040_004c: word_at = 32'h0013_0313; // addi t1,t1,1
            32'h0040_0050: word_at = 32'hff1f_f06f; // j bad loop

            32'h0040_0054: word_at = 32'h6c6c_6548; // "Hell"
            32'h0040_0058: word_at = 32'h7266_206f; // "o fr"
            32'h0040_005c: word_at = 32'h5220_6d6f; // "om R"
            32'h0040_0060: word_at = 32'h2032_3356; // "V32 "
            32'h0040_0064: word_at = 32'h756e_694c; // "Linu"
            32'h0040_0068: word_at = 32'h6e6f_2078; // "x on"
            32'h0040_006c: word_at = 32'h6d6f_6320; // " com"
            32'h0040_0070: word_at = 32'h6574_7570; // "pute"
            32'h0040_0074: word_at = 32'h4142_0072; // "r\0BA"
            32'h0040_0078: word_at = 32'h4f4f_4244; // "DBOO"
            32'h0040_007c: word_at = 32'h0000_0054; // "T\0"
            default: word_at = 32'h0000_0013; // nop
        endcase
    end
endfunction

function automatic [127:0] line_at;
    input [31:0] addr;
    reg [31:0] base;
    begin
        base = {addr[31:4], 4'b0000};
        line_at = {word_at(base + 32'd12), word_at(base + 32'd8),
                   word_at(base + 32'd4), word_at(base)};
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
            icache_mem_rdata <= line_at(icache_mem_addr);
        if(dcache_mem_req)
            dcache_mem_rdata <= line_at(dcache_mem_addr);
        if(walker_mem_req)
            walker_mem_rdata <= line_at(walker_mem_addr);
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
            $display("MMIO_UART byte[%0d]=%02h '%c' pc=%08h inst=%08h d_pa=%08h",
                     mmio_byte_count, mmio_uart_data, mmio_uart_data,
                     pc_out, inst_out, d_paddr_out);

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

    repeat(5) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < 3000; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if(linux_banner_seen || bad_banner_seen)
            cycle = 3000;
    end

    check(linux_banner_seen, "exact linux-smoke banner is emitted through computer_core MMIO");
    check(!bad_banner_seen, "exact linux-smoke does not take bad_boot path");
    check(privilege_out == 2'b01, "exact linux-smoke runs in S-mode");
    check(satp_out == 32'h0000_0000, "exact linux-smoke remains in bare mode");
    check(!i_page_fault_out && !d_page_fault_out, "exact linux-smoke has no page faults");
    check_reg(5'd10, 32'h0000_0000, "exact linux-smoke a0 remains hartid");
    check_reg(5'd11, 32'h0080_0000, "exact linux-smoke a1 remains dtb address");

    if(errors == 0) begin
        $display("CORE LINUX SMOKE PASS");
        $finish;
    end else begin
        $display("CORE LINUX SMOKE FAIL errors=%0d pc=%08h inst=%08h state=%0d priv=%0d i_pa=%08h d_pa=%08h mmio_bytes=%0d linux_match=%0d bad_match=%0d",
                 errors, pc_out, inst_out, state, privilege_out, i_paddr_out,
                 d_paddr_out, mmio_byte_count, linux_match_pos, bad_match_pos);
        $fatal(1);
    end
end

endmodule
