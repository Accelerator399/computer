module boot_ram #(
    parameter BASE_ADDR = 32'h0000_8000,
    parameter WORDS = 8192,
    parameter INIT_FILE = ""
)(
    input clk,
    input [31:0] addr,
    input [31:0] wdata,
    input [3:0] wstrb,
    input we,
    output [31:0] rdata,
    output hit
);

reg [31:0] ram [0:WORDS-1];
wire [31:0] word_index = (addr - BASE_ADDR) >> 2;

integer i;
initial begin
    for(i = 0; i < WORDS; i = i + 1)
        ram[i] = 32'h0000_0000;

    if(INIT_FILE != "")
        $readmemh(INIT_FILE, ram);
end

assign hit = (addr >= BASE_ADDR) && (word_index < WORDS);
assign rdata = hit ? ram[word_index] : 32'h0000_0000;

always @(posedge clk) begin
    if(we && hit) begin
        if(wstrb[0])
            ram[word_index][7:0] <= wdata[7:0];
        if(wstrb[1])
            ram[word_index][15:8] <= wdata[15:8];
        if(wstrb[2])
            ram[word_index][23:16] <= wdata[23:16];
        if(wstrb[3])
            ram[word_index][31:24] <= wdata[31:24];
    end
end

endmodule
