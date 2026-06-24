module regfile(
    input [4:0] rs1_addr,
    input [4:0] rs2_addr,
    input [4:0] rd_addr,
    input [31:0] rd_data,
    input we,
    input clk,
    output [31:0] rs1_data,
    output [31:0] rs2_data,
    input [4:0] test_addr,
    output [31:0] test_data
);

reg [31:0] regs [1:31];

assign rs1_data=(rs1_addr==5'd0)? 32'd0:regs[rs1_addr];
assign rs2_data=(rs2_addr==5'd0)? 32'd0:regs[rs2_addr];
assign test_data=(test_addr==5'd0)? 32'd0:regs[test_addr];

always @(posedge clk) begin
    if (we&&rd_addr!=5'd0) begin
        regs[rd_addr]<=rd_data;
    end
end

endmodule

