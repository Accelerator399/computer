`timescale 1ns/1ps

module tb_misaligned;

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

reg any_mem_write_seen;
reg misaligned_store_write_seen;

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
    .mem_rdata(32'h1234_5678),
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

function automatic [31:0] jalr;
    input [4:0] rd;
    input [4:0] rs1;
    input [11:0] imm;
    begin
        jalr = {imm, rs1, 3'b000, rd, 7'b1100111};
    end
endfunction

function automatic [31:0] lh;
    input [4:0] rd;
    input [4:0] rs1;
    input [11:0] imm;
    begin
        lh = {imm, rs1, 3'b001, rd, 7'b0000011};
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

function automatic [31:0] amo;
    input [4:0] funct5;
    input [4:0] rd;
    input [4:0] rs1;
    input [4:0] rs2;
    begin
        amo = {funct5, 2'b00, rs2, rs1, 3'b010, rd, 7'b0101111};
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
            32'h0000_0008: rom = jalr(5'd0, 5'd0, 12'h002);
            32'h0000_000c: rom = addi(5'd31, 5'd0, 12'h7ee);

            32'h0000_0010: rom = addi(5'd1, 5'd0, 12'h0a0);
            32'h0000_0014: rom = csrrw(12'h305, 5'd1); // mtvec = 0xa0
            32'h0000_0018: rom = addi(5'd3, 5'd0, 12'h101);
            32'h0000_001c: rom = lh(5'd4, 5'd3, 12'h000);
            32'h0000_0020: rom = addi(5'd31, 5'd0, 12'h7ee);

            32'h0000_0024: rom = addi(5'd1, 5'd0, 12'h0c0);
            32'h0000_0028: rom = csrrw(12'h305, 5'd1); // mtvec = 0xc0
            32'h0000_002c: rom = addi(5'd2, 5'd0, 12'h055);
            32'h0000_0030: rom = addi(5'd3, 5'd0, 12'h102);
            32'h0000_0034: rom = sw(5'd2, 5'd3, 12'h000);
            32'h0000_0038: rom = addi(5'd31, 5'd0, 12'h7ee);

            32'h0000_003c: rom = addi(5'd1, 5'd0, 12'h0e0);
            32'h0000_0040: rom = csrrw(12'h305, 5'd1); // mtvec = 0xe0
            32'h0000_0044: rom = addi(5'd3, 5'd0, 12'h102);
            32'h0000_0048: rom = amo(5'b00010, 5'd16, 5'd3, 5'd0); // lr.w x16,(x3)
            32'h0000_004c: rom = addi(5'd31, 5'd0, 12'h7ee);
            32'h0000_0050: rom = addi(5'd19, 5'd0, 12'h077);
            32'h0000_0054: rom = jal_zero(21'h0);

            32'h0000_0080: rom = csrrs(5'd10, 12'h342, 5'd0); // mcause
            32'h0000_0084: rom = csrrs(5'd11, 12'h343, 5'd0); // mtval
            32'h0000_0088: rom = addi(5'd1, 5'd0, 12'h010);
            32'h0000_008c: rom = csrrw(12'h341, 5'd1); // mepc = 0x10
            32'h0000_0090: rom = mret();

            32'h0000_00a0: rom = csrrs(5'd12, 12'h342, 5'd0); // mcause
            32'h0000_00a4: rom = csrrs(5'd13, 12'h343, 5'd0); // mtval
            32'h0000_00a8: rom = addi(5'd1, 5'd0, 12'h024);
            32'h0000_00ac: rom = csrrw(12'h341, 5'd1); // mepc = 0x24
            32'h0000_00b0: rom = mret();

            32'h0000_00c0: rom = csrrs(5'd14, 12'h342, 5'd0); // mcause
            32'h0000_00c4: rom = csrrs(5'd15, 12'h343, 5'd0); // mtval
            32'h0000_00c8: rom = addi(5'd1, 5'd0, 12'h03c);
            32'h0000_00cc: rom = csrrw(12'h341, 5'd1); // mepc = 0x3c
            32'h0000_00d0: rom = mret();

            32'h0000_00e0: rom = csrrs(5'd17, 12'h342, 5'd0); // mcause
            32'h0000_00e4: rom = csrrs(5'd18, 12'h343, 5'd0); // mtval
            32'h0000_00e8: rom = addi(5'd1, 5'd0, 12'h050);
            32'h0000_00ec: rom = csrrw(12'h341, 5'd1); // mepc = 0x50
            32'h0000_00f0: rom = mret();

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
        any_mem_write_seen <= 1'b0;
        misaligned_store_write_seen <= 1'b0;
    end else if(mem_write) begin
        any_mem_write_seen <= 1'b1;
        if(mem_addr == 32'h0000_0102)
            misaligned_store_write_seen <= 1'b1;
    end
end

initial begin
    rst = 1'b1;
    test_addr = 5'd0;
    external_csr_rdata = 32'b0;

    repeat(5) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < 420; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if(pc == 32'h0000_0054 && state == CPU_IF)
            cycle = 420;
    end

    check(pc == 32'h0000_0054, "misaligned trap program reaches the final spin");
    check_reg(5'd10, 32'h0000_0000, "instruction address misaligned uses mcause=0");
    check_reg(5'd11, 32'h0000_0002, "instruction address misaligned writes target mtval");
    check_reg(5'd12, 32'h0000_0004, "load address misaligned uses mcause=4");
    check_reg(5'd13, 32'h0000_0101, "load address misaligned writes address mtval");
    check_reg(5'd14, 32'h0000_0006, "store address misaligned uses mcause=6");
    check_reg(5'd15, 32'h0000_0102, "store address misaligned writes address mtval");
    check_reg(5'd17, 32'h0000_0004, "lr.w address misaligned uses load mcause=4");
    check_reg(5'd18, 32'h0000_0102, "lr.w address misaligned writes address mtval");
    check_reg(5'd4, 32'h0000_0000, "misaligned load does not write rd");
    check_reg(5'd16, 32'h0000_0000, "misaligned lr.w does not write rd");
    check_reg(5'd19, 32'h0000_0077, "mret returns after each misaligned trap");
    check_reg(5'd31, 32'h0000_0000, "faulting instructions skip the fail markers");
    check(!any_mem_write_seen, "misaligned store does not assert mem_write");
    check(!misaligned_store_write_seen, "misaligned store has no write side effect");
    check(!sfence_vma && !fence_i, "misaligned trap program does not pulse fence signals");

    $display("MISALIGNED CPU PASS");
    $finish;
end

endmodule
