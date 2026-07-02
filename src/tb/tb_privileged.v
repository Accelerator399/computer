`timescale 1ns/1ps

module tb_privileged;

localparam [1:0] PRIV_U = 2'b00;
localparam [1:0] PRIV_S = 2'b01;
localparam [1:0] PRIV_M = 2'b11;

localparam [2:0] CPU_IF = 3'd0;

reg clk;
reg rst;
reg [4:0] test_addr;

wire [31:0] pc;
wire [31:0] inst;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0] mem_wstrb;
wire mem_write;
wire [31:0] mem_rdata;
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

reg saw_m_ecall;
reg saw_m_ebreak;
reg saw_s_ecall;
reg saw_mret_to_s;
reg saw_sret_to_s;
reg saw_fence_i;

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
    .mem_rdata(mem_rdata),
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

assign mem_rdata = 32'b0;

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

function automatic [31:0] ecall;
    begin
        ecall = 32'h0000_0073;
    end
endfunction

function automatic [31:0] ebreak;
    begin
        ebreak = 32'h0010_0073;
    end
endfunction

function automatic [31:0] mret;
    begin
        mret = 32'h3020_0073;
    end
endfunction

function automatic [31:0] sret;
    begin
        sret = 32'h1020_0073;
    end
endfunction

function automatic [31:0] wfi;
    begin
        wfi = 32'h1050_0073;
    end
endfunction

function automatic [31:0] fence;
    begin
        fence = 32'h0ff0_000f;
    end
endfunction

function automatic [31:0] inst_fence_i;
    begin
        inst_fence_i = 32'h0000_100f;
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
            32'h0000_0000: rom = addi(5'd1, 5'd0, 12'h090);
            32'h0000_0004: rom = csrrw(12'h305, 5'd1); // mtvec = 0x90
            32'h0000_0008: rom = ecall();

            32'h0000_000c: rom = addi(5'd6, 5'd0, 12'h022);
            32'h0000_0010: rom = addi(5'd1, 5'd0, 12'h0a0);
            32'h0000_0014: rom = csrrw(12'h305, 5'd1); // mtvec = 0xa0
            32'h0000_0018: rom = ebreak();

            32'h0000_001c: rom = addi(5'd1, 5'd0, 12'h0c0);
            32'h0000_0020: rom = csrrw(12'h105, 5'd1); // stvec = 0xc0
            32'h0000_0024: rom = addi(5'd1, 5'd0, 12'h200);
            32'h0000_0028: rom = csrrw(12'h302, 5'd1); // delegate S ecall
            32'h0000_002c: rom = lui(5'd1, 20'h00001);
            32'h0000_0030: rom = addi(5'd1, 5'd1, 12'h800);
            32'h0000_0034: rom = csrrw(12'h300, 5'd1); // mstatus.MPP = S
            32'h0000_0038: rom = addi(5'd1, 5'd0, 12'h044);
            32'h0000_003c: rom = csrrw(12'h341, 5'd1); // mepc = 0x44
            32'h0000_0040: rom = mret();

            32'h0000_0044: rom = addi(5'd8, 5'd0, 12'h044);
            32'h0000_0048: rom = ecall();
            32'h0000_004c: rom = addi(5'd10, 5'd0, 12'h066);
            32'h0000_0050: rom = csrrs(5'd11, 12'h301, 5'd0); // misa
            32'h0000_0054: rom = csrrs(5'd12, 12'hf11, 5'd0); // mvendorid
            32'h0000_0058: rom = csrrs(5'd13, 12'hf12, 5'd0); // marchid
            32'h0000_005c: rom = csrrs(5'd14, 12'hf13, 5'd0); // mimpid
            32'h0000_0060: rom = csrrs(5'd15, 12'hf14, 5'd0); // mhartid
            32'h0000_0064: rom = addi(5'd1, 5'd0, 12'h12c);
            32'h0000_0068: rom = csrrw(12'h340, 5'd1); // mscratch = 0x12c
            32'h0000_006c: rom = csrrs(5'd17, 12'h340, 5'd0); // read mscratch
            32'h0000_0070: rom = inst_fence_i();
            32'h0000_0074: rom = fence();
            32'h0000_0078: rom = wfi();
            32'h0000_007c: rom = addi(5'd16, 5'd0, 12'h077);
            32'h0000_0080: rom = jal_zero(21'h0);

            32'h0000_0090: rom = addi(5'd5, 5'd0, 12'h011);
            32'h0000_0094: rom = addi(5'd1, 5'd0, 12'h00c);
            32'h0000_0098: rom = csrrw(12'h341, 5'd1); // mepc = 0x0c
            32'h0000_009c: rom = mret();

            32'h0000_00a0: rom = addi(5'd7, 5'd0, 12'h033);
            32'h0000_00a4: rom = addi(5'd1, 5'd0, 12'h01c);
            32'h0000_00a8: rom = csrrw(12'h341, 5'd1); // mepc = 0x1c
            32'h0000_00ac: rom = mret();

            32'h0000_00c0: rom = addi(5'd9, 5'd0, 12'h055);
            32'h0000_00c4: rom = addi(5'd1, 5'd0, 12'h04c);
            32'h0000_00c8: rom = csrrw(12'h141, 5'd1); // sepc = 0x4c
            32'h0000_00cc: rom = sret();

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
        saw_m_ecall <= 1'b0;
        saw_m_ebreak <= 1'b0;
        saw_s_ecall <= 1'b0;
        saw_mret_to_s <= 1'b0;
        saw_sret_to_s <= 1'b0;
        saw_fence_i <= 1'b0;
    end else begin
        if(pc == 32'h0000_0090 && dut.cs.mcause_reg == 32'd11)
            saw_m_ecall <= 1'b1;
        if(pc == 32'h0000_00a0 && dut.cs.mcause_reg == 32'd3)
            saw_m_ebreak <= 1'b1;
        if(pc == 32'h0000_00c0 && dut.cs.scause_reg == 32'd9)
            saw_s_ecall <= 1'b1;
        if(pc == 32'h0000_0044 && privilege_mode == PRIV_S)
            saw_mret_to_s <= 1'b1;
        if(pc == 32'h0000_004c && privilege_mode == PRIV_S)
            saw_sret_to_s <= 1'b1;
        if(fence_i)
            saw_fence_i <= 1'b1;
    end
end

initial begin
    rst = 1'b1;
    test_addr = 5'd0;
    external_csr_rdata = 32'b0;

    repeat(5) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < 240; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if(pc == 32'h0000_0080 && state == CPU_IF)
            cycle = 240;
    end

    check(pc == 32'h0000_0080, "privileged program reaches the final spin");
    check(saw_m_ecall, "M-mode ecall traps to mtvec with mcause=11");
    check(saw_m_ebreak, "ebreak decodes through funct12 and traps with mcause=3");
    check(saw_mret_to_s, "mret restores S privilege from mstatus.MPP");
    check(saw_s_ecall, "delegated S-mode ecall traps to stvec with scause=9");
    check(saw_sret_to_s, "sret returns through sepc and restores S privilege");
    check_reg(5'd5, 32'h0000_0011, "M ecall handler executed");
    check_reg(5'd6, 32'h0000_0022, "mret returned after the M ecall");
    check_reg(5'd7, 32'h0000_0033, "M ebreak handler executed");
    check_reg(5'd8, 32'h0000_0044, "mret entered S-mode payload");
    check_reg(5'd9, 32'h0000_0055, "S ecall handler executed");
    check_reg(5'd10, 32'h0000_0066, "sret returned to the S-mode payload");
    check_reg(5'd11, 32'h4014_1121, "misa reports RV32 IMAF plus S/U privilege support");
    check_reg(5'd12, 32'h0000_0000, "mvendorid is readable");
    check_reg(5'd13, 32'h0000_0001, "marchid is readable");
    check_reg(5'd14, 32'h0000_0001, "mimpid is readable");
    check_reg(5'd15, 32'h0000_0000, "mhartid is readable");
    check_reg(5'd16, 32'h0000_0077, "fence/fence.i/wfi continue execution");
    check_reg(5'd17, 32'h0000_012c, "mscratch is writable and readable");
    check(saw_fence_i, "fence.i pulses the I-cache flush signal");
    check(privilege_mode == PRIV_S, "final privilege remains S-mode");
    check(!sfence_vma, "non-sfence privileged program does not pulse sfence.vma");

    $display("PRIVILEGED CPU PASS");
    $finish;
end

endmodule
