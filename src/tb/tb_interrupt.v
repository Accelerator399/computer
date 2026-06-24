`timescale 1ns/1ps

module tb_interrupt;

localparam [2:0] CPU_IF = 3'd0;

reg clk;
reg rst;
reg timer_int;
reg soft_int;
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

reg timer_requested;
reg soft_requested;
reg saw_timer_irq;
reg saw_soft_irq;
reg saw_timer_return;
reg saw_soft_return;

cpu dut (
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
    .timer_int(timer_int),
    .soft_int(soft_int),
    .test_addr(test_addr),
    .test_data(test_data),
    .state(state)
);

function automatic [31:0] addi;
    input [4:0] rd;
    input [4:0] rs1;
    input [11:0] imm;
    begin
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    end
endfunction

function automatic [31:0] csrrw;
    input [11:0] csr;
    input [4:0] rs1;
    begin
        csrrw = {csr, rs1, 3'b001, 5'd0, 7'b1110011};
    end
endfunction

function automatic [31:0] csrrs;
    input [4:0] rd;
    input [11:0] csr;
    input [4:0] rs1;
    begin
        csrrs = {csr, rs1, 3'b010, rd, 7'b1110011};
    end
endfunction

function automatic [31:0] mret;
    begin
        mret = 32'h3020_0073;
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
            32'h0000_0000: rom = addi(5'd1, 5'd0, 12'h080);
            32'h0000_0004: rom = csrrw(12'h305, 5'd1); // mtvec = 0x80
            32'h0000_0008: rom = addi(5'd1, 5'd0, 12'h088);
            32'h0000_000c: rom = csrrw(12'h304, 5'd1); // mie.MTIE | mie.MSIE
            32'h0000_0010: rom = addi(5'd1, 5'd0, 12'h008);
            32'h0000_0014: rom = csrrw(12'h300, 5'd1); // mstatus.MIE
            32'h0000_0018: rom = addi(5'd5, 5'd0, 12'h011);
            32'h0000_001c: rom = addi(5'd6, 5'd0, 12'h022);
            32'h0000_0020: rom = addi(5'd9, 5'd0, 12'h044);
            32'h0000_0024: rom = addi(5'd10, 5'd0, 12'h055);
            32'h0000_0028: rom = addi(5'd11, 5'd0, 12'h066);
            32'h0000_002c: rom = addi(5'd12, 5'd0, 12'h077);
            32'h0000_0030: rom = jal_zero(21'h0);

            32'h0000_0080: rom = csrrs(5'd13, 12'h342, 5'd0); // mcause
            32'h0000_0084: rom = addi(5'd14, 5'd0, 12'h033);
            32'h0000_0088: rom = mret();

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

integer cycle;

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

always @(posedge clk) begin
    if(rst) begin
        timer_requested <= 1'b0;
        soft_requested <= 1'b0;
        saw_timer_irq <= 1'b0;
        saw_soft_irq <= 1'b0;
        saw_timer_return <= 1'b0;
        saw_soft_return <= 1'b0;
        timer_int <= 1'b0;
        soft_int <= 1'b0;
    end else begin
        if(!timer_requested && pc >= 32'h0000_001c && pc < 32'h0000_0080) begin
            timer_requested <= 1'b1;
            timer_int <= 1'b1;
        end

        if(pc == 32'h0000_0080 && dut.cs.mcause_reg == 32'h8000_0007) begin
            saw_timer_irq <= 1'b1;
            timer_int <= 1'b0;
        end

        if(saw_timer_irq && pc >= 32'h0000_0028 && pc < 32'h0000_0080)
            saw_timer_return <= 1'b1;

        if(saw_timer_return && !soft_requested && pc >= 32'h0000_0028 && pc < 32'h0000_0080) begin
            soft_requested <= 1'b1;
            soft_int <= 1'b1;
        end

        if(pc == 32'h0000_0080 && dut.cs.mcause_reg == 32'h8000_0003) begin
            saw_soft_irq <= 1'b1;
            soft_int <= 1'b0;
        end

        if(saw_soft_irq && pc >= 32'h0000_0030 && pc < 32'h0000_0080)
            saw_soft_return <= 1'b1;
    end
end

initial begin
    rst = 1'b1;
    test_addr = 5'd0;
    external_csr_rdata = 32'b0;

    repeat(5) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < 260; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if(pc == 32'h0000_0030 && state == CPU_IF && saw_soft_return)
            cycle = 260;
    end

    check(pc == 32'h0000_0030, "interrupt program reaches the final spin");
    check(saw_timer_irq, "machine timer interrupt traps with mcause=0x80000007");
    check(saw_timer_return, "mret returns after machine timer interrupt");
    check(saw_soft_irq, "machine software interrupt traps with mcause=0x80000003");
    check(saw_soft_return, "mret returns after machine software interrupt");
    check_reg(5'd5, 32'h0000_0011, "main code executed before interrupts");
    check_reg(5'd10, 32'h0000_0055, "main code continued after timer interrupt");
    check_reg(5'd12, 32'h0000_0077, "main code continued after software interrupt");
    check_reg(5'd13, 32'h8000_0003, "handler reads the last interrupt cause");
    check_reg(5'd14, 32'h0000_0033, "interrupt handler executed");
    check(!sfence_vma && !fence_i, "interrupt test does not pulse fence signals");

    $display("INTERRUPT CPU PASS");
    $finish;
end

endmodule
