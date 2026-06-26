`timescale 1ns/1ps

module tb_fpu;

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

function automatic [31:0] lui;
    input [4:0] rd;
    input [19:0] imm20;
    begin
        lui = {imm20, rd, 7'b0110111};
    end
endfunction

function automatic [31:0] addi;
    input [4:0] rd;
    input [4:0] rs1;
    input [11:0] imm;
    begin
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
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

function automatic [31:0] csrrw;
    input [11:0] csr;
    input [4:0] rs1;
    begin
        csrrw = {csr, rs1, 3'b001, 5'd0, 7'b1110011};
    end
endfunction

function automatic [31:0] fmv_w_x;
    input [4:0] rd;
    input [4:0] rs1;
    begin
        fmv_w_x = {7'b1111000, 5'd0, rs1, 3'b000, rd, 7'b1010011};
    end
endfunction

function automatic [31:0] fmv_x_w;
    input [4:0] rd;
    input [4:0] rs1;
    begin
        fmv_x_w = {7'b1110000, 5'd0, rs1, 3'b000, rd, 7'b1010011};
    end
endfunction

function automatic [31:0] fp_rr;
    input [6:0] funct7;
    input [4:0] rd;
    input [4:0] rs1;
    input [4:0] rs2;
    begin
        fp_rr = {funct7, rs2, rs1, 3'b000, rd, 7'b1010011};
    end
endfunction

function automatic [31:0] fp_rr_rm;
    input [6:0] funct7;
    input [2:0] rm;
    input [4:0] rd;
    input [4:0] rs1;
    input [4:0] rs2;
    begin
        fp_rr_rm = {funct7, rs2, rs1, rm, rd, 7'b1010011};
    end
endfunction

function automatic [31:0] fsgnj;
    input [2:0] funct3;
    input [4:0] rd;
    input [4:0] rs1;
    input [4:0] rs2;
    begin
        fsgnj = {7'b0010000, rs2, rs1, funct3, rd, 7'b1010011};
    end
endfunction

function automatic [31:0] fminmax;
    input [2:0] funct3;
    input [4:0] rd;
    input [4:0] rs1;
    input [4:0] rs2;
    begin
        fminmax = {7'b0010100, rs2, rs1, funct3, rd, 7'b1010011};
    end
endfunction

function automatic [31:0] fcmp;
    input [2:0] funct3;
    input [4:0] rd;
    input [4:0] rs1;
    input [4:0] rs2;
    begin
        fcmp = {7'b1010000, rs2, rs1, funct3, rd, 7'b1010011};
    end
endfunction

function automatic [31:0] fcvt_w_s;
    input [4:0] rd;
    input [4:0] rs1;
    input [4:0] rs2;
    input [2:0] rm;
    begin
        fcvt_w_s = {7'b1100000, rs2, rs1, rm, rd, 7'b1010011};
    end
endfunction

function automatic [31:0] fcvt_s_w;
    input [4:0] rd;
    input [4:0] rs1;
    input [4:0] rs2;
    input [2:0] rm;
    begin
        fcvt_s_w = {7'b1101000, rs2, rs1, rm, rd, 7'b1010011};
    end
endfunction

function automatic [31:0] fclass;
    input [4:0] rd;
    input [4:0] rs1;
    begin
        fclass = {7'b1110000, 5'd0, rs1, 3'b001, rd, 7'b1010011};
    end
endfunction

function automatic [31:0] flw;
    input [4:0] rd;
    input [4:0] rs1;
    input [11:0] imm;
    begin
        flw = {imm, rs1, 3'b010, rd, 7'b0000111};
    end
endfunction

function automatic [31:0] fsw;
    input [4:0] rs2;
    input [4:0] rs1;
    input [11:0] imm;
    begin
        fsw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100111};
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
            32'h0000_0000: rom = lui(5'd1, 20'h3fc00);        // x1 = 1.5f bits
            32'h0000_0004: rom = lui(5'd2, 20'h40100);        // x2 = 2.25f bits
            32'h0000_0008: rom = lui(5'd3, 20'h40000);        // x3 = 2.0f bits
            32'h0000_000c: rom = lui(5'd5, 20'hbfc00);        // x5 = -1.5f bits
            32'h0000_0010: rom = lui(5'd6, 20'h40800);        // x6 = 4.0f bits
            32'h0000_0014: rom = addi(5'd4, 5'd0, 12'h100);   // memory base
            32'h0000_0018: rom = fmv_w_x(5'd1, 5'd1);         // f1 = 1.5
            32'h0000_001c: rom = fmv_w_x(5'd2, 5'd2);         // f2 = 2.25
            32'h0000_0020: rom = fmv_w_x(5'd3, 5'd3);         // f3 = 2.0
            32'h0000_0024: rom = fmv_w_x(5'd5, 5'd5);         // f5 = -1.5
            32'h0000_0028: rom = fmv_w_x(5'd6, 5'd6);         // f6 = 4.0
            32'h0000_002c: rom = fp_rr(7'b0000000, 5'd7, 5'd1, 5'd2);  // f7 = 3.75
            32'h0000_0030: rom = fmv_x_w(5'd10, 5'd7);
            32'h0000_0034: rom = fp_rr(7'b0000100, 5'd8, 5'd2, 5'd1);  // f8 = 0.75
            32'h0000_0038: rom = fmv_x_w(5'd11, 5'd8);
            32'h0000_003c: rom = fp_rr(7'b0001000, 5'd9, 5'd1, 5'd3);  // f9 = 3.0
            32'h0000_0040: rom = fmv_x_w(5'd12, 5'd9);
            32'h0000_0044: rom = fp_rr(7'b0001100, 5'd10, 5'd2, 5'd3); // f10 = 1.125
            32'h0000_0048: rom = fmv_x_w(5'd13, 5'd10);
            32'h0000_004c: rom = fp_rr_rm(7'b0101100, 3'b000, 5'd11, 5'd2, 5'd0); // fsqrt(f2) = 1.5
            32'h0000_0050: rom = fmv_x_w(5'd14, 5'd11);
            32'h0000_0054: rom = fsgnj(3'b000, 5'd12, 5'd1, 5'd5);     // f12 = -1.5
            32'h0000_0058: rom = fmv_x_w(5'd15, 5'd12);
            32'h0000_005c: rom = fsgnj(3'b001, 5'd13, 5'd1, 5'd5);     // f13 = +1.5
            32'h0000_0060: rom = fmv_x_w(5'd16, 5'd13);
            32'h0000_0064: rom = fsgnj(3'b010, 5'd14, 5'd1, 5'd5);     // f14 = -1.5
            32'h0000_0068: rom = fmv_x_w(5'd17, 5'd14);
            32'h0000_006c: rom = fminmax(3'b000, 5'd15, 5'd5, 5'd2);    // f15 = min(-1.5, 2.25)
            32'h0000_0070: rom = fmv_x_w(5'd18, 5'd15);
            32'h0000_0074: rom = fminmax(3'b001, 5'd16, 5'd5, 5'd2);    // f16 = max(-1.5, 2.25)
            32'h0000_0078: rom = fmv_x_w(5'd19, 5'd16);
            32'h0000_007c: rom = fcmp(3'b010, 5'd20, 5'd1, 5'd1);       // feq
            32'h0000_0080: rom = fcmp(3'b001, 5'd21, 5'd5, 5'd2);       // flt
            32'h0000_0084: rom = fcmp(3'b000, 5'd22, 5'd1, 5'd1);       // fle
            32'h0000_0088: rom = fclass(5'd23, 5'd5);                   // class(-1.5)
            32'h0000_008c: rom = fcvt_w_s(5'd24, 5'd2, 5'd0, 3'b001);   // 2.25 -> 2
            32'h0000_0090: rom = fcvt_w_s(5'd25, 5'd6, 5'd1, 3'b001);   // 4.0 -> 4 (unsigned)
            32'h0000_0094: rom = addi(5'd26, 5'd0, 12'h003);            // x26 = 3
            32'h0000_0098: rom = fcvt_s_w(5'd17, 5'd26, 5'd0, 3'b000);  // f17 = 3.0
            32'h0000_009c: rom = fmv_x_w(5'd27, 5'd17);
            32'h0000_00a0: rom = addi(5'd28, 5'd0, 12'h004);            // x28 = 4
            32'h0000_00a4: rom = fcvt_s_w(5'd18, 5'd28, 5'd1, 3'b000);  // f18 = 4.0
            32'h0000_00a8: rom = fmv_x_w(5'd29, 5'd18);
            32'h0000_00ac: rom = fsw(5'd7, 5'd4, 12'h000);
            32'h0000_00b0: rom = flw(5'd19, 5'd4, 12'h000);
            32'h0000_00b4: rom = fmv_x_w(5'd30, 5'd19);
            32'h0000_00b8: rom = csrrs(5'd31, 12'h301, 5'd0);          // misa
            32'h0000_00bc: rom = addi(5'd1, 5'd0, 12'h01f);
            32'h0000_00c0: rom = csrrw(12'h001, 5'd1);                 // fflags = 0x1f
            32'h0000_00c4: rom = csrrs(5'd2, 12'h003, 5'd0);           // fcsr
            32'h0000_00c8: rom = jal_zero(21'h0);
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

    for(cycle = 0; cycle < 420; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if(pc == 32'h0000_00c8 && state == CPU_IF)
            cycle = 420;
    end

    check(pc == 32'h0000_00c8, "FPU program reaches the final spin");
    check_reg(5'd10, 32'h4070_0000, "FADD.S computes 1.5 + 2.25 = 3.75");
    check_reg(5'd11, 32'h3f40_0000, "FSUB.S computes 2.25 - 1.5 = 0.75");
    check_reg(5'd12, 32'h4040_0000, "FMUL.S computes 1.5 * 2.0 = 3.0");
    check_reg(5'd13, 32'h3f90_0000, "FDIV.S computes 2.25 / 2.0 = 1.125");
    check_reg(5'd14, 32'h3fc0_0000, "FSQRT.S computes sqrt(2.25) = 1.5");
    check_reg(5'd15, 32'hbfc0_0000, "FSGNJ.S applies sign from rs2");
    check_reg(5'd16, 32'h3fc0_0000, "FSGNJN.S inverts rs2 sign");
    check_reg(5'd17, 32'hbfc0_0000, "FSGNJX.S xors sign bits");
    check_reg(5'd18, 32'hbfc0_0000, "FMIN.S picks the smaller operand");
    check_reg(5'd19, 32'h4010_0000, "FMAX.S picks the larger operand");
    check_reg(5'd20, 32'h0000_0001, "FEQ.S reports equal operands");
    check_reg(5'd21, 32'h0000_0001, "FLT.S reports less-than");
    check_reg(5'd22, 32'h0000_0001, "FLE.S reports less-or-equal");
    check_reg(5'd23, 32'h0000_0002, "FCLASS.S reports negative normal");
    check_reg(5'd24, 32'h0000_0002, "FCVT.W.S truncates 2.25 to 2");
    check_reg(5'd25, 32'h0000_0004, "FCVT.WU.S converts unsigned 4.0 to 4");
    check_reg(5'd27, 32'h4040_0000, "FCVT.S.W converts 3 to 3.0");
    check_reg(5'd29, 32'h4080_0000, "FCVT.S.WU converts 4 to 4.0");
    check_reg(5'd30, 32'h4070_0000, "FLW reloads the FSW value");
    check_reg(5'd31, 32'h4014_1121, "misa reports RV32F");
    check_reg(5'd2, 32'h0000_001f, "fcsr exposes writable fflags");
    check(data_mem[8'h40] == 32'h4070_0000, "FSW stores a 32-bit float word");
    check(!sfence_vma && !fence_i, "FPU program does not pulse fence signals");

    $display("FPU CPU PASS");
    $finish;
end

endmodule
