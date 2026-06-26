`timescale 1ns/1ps

module tb_div;

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
    input [19:0] imm20;
    begin
        lui = {imm20, rd, 7'b0110111};
    end
endfunction

function automatic [31:0] div_inst;
    input [2:0] funct3;
    input [4:0] rd;
    input [4:0] rs1;
    input [4:0] rs2;
    begin
        div_inst = {7'b0000001, rs2, rs1, funct3, rd, 7'b0110011};
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
            32'h0000_0000: rom = addi(5'd1, 5'd0, 12'd20);
            32'h0000_0004: rom = addi(5'd2, 5'd0, 12'd3);
            32'h0000_0008: rom = addi(5'd3, 5'd0, 12'hfec); // -20
            32'h0000_000c: rom = addi(5'd4, 5'd0, 12'hffd); // -3
            32'h0000_0010: rom = lui(5'd5, 20'h80000);      // INT_MIN
            32'h0000_0014: rom = addi(5'd6, 5'd0, 12'hfff); // -1
            32'h0000_0018: rom = div_inst(3'b100, 5'd10, 5'd1, 5'd2); // div 20/3
            32'h0000_001c: rom = div_inst(3'b110, 5'd11, 5'd1, 5'd2); // rem 20%3
            32'h0000_0020: rom = div_inst(3'b101, 5'd12, 5'd1, 5'd2); // divu 20/3
            32'h0000_0024: rom = div_inst(3'b111, 5'd13, 5'd1, 5'd2); // remu 20%3
            32'h0000_0028: rom = div_inst(3'b100, 5'd14, 5'd3, 5'd2); // div -20/3
            32'h0000_002c: rom = div_inst(3'b110, 5'd15, 5'd3, 5'd2); // rem -20%3
            32'h0000_0030: rom = div_inst(3'b100, 5'd16, 5'd1, 5'd4); // div 20/-3
            32'h0000_0034: rom = div_inst(3'b110, 5'd17, 5'd1, 5'd4); // rem 20%-3
            32'h0000_0038: rom = div_inst(3'b100, 5'd18, 5'd3, 5'd4); // div -20/-3
            32'h0000_003c: rom = div_inst(3'b110, 5'd19, 5'd3, 5'd4); // rem -20%-3
            32'h0000_0040: rom = div_inst(3'b101, 5'd20, 5'd3, 5'd2); // divu 0xffffffec/3
            32'h0000_0044: rom = div_inst(3'b111, 5'd21, 5'd3, 5'd2); // remu 0xffffffec%3
            32'h0000_0048: rom = div_inst(3'b100, 5'd22, 5'd1, 5'd0); // div by zero
            32'h0000_004c: rom = div_inst(3'b110, 5'd23, 5'd1, 5'd0); // rem by zero
            32'h0000_0050: rom = div_inst(3'b101, 5'd24, 5'd1, 5'd0); // divu by zero
            32'h0000_0054: rom = div_inst(3'b111, 5'd25, 5'd1, 5'd0); // remu by zero
            32'h0000_0058: rom = div_inst(3'b100, 5'd26, 5'd5, 5'd6); // overflow
            32'h0000_005c: rom = div_inst(3'b110, 5'd27, 5'd5, 5'd6); // overflow rem
            32'h0000_0060: rom = jal_zero(21'h0);
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

initial begin
    rst = 1'b1;
    test_addr = 5'd0;
    external_csr_rdata = 32'b0;

    repeat(5) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < 2000; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if(pc == 32'h0000_0060 && state == CPU_IF)
            cycle = 2000;
    end

    check(pc == 32'h0000_0060, "division program reaches the final spin");
    check_reg(5'd10, 32'h0000_0006, "DIV 20 / 3");
    check_reg(5'd11, 32'h0000_0002, "REM 20 % 3");
    check_reg(5'd12, 32'h0000_0006, "DIVU 20 / 3");
    check_reg(5'd13, 32'h0000_0002, "REMU 20 % 3");
    check_reg(5'd14, 32'hffff_fffa, "DIV -20 / 3 truncates toward zero");
    check_reg(5'd15, 32'hffff_fffe, "REM -20 % 3 keeps dividend sign");
    check_reg(5'd16, 32'hffff_fffa, "DIV 20 / -3 truncates toward zero");
    check_reg(5'd17, 32'h0000_0002, "REM 20 % -3 keeps dividend sign");
    check_reg(5'd18, 32'h0000_0006, "DIV -20 / -3");
    check_reg(5'd19, 32'hffff_fffe, "REM -20 % -3");
    check_reg(5'd20, 32'h5555_554e, "DIVU 0xffffffec / 3");
    check_reg(5'd21, 32'h0000_0002, "REMU 0xffffffec % 3");
    check_reg(5'd22, 32'hffff_ffff, "DIV by zero returns -1");
    check_reg(5'd23, 32'h0000_0014, "REM by zero returns dividend");
    check_reg(5'd24, 32'hffff_ffff, "DIVU by zero returns all ones");
    check_reg(5'd25, 32'h0000_0014, "REMU by zero returns dividend");
    check_reg(5'd26, 32'h8000_0000, "DIV overflow returns INT_MIN");
    check_reg(5'd27, 32'h0000_0000, "REM overflow returns zero");
    check(!mem_write, "division program does not write memory");
    check(!sfence_vma && !fence_i, "division program does not pulse fence signals");

    $display("DIV CPU PASS");
    $finish;
end

endmodule
