`timescale 1ns/1ps

module tb_computer_smode_plic_irq;

localparam [2:0] CPU_IF = 3'd0;

reg clk;
reg rst;
reg ext_int;
reg [4:0] test_addr;

wire [31:0] test_data;
wire [2:0] state;
wire [31:0] pc_out;
wire [31:0] mem_addr_out;
wire [31:0] mem_wdata_out;
wire [3:0] mem_wstrb_out;
wire mem_write_out;
wire [1:0] privilege_out;
wire i_page_fault_out;
wire d_page_fault_out;
wire [31:0] satp_out;
wire [31:0] pad;

reg ext_requested;
reg saw_s_ext_irq;
reg saw_s_ext_return;
integer errors;

top_sim #(
    .MEM_WORDS(4096)
) dut (
    .clk(clk),
    .rst(rst),
    .pad(pad),
    .ext_int(ext_int),
    .timer_int(1'b0),
    .soft_int(1'b0),
    .test_addr(test_addr),
    .test_data(test_data),
    .state(state),
    .pc_out(pc_out),
    .inst_out(),
    .mem_addr_out(mem_addr_out),
    .mem_wdata_out(mem_wdata_out),
    .mem_wstrb_out(mem_wstrb_out),
    .mem_write_out(mem_write_out),
    .privilege_out(privilege_out),
    .i_paddr_out(),
    .d_paddr_out(),
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

function automatic [31:0] csrrs;
    input [4:0] rd;
    input [11:0] csr;
    input [4:0] rs1;
    begin
        csrrs = {csr, rs1, 3'b010, rd, 7'b1110011};
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

function automatic [31:0] jal_zero;
    input [20:0] imm;
    begin
        jal_zero = {imm[20], imm[10:1], imm[11], imm[19:12], 5'd0, 7'b1101111};
    end
endfunction

task automatic put_inst;
    input [31:0] addr;
    input [31:0] value;
    begin
        dut.u_mem.mem[addr[31:2]] = value;
    end
endtask

task automatic load_program;
    begin
        put_inst(32'h0000_0000, addi(5'd1, 5'd0, 12'h100));
        put_inst(32'h0000_0004, csrrw(12'h105, 5'd1));       // stvec = 0x100
        put_inst(32'h0000_0008, addi(5'd1, 5'd0, 12'h200));
        put_inst(32'h0000_000c, csrrw(12'h303, 5'd1));       // delegate SEIP
        put_inst(32'h0000_0010, csrrw(12'h104, 5'd1));       // sie.SEIE
        put_inst(32'h0000_0014, addi(5'd1, 5'd0, 12'h002));
        put_inst(32'h0000_0018, csrrw(12'h100, 5'd1));       // sstatus.SIE
        put_inst(32'h0000_001c, lui(5'd2, 20'h10030));       // PLIC priority base
        put_inst(32'h0000_0020, addi(5'd3, 5'd0, 12'h001));
        put_inst(32'h0000_0024, sw(5'd3, 5'd2, 12'h004));    // priority[1] = 1
        put_inst(32'h0000_0028, lui(5'd2, 20'h10032));       // PLIC enable base
        put_inst(32'h0000_002c, addi(5'd3, 5'd0, 12'h002));
        put_inst(32'h0000_0030, sw(5'd3, 5'd2, 12'h000));    // enable source 1
        put_inst(32'h0000_0034, lui(5'd2, 20'h10230));       // PLIC threshold/claim base
        put_inst(32'h0000_0038, sw(5'd0, 5'd2, 12'h000));    // threshold = 0
        put_inst(32'h0000_003c, addi(5'd1, 5'd0, 12'h054));
        put_inst(32'h0000_0040, csrrw(12'h341, 5'd1));       // mepc = S payload
        put_inst(32'h0000_0044, lui(5'd1, 20'h00001));
        put_inst(32'h0000_0048, addi(5'd1, 5'd1, 12'h800));  // x1 = 0x800
        put_inst(32'h0000_004c, csrrs(5'd0, 12'h300, 5'd1)); // mstatus.MPP = S
        put_inst(32'h0000_0050, mret());

        put_inst(32'h0000_0054, addi(5'd5, 5'd0, 12'h011));
        put_inst(32'h0000_0058, jal_zero(21'h0));

        put_inst(32'h0000_0100, csrrs(5'd10, 12'h142, 5'd0)); // scause
        put_inst(32'h0000_0104, lui(5'd2, 20'h10230));
        put_inst(32'h0000_0108, lw(5'd11, 5'd2, 12'h004));    // PLIC claim
        put_inst(32'h0000_010c, sw(5'd11, 5'd2, 12'h004));    // PLIC complete
        put_inst(32'h0000_0110, addi(5'd12, 5'd0, 12'h033));
        put_inst(32'h0000_0114, sret());
    end
endtask

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
        ext_requested <= 1'b0;
        saw_s_ext_irq <= 1'b0;
        saw_s_ext_return <= 1'b0;
        ext_int <= 1'b0;
    end else begin
        if(!ext_requested && pc_out == 32'h0000_0058 && state == CPU_IF && privilege_out == 2'b01) begin
            ext_requested <= 1'b1;
            ext_int <= 1'b1;
        end

        if(pc_out == 32'h0000_0100) begin
            saw_s_ext_irq <= 1'b1;
            ext_int <= 1'b0;
        end

        if(saw_s_ext_irq && pc_out == 32'h0000_0058 && state == CPU_IF && privilege_out == 2'b01)
            saw_s_ext_return <= 1'b1;
    end
end

initial begin
    rst = 1'b1;
    test_addr = 5'd0;
    ext_int = 1'b0;
    errors = 0;
    load_program();

    repeat(8) @(posedge clk);
    rst = 1'b0;

    for(cycle = 0; cycle < 1500; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if(saw_s_ext_return)
            cycle = 1500;
    end

    check(saw_s_ext_irq, "computer_core routes delegated PLIC external interrupt to S-mode");
    check(saw_s_ext_return, "sret returns after the S-mode external interrupt");
    check(!i_page_fault_out && !d_page_fault_out, "S-mode PLIC interrupt path has no page faults");
    check_reg(5'd5, 32'h0000_0011, "S-mode payload runs before external interrupt");
    check_reg(5'd10, 32'h8000_0009, "S-mode handler reads scause=0x80000009");
    check_reg(5'd11, 32'h0000_0001, "S-mode handler claims PLIC source 1");
    check_reg(5'd12, 32'h0000_0033, "S-mode interrupt handler completed");
    check(privilege_out == 2'b01, "S-mode external interrupt test remains in S-mode");
    check(satp_out == 32'b0, "S-mode external interrupt test runs in bare mode");

    if(errors == 0) begin
        $display("COMPUTER S-MODE PLIC IRQ PASS");
        $finish;
    end else begin
        $display("COMPUTER S-MODE PLIC IRQ FAIL errors=%0d pc=%08h privilege=%0d", errors, pc_out, privilege_out);
        $fatal(1);
    end
end

endmodule
