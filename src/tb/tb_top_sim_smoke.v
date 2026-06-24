`timescale 1ns/1ps

module tb_top_sim_smoke;

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

top_sim #(
    .MEM_WORDS(4096),
    .INIT_FILE("src/tb/smoke_program.hex")
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

always #5 clk = ~clk;

integer errors;

task expect_reg;
    input [4:0] addr;
    input [31:0] expected;
    begin
        test_addr = addr;
        #1;
        if(test_data !== expected) begin
            $display("FAIL: x%0d expected %08h got %08h", addr, expected, test_data);
            errors = errors + 1;
        end else begin
            $display("PASS: x%0d = %08h", addr, test_data);
        end
    end
endtask

initial begin
    $dumpfile("tb_top_sim_smoke.vcd");
    $dumpvars(0, tb_top_sim_smoke);

    clk = 1'b0;
    rst = 1'b1;
    test_addr = 5'd0;
    errors = 0;

    repeat(8) @(posedge clk);
    rst = 1'b0;

    repeat(500) @(posedge clk);

    expect_reg(5'd3, 32'd42);
    expect_reg(5'd4, 32'd90);

    if(dut.u_mem.mem[16] !== 32'h00005a2a) begin
        $display("FAIL: mem[0x40] expected 00005a2a got %08h", dut.u_mem.mem[16]);
        errors = errors + 1;
    end else begin
        $display("PASS: mem[0x40] = %08h", dut.u_mem.mem[16]);
    end

    if(i_page_fault_out || d_page_fault_out) begin
        $display("FAIL: unexpected page fault i=%b d=%b", i_page_fault_out, d_page_fault_out);
        errors = errors + 1;
    end

    if(errors == 0)
        $display("SMOKE PASS");
    else
        $display("SMOKE FAIL errors=%0d", errors);

    $finish;
end

endmodule
