module div(
    input [31:0] a,
    input [31:0] b,
    input is_signed,
    output [31:0] quotient,
    output [31:0] remainder
);

wire signed [31:0] a_s=a;
wire signed [31:0] b_s=b;

assign quotient=is_signed? (a_s/b_s):(a/b);
assign remainder=is_signed? (a_s%b_s):(a%b);

endmodule
