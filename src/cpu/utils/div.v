module div(
    input clk,
    input rst,
    input start,
    input [31:0] a,
    input [31:0] b,
    input is_signed,
    output reg ready,
    output reg [31:0] quotient,
    output reg [31:0] remainder
);

reg busy;
reg [5:0] count;
reg [31:0] divisor;
reg [31:0] dividend_shift;
reg [31:0] quotient_work;
reg [32:0] remainder_work;
reg quotient_neg;
reg remainder_neg;

wire a_neg = is_signed && a[31];
wire b_neg = is_signed && b[31];
wire [31:0] abs_a = a_neg ? ((~a) + 32'd1) : a;
wire [31:0] abs_b = b_neg ? ((~b) + 32'd1) : b;
wire div_by_zero = b == 32'b0;
wire signed_overflow = is_signed && (a == 32'h8000_0000) && (b == 32'hffff_ffff);

wire [32:0] shifted_remainder = {remainder_work[31:0], dividend_shift[31]};
wire step_subtract = shifted_remainder >= {1'b0, divisor};
wire [32:0] step_remainder =
    step_subtract ? (shifted_remainder - {1'b0, divisor}) : shifted_remainder;
wire [31:0] step_quotient = {quotient_work[30:0], step_subtract};
wire [31:0] final_quotient =
    quotient_neg ? ((~step_quotient) + 32'd1) : step_quotient;
wire [31:0] final_remainder =
    remainder_neg ? ((~step_remainder[31:0]) + 32'd1) : step_remainder[31:0];

always @(posedge clk) begin
    if(rst) begin
        busy <= 1'b0;
        ready <= 1'b0;
        count <= 6'b0;
        divisor <= 32'b0;
        dividend_shift <= 32'b0;
        quotient_work <= 32'b0;
        remainder_work <= 33'b0;
        quotient_neg <= 1'b0;
        remainder_neg <= 1'b0;
        quotient <= 32'b0;
        remainder <= 32'b0;
    end else if(start) begin
        busy <= 1'b0;
        ready <= 1'b1;
        count <= 6'b0;
        divisor <= abs_b;
        dividend_shift <= abs_a;
        quotient_work <= 32'b0;
        remainder_work <= 33'b0;
        quotient_neg <= a_neg ^ b_neg;
        remainder_neg <= a_neg;

        if(div_by_zero) begin
            quotient <= 32'hffff_ffff;
            remainder <= a;
        end else if(signed_overflow) begin
            quotient <= 32'h8000_0000;
            remainder <= 32'b0;
        end else begin
            busy <= 1'b1;
            ready <= 1'b0;
            quotient <= 32'b0;
            remainder <= 32'b0;
        end
    end else if(busy) begin
        dividend_shift <= {dividend_shift[30:0], 1'b0};
        quotient_work <= step_quotient;
        remainder_work <= step_remainder;

        if(count == 6'd31) begin
            busy <= 1'b0;
            ready <= 1'b1;
            quotient <= final_quotient;
            remainder <= final_remainder;
        end else begin
            count <= count + 6'd1;
        end
    end
end

endmodule
