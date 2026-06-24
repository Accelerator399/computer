`timescale 1ns/1ps

module tb_boot_plic;

localparam [2:0] CPU_IF = 3'd0;
localparam PLIC_BASE = 32'h1003_0000;

reg clk;
reg rst;
reg [4:0] test_addr;

wire [31:0] pc;
wire [31:0] inst;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0] mem_wstrb;
wire mem_write;
wire external_csr_we;
wire [11:0] external_csr_addr;
wire [31:0] external_csr_wdata;
reg [31:0] external_csr_rdata;
wire sfence_vma;
wire fence_i;
wire mstatus_sum;
wire mstatus_mxr;
wire [1:0] privilege_mode;
wire [31:0] test_data;
wire [2:0] state;

reg plic_irq_source;
reg [31:0] plic_addr;
reg [31:0] plic_wdata;
reg [3:0] plic_wstrb;
reg plic_we;
wire [31:0] plic_rdata;
wire plic_irq_out;

wire [31:0] boot_rdata;
wire boot_hit;
reg [31:0] boot_addr;

cpu #(
    .RESET_VECTOR(32'h0000_0080)
) u_cpu (
    .clk(clk),
    .rst(rst),
    .pc(pc),
    .inst(inst),
    .icache_hit(1'b1),
    .i_page_fault(1'b0),
    .i_addr_misaligned(),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_write(mem_write),
    .mem_rdata(32'b0),
    .dcache_hit(1'b1),
    .d_page_fault(1'b0),
    .d_addr_misaligned(),
    .external_csr_we(external_csr_we),
    .external_csr_addr(external_csr_addr),
    .external_csr_wdata(external_csr_wdata),
    .external_csr_rdata(external_csr_rdata),
    .sfence_vma(sfence_vma),
    .fence_i(fence_i),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    .privilege_mode(privilege_mode),
    .ext_int(1'b0),
    .timer_int(1'b0),
    .soft_int(1'b0),
    .test_addr(test_addr),
    .test_data(test_data),
    .state(state)
);

plic #(
    .BASE_ADDR(PLIC_BASE),
    .NUM_SOURCES(2)
) u_plic (
    .clk(clk),
    .rst(rst),
    .irq_sources({1'b0, plic_irq_source}),
    .addr(plic_addr),
    .wdata(plic_wdata),
    .wstrb(plic_wstrb),
    .we(plic_we),
    .rdata(plic_rdata),
    .irq_out(plic_irq_out)
);

boot_rom #(
    .BASE_ADDR(32'h0000_0200),
    .WORDS(4)
) u_boot_rom (
    .addr(boot_addr),
    .rdata(boot_rdata),
    .hit(boot_hit)
);

function automatic [31:0] addi;
    input [4:0] rd;
    input [4:0] rs1;
    input [11:0] imm;
    begin
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    end
endfunction

function automatic [31:0] jal_zero;
    input [20:0] imm;
    begin
        jal_zero = {imm[20], imm[10:1], imm[11], imm[19:12], 5'd0, 7'b1101111};
    end
endfunction

function automatic [31:0] rom;
    input [31:0] addr;
    begin
        case(addr)
            32'h0000_0080: rom = addi(5'd3, 5'd0, 12'h123);
            32'h0000_0084: rom = jal_zero(21'h0);
            default: rom = jal_zero(21'h0);
        endcase
    end
endfunction

assign inst = rom(pc);

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

task automatic check_reg;
    input [4:0] reg_addr;
    input [31:0] expected;
    input string message;
    begin
        test_addr = reg_addr;
        #1;
        check(test_data == expected, message);
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

integer cycle;

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

initial begin
    rst = 1'b1;
    test_addr = 5'd0;
    external_csr_rdata = 32'b0;
    plic_irq_source = 1'b0;
    plic_addr = PLIC_BASE;
    plic_wdata = 32'b0;
    plic_wstrb = 4'b0;
    plic_we = 1'b0;
    boot_addr = 32'h0000_0200;

    repeat(5) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < 80; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if(pc == 32'h0000_0084 && state == CPU_IF)
            cycle = 80;
    end

    check(pc == 32'h0000_0084, "CPU starts from the configured reset vector");
    check_reg(5'd3, 32'h0000_0123, "reset-vector program executed");

    boot_addr = 32'h0000_0200;
    #1;
    check(boot_hit && boot_rdata == 32'h0000_0013, "boot ROM hits at its base and defaults to NOP");
    boot_addr = 32'h0000_0300;
    #1;
    check(!boot_hit && boot_rdata == 32'h0000_0013, "boot ROM misses outside its window");

    plic_irq_source = 1'b1;
    @(posedge clk);
    #1;
    plic_irq_source = 1'b0;
    plic_read_check(PLIC_BASE + 32'h0000_1000, 32'h0000_0002, "PLIC latches pending source 1");
    check(!plic_irq_out, "PLIC output waits for priority and enable");

    plic_write(PLIC_BASE + 32'h0000_0004, 32'h0000_0001);
    plic_write(PLIC_BASE + 32'h0000_2000, 32'h0000_0002);
    plic_write(PLIC_BASE + 32'h0020_0000, 32'h0000_0000);
    check(plic_irq_out, "PLIC asserts external interrupt when enabled pending priority beats threshold");
    plic_read_check(PLIC_BASE + 32'h0020_0004, 32'h0000_0001, "PLIC claim returns source 1");

    plic_write(PLIC_BASE + 32'h0020_0004, 32'h0000_0001);
    check(!plic_irq_out, "PLIC completion clears the interrupt");
    plic_read_check(PLIC_BASE + 32'h0000_1000, 32'h0000_0000, "PLIC pending clears after completion");

    $display("BOOT/PLIC PASS");
    $finish;
end

endmodule
