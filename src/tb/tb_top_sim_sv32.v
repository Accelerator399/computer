`timescale 1ns/1ps

module tb_top_sim_sv32;

localparam integer MEM_WORDS = 1100000;
localparam integer CPU_TIMEOUT_CYCLES = 5000;

localparam [31:0] SATP_SV32_ROOT4 = 32'h8000_0004;
localparam [31:0] SUPER_DATA_WORD = 32'h1234_5678;

localparam [7:0] PTE_V = 8'h01;
localparam [7:0] PTE_R = 8'h02;
localparam [7:0] PTE_W = 8'h04;
localparam [7:0] PTE_X = 8'h08;
localparam [7:0] PTE_A = 8'h40;
localparam [7:0] PTE_D = 8'h80;

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
wire [31:0] i_paddr_out;
wire [31:0] d_paddr_out;
wire i_page_fault_out;
wire d_page_fault_out;
wire [31:0] satp_out;
wire [31:0] pad;

reg saw_i_page_fault;
reg saw_d_page_fault;
integer errors;
integer cycle;

top_sim #(
    .MEM_WORDS(MEM_WORDS),
    .INIT_FILE("")
) dut (
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
    .i_paddr_out(i_paddr_out),
    .d_paddr_out(d_paddr_out),
    .i_page_fault_out(i_page_fault_out),
    .d_page_fault_out(d_page_fault_out),
    .satp_out(satp_out)
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

task automatic poke_word;
    input [31:0] addr;
    input [31:0] data;
    begin
        dut.u_mem.mem[addr[31:2]] = data;
    end
endtask

task automatic expect_reg;
    input [4:0] addr;
    input [31:0] expected;
    input [8*48-1:0] message;
    begin
        test_addr = addr;
        #1;
        if(test_data !== expected) begin
            $display("FAIL: %0s expected %08h got %08h pc=%08h inst=%08h state=%0d priv=%0d satp=%08h i_pa=%08h d_pa=%08h",
                     message, expected, test_data, pc_out, inst_out, state, privilege_out,
                     satp_out, i_paddr_out, d_paddr_out);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s x%0d = %08h", message, addr, test_data);
        end
    end
endtask

task automatic check_bool;
    input condition;
    input [8*64-1:0] message;
    begin
        if(!condition) begin
            $display("FAIL: %0s", message);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s", message);
        end
    end
endtask

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

always @(posedge clk) begin
    if(rst) begin
        saw_i_page_fault <= 1'b0;
        saw_d_page_fault <= 1'b0;
    end else begin
        if(i_page_fault_out)
            saw_i_page_fault <= 1'b1;
        if(d_page_fault_out)
            saw_d_page_fault <= 1'b1;
    end
end

initial begin
    errors = 0;
    test_addr = 5'd0;
    rst = 1'b1;

    poke_word(32'h0000_0000, addi(5'd1, 5'd0, 12'h080));
    poke_word(32'h0000_0004, csrrw(12'h305, 5'd1));
    poke_word(32'h0000_0008, lui(5'd1, 20'h80000));
    poke_word(32'h0000_000c, csrrw(12'h341, 5'd1));
    poke_word(32'h0000_0010, addi(5'd1, 5'd1, 12'h004));
    poke_word(32'h0000_0014, csrrw(12'h180, 5'd1));
    poke_word(32'h0000_0018, inst_sfence_vma());
    poke_word(32'h0000_001c, lui(5'd1, 20'h00001));
    poke_word(32'h0000_0020, addi(5'd1, 5'd1, 12'h800));
    poke_word(32'h0000_0024, csrrw(12'h300, 5'd1));
    poke_word(32'h0000_0028, mret());
    poke_word(32'h0000_002c, jal_zero(21'h0));
    poke_word(32'h0000_0080, jal_zero(21'h0));

    poke_word(32'h0000_1000, lui(5'd10, 20'h00400));
    poke_word(32'h0000_1004, addi(5'd10, 5'd10, 12'h040));
    poke_word(32'h0000_1008, lw(5'd5, 5'd10, 12'h000));
    poke_word(32'h0000_100c, lui(5'd11, 20'h80001));
    poke_word(32'h0000_1010, addi(5'd11, 5'd11, 12'h040));
    poke_word(32'h0000_1014, sw(5'd5, 5'd11, 12'h000));
    poke_word(32'h0000_1018, lw(5'd6, 5'd11, 12'h000));
    poke_word(32'h0000_101c, inst_fence_i());
    poke_word(32'h0000_1020, wfi());
    poke_word(32'h0000_1024, addi(5'd7, 5'd0, 12'h05a));
    poke_word(32'h0000_1028, jal_zero(21'h0));

    poke_word(32'h0000_4004, make_pte(22'h000400, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D));
    poke_word(32'h0000_4800, make_pte(22'd5, PTE_V));
    poke_word(32'h0000_5000, make_pte(22'd1, PTE_V | PTE_R | PTE_X | PTE_A | PTE_D));
    poke_word(32'h0000_5004, make_pte(22'd3, PTE_V | PTE_R | PTE_W | PTE_A | PTE_D));
    poke_word(32'h0040_0040, SUPER_DATA_WORD);
    poke_word(32'h0000_3040, 32'b0);

    repeat(8) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < CPU_TIMEOUT_CYCLES; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        test_addr = 5'd7;
        if(test_data === 32'h0000_005a)
            cycle = CPU_TIMEOUT_CYCLES;
    end

    expect_reg(5'd7, 32'h0000_005a, "S-mode payload completed after Sv32 handoff");
    expect_reg(5'd5, SUPER_DATA_WORD, "S-mode load through 4MiB superpage");
    expect_reg(5'd6, SUPER_DATA_WORD, "S-mode store/load through 4KiB page");
    check_bool(privilege_out == 2'b01, "CPU remains in S-mode after mret");
    check_bool(satp_out == SATP_SV32_ROOT4, "satp stores Sv32 root PPN");
    check_bool(!saw_i_page_fault && !saw_d_page_fault, "Sv32 handoff has no page faults");
    check_bool(dut.u_mem.mem[32'h0000_3040 >> 2] == SUPER_DATA_WORD,
               "translated S-mode store reaches physical memory");

    if(errors == 0)
        $display("TOP SIM SV32 PASS");
    else
        $display("TOP SIM SV32 FAIL errors=%0d", errors);

    $finish;
end

endmodule
