`timescale 1ns/1ps

module tb_clint;

localparam BASE = 32'h1000_0000;

reg clk;
reg rst;
reg [31:0] addr;
reg [31:0] wdata;
reg [3:0] wstrb;
reg we;

wire [31:0] rdata;
wire timer_int;
wire soft_int;

clint #(
    .BASE_ADDR(BASE)
) dut (
    .clk(clk),
    .rst(rst),
    .addr(addr),
    .wdata(wdata),
    .wstrb(wstrb),
    .we(we),
    .rdata(rdata),
    .timer_int(timer_int),
    .soft_int(soft_int)
);

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

task automatic write32;
    input [31:0] write_addr;
    input [31:0] value;
    input [3:0] byte_en;
    begin
        @(negedge clk);
        addr = write_addr;
        wdata = value;
        wstrb = byte_en;
        we = 1'b1;
        @(negedge clk);
        we = 1'b0;
        wdata = 32'b0;
        wstrb = 4'b0;
        @(posedge clk);
        #1;
    end
endtask

task automatic read_check;
    input [31:0] read_addr;
    input [31:0] expected;
    input string message;
    begin
        addr = read_addr;
        #1;
        check(rdata == expected, message);
    end
endtask

integer n;

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

initial begin
    rst = 1'b1;
    addr = BASE;
    wdata = 32'b0;
    wstrb = 4'b0;
    we = 1'b0;

    repeat(5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
    #1;

    check(!soft_int, "MSIP reset clears software interrupt");
    check(!timer_int, "mtimecmp reset keeps timer interrupt deasserted");

    write32(BASE + 32'h0000_0000, 32'h0000_0001, 4'b0001);
    check(soft_int, "MSIP bit 0 asserts software interrupt");
    read_check(BASE + 32'h0000_0000, 32'h0000_0001, "MSIP reads back bit 0");

    write32(BASE + 32'h0000_0000, 32'hffff_0000, 4'b1100);
    check(soft_int, "upper-byte MSIP write does not clear bit 0");

    write32(BASE + 32'h0000_0000, 32'h0000_0000, 4'b0001);
    check(!soft_int, "clearing MSIP bit 0 deasserts software interrupt");

    write32(BASE + 32'h0000_bffc, 32'h0000_0000, 4'b1111);
    write32(BASE + 32'h0000_bff8, 32'h0000_0000, 4'b1111);
    write32(BASE + 32'h0000_4004, 32'h0000_0000, 4'b1111);
    write32(BASE + 32'h0000_4000, 32'h0000_0008, 4'b1111);
    check(!timer_int, "timer interrupt waits while mtime is below mtimecmp");

    for(n = 0; n < 12; n = n + 1)
        @(posedge clk);
    #1;
    check(timer_int, "timer interrupt asserts when mtime reaches mtimecmp");

    write32(BASE + 32'h0000_4000, 32'hffff_ffff, 4'b1111);
    write32(BASE + 32'h0000_4004, 32'hffff_ffff, 4'b1111);
    check(!timer_int, "raising mtimecmp deasserts timer interrupt");

    write32(BASE + 32'h0000_4000, 32'h0000_00aa, 4'b0001);
    read_check(BASE + 32'h0000_4000, 32'hffff_ffaa, "mtimecmp low byte honors write strobes");

    $display("CLINT PASS");
    $finish;
end

endmodule
