`timescale 1ns/1ps

module tb_atomic;

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
reg [31:0] mem_rdata;
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

reg [31:0] data_mem [0:255];

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

function automatic [31:0] addi;
    input [4:0] rd;
    input [4:0] rs1;
    input [11:0] imm;
    begin
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
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
            32'h0000_0000: rom = addi(5'd1, 5'd0, 12'h100); // base
            32'h0000_0004: rom = addi(5'd2, 5'd0, 12'h005); // +5
            32'h0000_0008: rom = sw(5'd2, 5'd1, 12'h000);   // mem = 5
            32'h0000_000c: rom = amo(5'b00010, 5'd3, 5'd1, 5'd0); // lr.w x3,(x1)
            32'h0000_0010: rom = addi(5'd4, 5'd0, 12'h009); // +9
            32'h0000_0014: rom = amo(5'b00011, 5'd5, 5'd1, 5'd4); // sc.w success, mem = 9
            32'h0000_0018: rom = amo(5'b00011, 5'd6, 5'd1, 5'd4); // sc.w fail
            32'h0000_001c: rom = amo(5'b00000, 5'd7, 5'd1, 5'd2); // amoadd: 9 -> 14
            32'h0000_0020: rom = amo(5'b00001, 5'd8, 5'd1, 5'd4); // amoswap: 14 -> 9
            32'h0000_0024: rom = amo(5'b00100, 5'd9, 5'd1, 5'd2); // amoxor: 9 -> 12
            32'h0000_0028: rom = amo(5'b01100, 5'd10, 5'd1, 5'd4); // amoand: 12 -> 8
            32'h0000_002c: rom = amo(5'b01000, 5'd11, 5'd1, 5'd2); // amoor: 8 -> 13
            32'h0000_0030: rom = addi(5'd12, 5'd0, 12'hfff); // -1
            32'h0000_0034: rom = amo(5'b10000, 5'd13, 5'd1, 5'd12); // amomin: 13 -> -1
            32'h0000_0038: rom = amo(5'b10100, 5'd14, 5'd1, 5'd4); // amomax: -1 -> 9
            32'h0000_003c: rom = amo(5'b11000, 5'd15, 5'd1, 5'd12); // amominu: 9 -> 9
            32'h0000_0040: rom = amo(5'b11100, 5'd16, 5'd1, 5'd12); // amomaxu: 9 -> -1
            32'h0000_0044: rom = jal_zero(21'h0);
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

integer i;
integer cycle;
wire [7:0] data_word_addr = mem_addr[9:2];

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

always @(*) begin
    mem_rdata = data_mem[data_word_addr];
end

always @(posedge clk) begin
    if(mem_write) begin
        if(mem_wstrb[0]) data_mem[data_word_addr][7:0] <= mem_wdata[7:0];
        if(mem_wstrb[1]) data_mem[data_word_addr][15:8] <= mem_wdata[15:8];
        if(mem_wstrb[2]) data_mem[data_word_addr][23:16] <= mem_wdata[23:16];
        if(mem_wstrb[3]) data_mem[data_word_addr][31:24] <= mem_wdata[31:24];
    end
end

initial begin
    for(i = 0; i < 256; i = i + 1)
        data_mem[i] = 32'b0;

    rst = 1'b1;
    test_addr = 5'd0;
    external_csr_rdata = 32'b0;

    repeat(5) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < 260; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if(pc == 32'h0000_0044 && state == CPU_IF)
            cycle = 260;
    end

    check(pc == 32'h0000_0044, "atomic program reaches the final spin");
    check_reg(5'd3, 32'h0000_0005, "lr.w returns the loaded word");
    check_reg(5'd5, 32'h0000_0000, "sc.w succeeds after lr.w");
    check_reg(5'd6, 32'h0000_0001, "sc.w fails after reservation is consumed");
    check_reg(5'd7, 32'h0000_0009, "amoadd.w returns the old value");
    check_reg(5'd8, 32'h0000_000e, "amoswap.w returns the old value");
    check_reg(5'd9, 32'h0000_0009, "amoxor.w returns the old value");
    check_reg(5'd10, 32'h0000_000c, "amoand.w returns the old value");
    check_reg(5'd11, 32'h0000_0008, "amoor.w returns the old value");
    check_reg(5'd13, 32'h0000_000d, "amomin.w returns the old value");
    check_reg(5'd14, 32'hffff_ffff, "amomax.w returns the old value");
    check_reg(5'd15, 32'h0000_0009, "amominu.w returns the old value");
    check_reg(5'd16, 32'h0000_0009, "amomaxu.w returns the old value");
    check(data_mem[8'h40] == 32'hffff_ffff, "atomic operations update memory");
    check(!sfence_vma && !fence_i, "atomic program does not pulse fence signals");

    $display("ATOMIC CPU PASS");
    $finish;
end

endmodule
