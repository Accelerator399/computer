module boot_rom #(
    parameter BASE_ADDR = 32'h0000_0000,
    parameter WORDS = 64,
    parameter INIT_FILE = ""
)(
    input [31:0] addr,
    output [31:0] rdata,
    output hit
);

reg [31:0] rom [0:WORDS-1];
wire [31:0] word_index = (addr - BASE_ADDR) >> 2;

integer i;
initial begin
    for(i = 0; i < WORDS; i = i + 1)
        rom[i] = 32'h0000_0013;

    if(INIT_FILE != "")
        $readmemh(INIT_FILE, rom);
end

assign hit = (addr >= BASE_ADDR) && (word_index < WORDS);
assign rdata = hit ? rom[word_index] : 32'h0000_0013;

endmodule
