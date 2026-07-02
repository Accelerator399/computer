module byte_fifo #(
    parameter integer DEPTH = 512,
    parameter integer ADDR_BITS = (DEPTH <= 2) ? 1 : $clog2(DEPTH)
)(
    input clk,
    input rst,
    input push,
    input [7:0] din,
    input pop,
    output [7:0] dout,
    output empty,
    output full
);

reg [7:0] mem [0:DEPTH-1];
reg [ADDR_BITS-1:0] rd_ptr;
reg [ADDR_BITS-1:0] wr_ptr;
reg [ADDR_BITS:0] count;

assign empty = (count == {ADDR_BITS+1{1'b0}});
assign full = (count == DEPTH[ADDR_BITS:0]);
assign dout = mem[rd_ptr];

wire do_push = push && !full;
wire do_pop = pop && !empty;

always @(posedge clk) begin
    if(rst) begin
        rd_ptr <= {ADDR_BITS{1'b0}};
        wr_ptr <= {ADDR_BITS{1'b0}};
        count <= {ADDR_BITS+1{1'b0}};
    end else begin
        if(do_push) begin
            mem[wr_ptr] <= din;
            wr_ptr <= wr_ptr + 1'b1;
        end

        if(do_pop)
            rd_ptr <= rd_ptr + 1'b1;

        case({do_push, do_pop})
            2'b10: count <= count + 1'b1;
            2'b01: count <= count - 1'b1;
            default: count <= count;
        endcase
    end
end

endmodule
