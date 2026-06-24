module simple_mem128 #(
    parameter WORDS = 4096,
    parameter INIT_FILE = ""
)(
    input clk,
    input rst,

    input i_req,
    input i_we,
    input [31:0] i_addr,
    input [127:0] i_wdata,
    input [15:0] i_wstrb,
    output reg [127:0] i_rdata,
    output reg i_ready,

    input d_req,
    input d_we,
    input [31:0] d_addr,
    input [127:0] d_wdata,
    input [15:0] d_wstrb,
    output reg [127:0] d_rdata,
    output reg d_ready,

    input w_req,
    input [31:0] w_addr,
    output reg [127:0] w_rdata,
    output reg w_ready
);

reg [31:0] mem [0:WORDS-1];

integer k;
initial begin
    for(k=0;k<WORDS;k=k+1)
        mem[k]=32'b0;

    if(INIT_FILE!="")
        $readmemh(INIT_FILE, mem);
end

wire [31:0] i_line_addr = {i_addr[31:4],4'b0};
wire [31:0] d_line_addr = {d_addr[31:4],4'b0};
wire [31:0] w_line_addr = {w_addr[31:4],4'b0};
wire [31:0] i_word_addr = i_line_addr[31:2];
wire [31:0] d_word_addr = d_line_addr[31:2];
wire [31:0] w_word_addr = w_line_addr[31:2];

wire i_in_range = (i_word_addr + 3) < WORDS;
wire d_in_range = (d_word_addr + 3) < WORDS;
wire w_in_range = (w_word_addr + 3) < WORDS;

always @(posedge clk) begin
    if(rst) begin
        i_rdata<=128'b0;
        i_ready<=1'b0;
        d_rdata<=128'b0;
        d_ready<=1'b0;
        w_rdata<=128'b0;
        w_ready<=1'b0;
    end else begin
        i_ready<=1'b0;
        d_ready<=1'b0;
        w_ready<=1'b0;

        if(i_req) begin
            i_ready<=1'b1;
            if(i_in_range) begin
                i_rdata<={mem[i_word_addr+3],mem[i_word_addr+2],
                          mem[i_word_addr+1],mem[i_word_addr+0]};
            end else begin
                i_rdata<=128'b0;
            end
        end

        if(d_req) begin
            d_ready<=1'b1;
            if(d_in_range) begin
                if(d_we) begin
                    if(d_wstrb[0])  mem[d_word_addr+0][7:0]   <= d_wdata[7:0];
                    if(d_wstrb[1])  mem[d_word_addr+0][15:8]  <= d_wdata[15:8];
                    if(d_wstrb[2])  mem[d_word_addr+0][23:16] <= d_wdata[23:16];
                    if(d_wstrb[3])  mem[d_word_addr+0][31:24] <= d_wdata[31:24];
                    if(d_wstrb[4])  mem[d_word_addr+1][7:0]   <= d_wdata[39:32];
                    if(d_wstrb[5])  mem[d_word_addr+1][15:8]  <= d_wdata[47:40];
                    if(d_wstrb[6])  mem[d_word_addr+1][23:16] <= d_wdata[55:48];
                    if(d_wstrb[7])  mem[d_word_addr+1][31:24] <= d_wdata[63:56];
                    if(d_wstrb[8])  mem[d_word_addr+2][7:0]   <= d_wdata[71:64];
                    if(d_wstrb[9])  mem[d_word_addr+2][15:8]  <= d_wdata[79:72];
                    if(d_wstrb[10]) mem[d_word_addr+2][23:16] <= d_wdata[87:80];
                    if(d_wstrb[11]) mem[d_word_addr+2][31:24] <= d_wdata[95:88];
                    if(d_wstrb[12]) mem[d_word_addr+3][7:0]   <= d_wdata[103:96];
                    if(d_wstrb[13]) mem[d_word_addr+3][15:8]  <= d_wdata[111:104];
                    if(d_wstrb[14]) mem[d_word_addr+3][23:16] <= d_wdata[119:112];
                    if(d_wstrb[15]) mem[d_word_addr+3][31:24] <= d_wdata[127:120];
                end

                d_rdata<={mem[d_word_addr+3],mem[d_word_addr+2],
                          mem[d_word_addr+1],mem[d_word_addr+0]};
            end else begin
                d_rdata<=128'b0;
            end
        end

        if(w_req) begin
            w_ready<=1'b1;
            if(w_in_range) begin
                w_rdata<={mem[w_word_addr+3],mem[w_word_addr+2],
                          mem[w_word_addr+1],mem[w_word_addr+0]};
            end else begin
                w_rdata<=128'b0;
            end
        end
    end
end

endmodule
