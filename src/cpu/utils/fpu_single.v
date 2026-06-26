module fpu_single(
    input clk,
    input rst,
    input start,
    input [2:0] op,
    input [31:0] a,
    input [31:0] b,
    output ready,
    output [31:0] result
);

localparam OP_ADD  = 3'd0;
localparam OP_SUB  = 3'd1;
localparam OP_MUL  = 3'd2;
localparam OP_DIV  = 3'd3;
localparam OP_SQRT = 3'd4;

`ifdef USE_VIVADO_FPU_IP
reg [2:0] op_reg;
reg ready_reg;
reg [31:0] result_reg;

wire add_start = start && (op == OP_ADD);
wire sub_start = start && (op == OP_SUB);
wire mul_start = start && (op == OP_MUL);
wire div_start = start && (op == OP_DIV);
wire sqrt_start = start && (op == OP_SQRT);

wire add_valid;
wire sub_valid;
wire mul_valid;
wire div_valid;
wire sqrt_valid;
wire [31:0] add_result;
wire [31:0] sub_result;
wire [31:0] mul_result;
wire [31:0] div_result;
wire [31:0] sqrt_result;

fp_add_s fp_add_s_i (
    .aclk(clk),
    .s_axis_a_tvalid(add_start),
    .s_axis_a_tdata(a),
    .s_axis_b_tvalid(add_start),
    .s_axis_b_tdata(b),
    .m_axis_result_tvalid(add_valid),
    .m_axis_result_tdata(add_result)
);

fp_sub_s fp_sub_s_i (
    .aclk(clk),
    .s_axis_a_tvalid(sub_start),
    .s_axis_a_tdata(a),
    .s_axis_b_tvalid(sub_start),
    .s_axis_b_tdata(b),
    .m_axis_result_tvalid(sub_valid),
    .m_axis_result_tdata(sub_result)
);

fp_mul_s fp_mul_s_i (
    .aclk(clk),
    .s_axis_a_tvalid(mul_start),
    .s_axis_a_tdata(a),
    .s_axis_b_tvalid(mul_start),
    .s_axis_b_tdata(b),
    .m_axis_result_tvalid(mul_valid),
    .m_axis_result_tdata(mul_result)
);

fp_div_s fp_div_s_i (
    .aclk(clk),
    .s_axis_a_tvalid(div_start),
    .s_axis_a_tdata(a),
    .s_axis_b_tvalid(div_start),
    .s_axis_b_tdata(b),
    .m_axis_result_tvalid(div_valid),
    .m_axis_result_tdata(div_result)
);

fp_sqrt_s fp_sqrt_s_i (
    .aclk(clk),
    .s_axis_a_tvalid(sqrt_start),
    .s_axis_a_tdata(a),
    .m_axis_result_tvalid(sqrt_valid),
    .m_axis_result_tdata(sqrt_result)
);

wire selected_valid = ((op_reg == OP_ADD) && add_valid) ||
                      ((op_reg == OP_SUB) && sub_valid) ||
                      ((op_reg == OP_MUL) && mul_valid) ||
                      ((op_reg == OP_DIV) && div_valid) ||
                      ((op_reg == OP_SQRT) && sqrt_valid);
wire [31:0] selected_result = (op_reg == OP_ADD) ? add_result :
                              (op_reg == OP_SUB) ? sub_result :
                              (op_reg == OP_MUL) ? mul_result :
                              (op_reg == OP_DIV) ? div_result :
                                                   sqrt_result;

always @(posedge clk) begin
    if(rst) begin
        op_reg <= OP_ADD;
        ready_reg <= 1'b0;
        result_reg <= 32'b0;
    end else begin
        if(start) begin
            op_reg <= op;
            ready_reg <= 1'b0;
        end else if(selected_valid) begin
            result_reg <= selected_result;
            ready_reg <= 1'b1;
        end
    end
end

assign ready = ready_reg;
assign result = result_reg;

`else
`ifdef SYNTHESIS
initial begin
    $error("fpu_single synthesis requires USE_VIVADO_FPU_IP and generated fp_add_s/fp_sub_s/fp_mul_s/fp_div_s/fp_sqrt_s IP.");
end

assign ready = 1'b0;
assign result = 32'h7fc0_0000;

`else
reg ready_reg;
reg [31:0] result_reg;

function automatic [31:0] sim_calc;
    input [2:0] calc_op;
    input [31:0] calc_a;
    input [31:0] calc_b;
    shortreal real_a;
    shortreal real_b;
    shortreal real_result;
    begin
        real_a = $bitstoshortreal(calc_a);
        real_b = $bitstoshortreal(calc_b);
        case(calc_op)
            OP_SUB: real_result = real_a - real_b;
            OP_MUL: real_result = real_a * real_b;
            OP_DIV: real_result = real_a / real_b;
            OP_SQRT: real_result = $sqrt(real_a);
            default: real_result = real_a + real_b;
        endcase
        sim_calc = $shortrealtobits(real_result);
    end
endfunction

always @(posedge clk) begin
    if(rst) begin
        ready_reg <= 1'b0;
        result_reg <= 32'b0;
    end else if(start) begin
        result_reg <= sim_calc(op, a, b);
        ready_reg <= 1'b1;
    end
end

assign ready = ready_reg;
assign result = result_reg;
`endif
`endif

endmodule
