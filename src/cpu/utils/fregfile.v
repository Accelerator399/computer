module fregfile(
    input [4:0] rs1_addr,
    input [4:0] rs2_addr,
    input [4:0] rd_addr,
    input [31:0] rd_data,
    input we,
    input clk,
    output [31:0] rs1_data,
    output [31:0] rs2_data
);

reg [31:0] regs [0:31];

assign rs1_data = regs[rs1_addr];
assign rs2_data = regs[rs2_addr];

always @(posedge clk) begin
    if(we)
        regs[rd_addr] <= rd_data;
end

endmodule

