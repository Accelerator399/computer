module mul(
    input [31:0] a,
    input [31:0] b,
    input a_signed,
    input b_signed,
    input take_high,
    output [31:0] result
);

wire signed [32:0] a_ext={a_signed? a[31]:1'b0,a};
wire signed [32:0] b_ext={b_signed? b[31]:1'b0,b};
wire signed [65:0] prod=a_ext*b_ext;

assign result=take_high? prod[63:32]:prod[31:0];

endmodule