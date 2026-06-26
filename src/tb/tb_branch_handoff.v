`timescale 1ns/1ps

module tb_branch_handoff;

localparam [2:0] CPU_IF = 3'd0;
localparam [1:0] PRIV_S = 2'b01;

reg clk;
reg rst;
reg [4:0] test_addr;
reg [31:0] external_csr_rdata;

wire [31:0] pc;
wire [31:0] inst;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0] mem_wstrb;
wire mem_write;
wire external_csr_we;
wire [11:0] external_csr_addr;
wire [31:0] external_csr_wdata;
wire sfence_vma;
wire fence_i;
wire mstatus_sum;
wire mstatus_mxr;
wire [1:0] privilege_mode;
wire [31:0] test_data;
wire [2:0] state;

integer cycle;
integer errors;

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

function automatic [31:0] rom;
    input [31:0] addr;
    begin
        case(addr)
            32'h0000_0000: rom = addi(5'd10, 5'd0, 12'h000); // a0 = hartid 0
            32'h0000_0004: rom = lui(5'd11, 20'h00800);       // a1 = dtb 0x00800000
            32'h0000_0008: rom = lui(5'd5, 20'h00400);        // t0 = S-mode entry
            32'h0000_000c: rom = csrrw(12'h341, 5'd5);        // mepc = 0x00400000
            32'h0000_0010: rom = lui(5'd5, 20'h00001);
            32'h0000_0014: rom = addi(5'd5, 5'd5, 12'h800);   // t0 = MSTATUS_MPP_S
            32'h0000_0018: rom = csrrw(12'h300, 5'd5);
            32'h0000_001c: rom = mret();

            32'h0040_0000: rom = branch(3'b001, 5'd10, 5'd0, 13'd32); // bnez a0, bad
            32'h0040_0004: rom = lui(5'd5, 20'h00800);
            32'h0040_0008: rom = branch(3'b001, 5'd11, 5'd5, 13'd24); // bne a1, t0, bad
            32'h0040_000c: rom = addi(5'd8, 5'd0, 12'h123);
            32'h0040_0010: rom = jal_zero(21'd0);

            32'h0040_0020: rom = addi(5'd8, 5'd0, 12'h055);
            32'h0040_0024: rom = jal_zero(21'd0);

            default: rom = jal_zero(21'd0);
        endcase
    end
endfunction

assign inst = rom(pc);

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
            $display("FAIL: %0s expected=%08h got=%08h pc=%08h inst=%08h state=%0d priv=%0d",
                     message, expected, test_data, pc, inst, state, privilege_mode);
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
        $display("TRACE pc=%08h inst=%08h priv=%0d", pc, inst, privilege_mode);
end

initial begin
    rst = 1'b1;
    test_addr = 5'd0;
    external_csr_rdata = 32'b0;
    errors = 0;

    repeat(5) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < 120; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if((pc == 32'h0040_0010 || pc == 32'h0040_0024) && state == CPU_IF)
            cycle = 120;
    end

    check(pc == 32'h0040_0010, "S-mode branch handoff reaches the success spin");
    check(privilege_mode == PRIV_S, "handoff leaves the CPU in S-mode");
    check_reg(5'd10, 32'h0000_0000, "a0 survives handoff as hartid");
    check_reg(5'd11, 32'h0080_0000, "a1 survives handoff as dtb address");
    check_reg(5'd8, 32'h0000_0123, "bnez/bne checks fall through when arguments match");

    if(errors == 0) begin
        $display("BRANCH HANDOFF PASS");
        $finish;
    end else begin
        $display("BRANCH HANDOFF FAIL errors=%0d pc=%08h inst=%08h state=%0d priv=%0d",
                 errors, pc, inst, state, privilege_mode);
        $fatal(1);
    end
end

endmodule
