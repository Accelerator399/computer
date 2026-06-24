`timescale 1ns/1ps

module tb_firmware_boot;

localparam [2:0] CPU_IF = 3'd0;

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

reg saw_sfence;
reg saw_fence_i;
reg saw_wfi_continue;
integer errors;

cpu #(
    .RESET_VECTOR(32'h0000_0100)
) dut (
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

function automatic [31:0] rom;
    input [31:0] addr;
    begin
        case(addr)
            32'h0000_0100: rom = addi(5'd1, 5'd0, 12'h180);
            32'h0000_0104: rom = csrrw(12'h305, 5'd1); // mtvec
            32'h0000_0108: rom = addi(5'd1, 5'd0, 12'h200);
            32'h0000_010c: rom = csrrw(12'h105, 5'd1); // stvec
            32'h0000_0110: rom = lui(5'd1, 20'h00001);
            32'h0000_0114: rom = addi(5'd1, 5'd1, 12'h800);
            32'h0000_0118: rom = csrrw(12'h300, 5'd1); // mstatus.MPP=S
            32'h0000_011c: rom = addi(5'd1, 5'd0, 12'h140);
            32'h0000_0120: rom = csrrw(12'h341, 5'd1); // mepc=S payload
            32'h0000_0124: rom = csrrs(5'd5, 12'h301, 5'd0); // misa
            32'h0000_0128: rom = mret();

            32'h0000_0140: rom = addi(5'd6, 5'd0, 12'h123);
            32'h0000_0144: rom = inst_sfence_vma();
            32'h0000_0148: rom = inst_fence_i();
            32'h0000_014c: rom = wfi();
            32'h0000_0150: rom = addi(5'd7, 5'd0, 12'h456);
            32'h0000_0154: rom = jal_zero(21'h0);

            32'h0000_0180: rom = jal_zero(21'h0);
            32'h0000_0200: rom = jal_zero(21'h0);
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
            errors = errors + 1;
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
        saw_sfence <= 1'b0;
        saw_fence_i <= 1'b0;
        saw_wfi_continue <= 1'b0;
    end else begin
        if(sfence_vma)
            saw_sfence <= 1'b1;
        if(fence_i)
            saw_fence_i <= 1'b1;
        if(pc == 32'h0000_0150 && privilege_mode == 2'b01)
            saw_wfi_continue <= 1'b1;
    end
end

initial begin
    rst = 1'b1;
    test_addr = 5'd0;
    external_csr_rdata = 32'b0;
    errors = 0;

    repeat(5) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < 200; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if(pc == 32'h0000_0154 && state == CPU_IF)
            cycle = 200;
    end

    check(pc == 32'h0000_0154, "firmware handoff reaches the S-mode final spin");
    check(privilege_mode == 2'b01, "firmware handoff leaves the CPU in S-mode");
    check_reg(5'd5, 32'h4014_1101, "firmware reads misa before handoff");
    check_reg(5'd6, 32'h0000_0123, "S-mode payload executed after mret");
    check_reg(5'd7, 32'h0000_0456, "S-mode payload continued after WFI");
    check(saw_sfence, "S-mode payload executed sfence.vma");
    check(saw_fence_i, "S-mode payload executed fence.i");
    check(saw_wfi_continue, "WFI acts as a forward-progress NOP for firmware boot");

    if(errors == 0) begin
        $display("FIRMWARE BOOT PASS");
        $finish;
    end else begin
        $display("FIRMWARE BOOT FAIL errors=%0d pc=%08h privilege=%0d", errors, pc, privilege_mode);
        $fatal(1);
    end
end

endmodule
