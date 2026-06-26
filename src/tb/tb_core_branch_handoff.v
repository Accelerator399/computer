`timescale 1ns/1ps

module tb_core_branch_handoff;

localparam [2:0] CPU_IF = 3'd0;
localparam integer MEM_WORDS = 1048624;
localparam integer S_BASE_WORD = 32'h0040_0000 >> 2;

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

integer cycle;
integer errors;

top_sim #(
    .MEM_WORDS(MEM_WORDS)
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

function automatic [31:0] branch;
    input [2:0] funct3;
    input [4:0] rs1;
    input [4:0] rs2;
    input [12:0] imm;
    begin
        branch = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], 7'b1100011};
    end
endfunction

function automatic [31:0] jal_zero;
    input [20:0] imm;
    begin
        jal_zero = {imm[20], imm[10:1], imm[11], imm[19:12], 5'd0, 7'b1101111};
    end
endfunction

task automatic poke_word;
    input [31:0] addr;
    input [31:0] data;
    begin
        dut.u_mem.mem[addr[31:2]] = data;
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

always @(posedge clk) begin
    if(!rst && state == CPU_IF)
        $display("TRACE pc=%08h inst=%08h priv=%0d i_pa=%08h d_pa=%08h",
                 pc_out, inst_out, privilege_out, i_paddr_out, d_paddr_out);
end

initial begin
    rst = 1'b1;
    test_addr = 5'd0;
    errors = 0;

    poke_word(32'h0000_0000, addi(5'd10, 5'd0, 12'h000));
    poke_word(32'h0000_0004, lui(5'd11, 20'h00800));
    poke_word(32'h0000_0008, lui(5'd5, 20'h00400));
    poke_word(32'h0000_000c, csrrw(12'h341, 5'd5));
    poke_word(32'h0000_0010, lui(5'd5, 20'h00001));
    poke_word(32'h0000_0014, addi(5'd5, 5'd5, 12'h800));
    poke_word(32'h0000_0018, csrrw(12'h300, 5'd5));
    poke_word(32'h0000_001c, mret());

    poke_word(32'h0040_0000, branch(3'b001, 5'd10, 5'd0, 13'd52));
    poke_word(32'h0040_0004, lui(5'd5, 20'h00800));
    poke_word(32'h0040_0008, branch(3'b001, 5'd11, 5'd5, 13'd44));
    poke_word(32'h0040_000c, addi(5'd8, 5'd0, 12'h123));
    poke_word(32'h0040_0010, jal_zero(21'd0));
    poke_word(32'h0040_0034, addi(5'd8, 5'd0, 12'h055));
    poke_word(32'h0040_0038, jal_zero(21'd0));

    repeat(5) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < 300; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if((pc_out == 32'h0040_0010 || pc_out == 32'h0040_0038) && state == CPU_IF)
            cycle = 300;
    end

    check(pc_out == 32'h0040_0010, "computer_core high-address S-mode branch reaches success spin");
    check(privilege_out == 2'b01, "computer_core handoff leaves CPU in S-mode");
    check(satp_out == 32'h0000_0000, "computer_core remains in bare translation mode");
    check(!i_page_fault_out && !d_page_fault_out, "computer_core branch test has no page faults");
    check_reg(5'd10, 32'h0000_0000, "a0 survives through computer_core");
    check_reg(5'd11, 32'h0080_0000, "a1 survives through computer_core");
    check_reg(5'd8, 32'h0000_0123, "computer_core bnez/bne checks fall through");

    if(errors == 0) begin
        $display("CORE BRANCH HANDOFF PASS");
        $finish;
    end else begin
        $display("CORE BRANCH HANDOFF FAIL errors=%0d pc=%08h inst=%08h state=%0d priv=%0d i_pa=%08h d_pa=%08h",
                 errors, pc_out, inst_out, state, privilege_out, i_paddr_out, d_paddr_out);
        $fatal(1);
    end
end

endmodule
