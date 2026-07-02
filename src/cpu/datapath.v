module datapath #(
    parameter RESET_VECTOR = 32'h0000_0000,
    parameter ENABLE_FPU = 1
)(
    //全局
    input clk,
    input rst,

    //控制信号
    input pc_write,
    input [1:0] pc_src,
    input ir_write,
    input reg_write,
    input [2:0] wb_src,
    input alu_src_a,
    input [1:0] alu_src_b,
    input [1:0] alu_op,
    input mem_write,
    input alu_out_write,
    input ab_write,
    input mul_a_signed,
    input mul_b_signed,
    input mul_take_high,
    input div_is_signed,
    input [1:0] md_sel,
    input trap_pc_src,
    input amo_old_write,
    input amo_sc_check,
    input amo_reservation_set,
    input amo_reservation_clear,
    input amo_wdata_sel,
    input f_reg_write,
    input [1:0] f_wb_src,
    input div_start,
    output div_ready,
    input fpu_start,
    output fpu_ready,

    //异常信号
    input [31:0] mepc,
    input [31:0] mtvec,
    input [31:0] csr_rdata,
    input [31:0] trap_value_in,
    output [31:0] csr_wdata,
    output [11:0] csr_addr,
    output [31:0] exception_pc,
    output [31:0] trap_value,

    //iCache接口
    output [31:0] pc,
    input [31:0] inst,

    //dCache接口
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    output [3:0] mem_wstrb,
    input [31:0] mem_rdata,
    output i_addr_misaligned,
    output d_addr_misaligned,
    output [31:0] i_trap_addr,

    //控制器反馈
    output [6:0] opcode,
    output [2:0] funct3,
    output [6:0] funct7,
    output zero,
    output amo_sc_success,

    //调试端口
    input [4:0] test_addr,
    output [31:0] test_data
);

wire alu_zero;

wire [31:0] imm;
wire [31:0] pc_next;
wire [31:0] rs1_data,rs2_data;
wire [31:0] frs1_data,frs2_data;
wire [31:0] wb_data;
wire [31:0] f_wb_data;
wire [3:0] alu_op_out;
wire [31:0] alu_a,alu_b;
wire [31:0] alu_result;
wire [31:0] mul_result;
wire [31:0] div_quotient,div_remainder;
wire [31:0] md_result;
wire [31:0] fpu_result;
wire [2:0] fpu_op;
wire [31:0] fp_local_result;
wire [31:0] fp_int_result;
wire [31:0] zimm;

localparam FPU_ON = (ENABLE_FPU != 0);

reg [31:0] ir;
reg [31:0] A,B;
reg [31:0] FA,FB;
reg [31:0] pc_reg;
reg [31:0] alu_out;
reg [31:0] mdr;
reg [31:0] amo_old;
reg reservation_valid;
reg [31:0] reservation_addr;
reg sc_success_reg;

function [31:0] fp_class_bits;
    input [31:0] x;
    begin
        if(x[30:23] == 8'hff) begin
            if(x[22:0] == 23'b0)
                fp_class_bits = x[31] ? 32'h0000_0001 : 32'h0000_0080;
            else if(x[22])
                fp_class_bits = 32'h0000_0200;
            else
                fp_class_bits = 32'h0000_0100;
        end else if(x[30:23] == 8'h00) begin
            if(x[22:0] == 23'b0)
                fp_class_bits = x[31] ? 32'h0000_0008 : 32'h0000_0010;
            else
                fp_class_bits = x[31] ? 32'h0000_0004 : 32'h0000_0020;
        end else begin
            fp_class_bits = x[31] ? 32'h0000_0002 : 32'h0000_0040;
        end
    end
endfunction

function fp_is_nan;
    input [31:0] x;
    begin
        fp_is_nan = (x[30:23] == 8'hff) && (x[22:0] != 23'b0);
    end
endfunction

function fp_is_zero;
    input [31:0] x;
    begin
        fp_is_zero = (x[30:23] == 8'h00) && (x[22:0] == 23'b0);
    end
endfunction

function fp_lt;
    input [31:0] a;
    input [31:0] b;
    begin
        if(fp_is_nan(a) || fp_is_nan(b) || (fp_is_zero(a) && fp_is_zero(b)))
            fp_lt = 1'b0;
        else if(a[31] != b[31])
            fp_lt = a[31];
        else if(a[31] == 1'b0)
            fp_lt = a[30:0] < b[30:0];
        else
            fp_lt = a[30:0] > b[30:0];
    end
endfunction

function fp_eq;
    input [31:0] a;
    input [31:0] b;
    begin
        if(fp_is_nan(a) || fp_is_nan(b))
            fp_eq = 1'b0;
        else if(fp_is_zero(a) && fp_is_zero(b))
            fp_eq = 1'b1;
        else
            fp_eq = a == b;
    end
endfunction

function [31:0] fp_min;
    input [31:0] a;
    input [31:0] b;
    begin
        if(fp_is_nan(a) && fp_is_nan(b))
            fp_min = 32'h7fc0_0000;
        else if(fp_is_nan(a))
            fp_min = b;
        else if(fp_is_nan(b))
            fp_min = a;
        else if(fp_is_zero(a) && fp_is_zero(b))
            fp_min = (a[31] || b[31]) ? 32'h8000_0000 : 32'h0000_0000;
        else if(fp_lt(a, b))
            fp_min = a;
        else
            fp_min = b;
    end
endfunction

function [31:0] fp_max;
    input [31:0] a;
    input [31:0] b;
    begin
        if(fp_is_nan(a) && fp_is_nan(b))
            fp_max = 32'h7fc0_0000;
        else if(fp_is_nan(a))
            fp_max = b;
        else if(fp_is_nan(b))
            fp_max = a;
        else if(fp_is_zero(a) && fp_is_zero(b))
            fp_max = (a[31] && b[31]) ? 32'h8000_0000 : 32'h0000_0000;
        else if(fp_lt(a, b))
            fp_max = b;
        else
            fp_max = a;
    end
endfunction

function [31:0] fp_to_i32;
    input [31:0] x;
    input is_unsigned;
    reg sign;
    reg [7:0] exp;
    reg [22:0] frac;
    reg [23:0] sig;
    reg [63:0] mag64;
    integer unbiased;
    begin
        sign = x[31];
        exp = x[30:23];
        frac = x[22:0];
        if(exp == 8'hff) begin
            if(is_unsigned)
                fp_to_i32 = sign ? 32'b0 : 32'hffff_ffff;
            else
                fp_to_i32 = sign ? 32'h8000_0000 : 32'h7fff_ffff;
        end else if((exp == 8'h00) && (frac == 23'b0)) begin
            fp_to_i32 = 32'b0;
        end else begin
            if(exp == 8'h00) begin
                unbiased = -126;
                sig = {1'b0, frac};
            end else begin
                unbiased = exp - 127;
                sig = {1'b1, frac};
            end
            if(unbiased < 0) begin
                mag64 = 64'b0;
            end else if(unbiased >= 23) begin
                mag64 = {40'b0, sig} << (unbiased - 23);
            end else begin
                mag64 = {40'b0, sig} >> (23 - unbiased);
            end
            if(is_unsigned) begin
                if(sign)
                    fp_to_i32 = 32'b0;
                else if(mag64 > 64'h0000_0000_ffff_ffff)
                    fp_to_i32 = 32'hffff_ffff;
                else
                    fp_to_i32 = mag64[31:0];
            end else begin
                if(sign) begin
                    if(mag64 > 64'h0000_0000_8000_0000)
                        fp_to_i32 = 32'h8000_0000;
                    else
                        fp_to_i32 = (~mag64[31:0]) + 32'd1;
                end else begin
                    if(mag64 > 64'h0000_0000_7fff_ffff)
                        fp_to_i32 = 32'h7fff_ffff;
                    else
                        fp_to_i32 = mag64[31:0];
                end
            end
        end
    end
endfunction

function [31:0] i32_to_fp;
    input [31:0] x;
    input is_unsigned;
    reg sign;
    reg [31:0] mag;
    reg [31:0] shifted;
    reg [24:0] sig_round;
    reg [31:0] remainder_mask;
    reg [31:0] remainder;
    reg [7:0] exp;
    reg round_up;
    integer msb;
    integer idx;
    integer shift;
    reg found;
    begin
        if(is_unsigned) begin
            sign = 1'b0;
            mag = x;
        end else begin
            sign = x[31];
            mag = sign ? ((~x) + 32'd1) : x;
        end

        if(mag == 32'b0) begin
            i32_to_fp = {sign, 31'b0};
        end else begin
            msb = 0;
            found = 1'b0;
            for(idx = 31; idx >= 0; idx = idx - 1) begin
                if(!found && mag[idx]) begin
                    msb = idx;
                    found = 1'b1;
                end
            end

            exp = 8'd127 + msb;
            if(msb <= 23) begin
                shift = 23 - msb;
                sig_round = {1'b0, mag << shift};
            end else begin
                shift = msb - 23;
                shifted = mag >> shift;
                if(shift == 0) begin
                    round_up = 1'b0;
                end else begin
                    remainder_mask = (32'd1 << shift) - 1;
                    remainder = mag & remainder_mask;
                    round_up = (remainder > (32'd1 << (shift - 1))) ||
                               ((remainder == (32'd1 << (shift - 1))) && shifted[0]);
                end
                sig_round = {1'b0, shifted[23:0]} + round_up;
                if(sig_round[24]) begin
                    sig_round = sig_round >> 1;
                    exp = exp + 8'd1;
                end
            end

            i32_to_fp = {sign, exp, sig_round[22:0]};
        end
    end
endfunction

wire is_fp_op = FPU_ON && (ir[6:0] == 7'b1010011);
wire is_fadd_s = is_fp_op && (ir[31:25] == 7'b0000000);
wire is_fsub_s = is_fp_op && (ir[31:25] == 7'b0000100);
wire is_fmul_s = is_fp_op && (ir[31:25] == 7'b0001000);
wire is_fdiv_s = is_fp_op && (ir[31:25] == 7'b0001100);
wire is_fsqrt_s = is_fp_op && (ir[31:25] == 7'b0101100) && (ir[24:20] == 5'd0);
wire is_fsgnj_s = is_fp_op && (ir[31:25] == 7'b0010000) && (ir[14:12] == 3'b000);
wire is_fsgnjn_s = is_fp_op && (ir[31:25] == 7'b0010000) && (ir[14:12] == 3'b001);
wire is_fsgnjx_s = is_fp_op && (ir[31:25] == 7'b0010000) && (ir[14:12] == 3'b010);
wire is_fmin_s = is_fp_op && (ir[31:25] == 7'b0010100) && (ir[14:12] == 3'b000);
wire is_fmax_s = is_fp_op && (ir[31:25] == 7'b0010100) && (ir[14:12] == 3'b001);
wire is_feq_s = is_fp_op && (ir[31:25] == 7'b1010000) && (ir[14:12] == 3'b010);
wire is_flt_s = is_fp_op && (ir[31:25] == 7'b1010000) && (ir[14:12] == 3'b001);
wire is_fle_s = is_fp_op && (ir[31:25] == 7'b1010000) && (ir[14:12] == 3'b000);
wire is_fcvt_w_s = is_fp_op && (ir[31:25] == 7'b1100000) && (ir[24:20] == 5'd0);
wire is_fcvt_wu_s = is_fp_op && (ir[31:25] == 7'b1100000) && (ir[24:20] == 5'd1);
wire is_fcvt_s_w = is_fp_op && (ir[31:25] == 7'b1101000) && (ir[24:20] == 5'd0);
wire is_fcvt_s_wu = is_fp_op && (ir[31:25] == 7'b1101000) && (ir[24:20] == 5'd1);
wire is_fmv_x_w = is_fp_op && (ir[31:25] == 7'b1110000) && (ir[24:20] == 5'd0) && (ir[14:12] == 3'b000);
wire is_fclass_s = is_fp_op && (ir[31:25] == 7'b1110000) && (ir[24:20] == 5'd0) && (ir[14:12] == 3'b001);
wire is_fmv_w_x = is_fp_op && (ir[31:25] == 7'b1111000) && (ir[24:20] == 5'd0) && (ir[14:12] == 3'b000);
wire is_fp_ip_op = is_fadd_s || is_fsub_s || is_fmul_s || is_fdiv_s || is_fsqrt_s;
wire is_fp_to_int = is_fmv_x_w || is_feq_s || is_flt_s || is_fle_s || is_fclass_s || is_fcvt_w_s || is_fcvt_wu_s;
wire is_fp_to_freg = is_fp_ip_op || is_fsgnj_s || is_fsgnjn_s || is_fsgnjx_s ||
                     is_fmin_s || is_fmax_s || is_fmv_w_x || is_fcvt_s_w || is_fcvt_s_wu;

wire is_fp_load = FPU_ON && (ir[6:0] == 7'b0000111) && (ir[14:12] == 3'b010);
wire is_fp_store = FPU_ON && (ir[6:0] == 7'b0100111) && (ir[14:12] == 3'b010);

imm_gen ig(
    .inst(ir),
    .imm(imm)
);

regfile rf(
    .rs1_addr(ir[19:15]),
    .rs2_addr(ir[24:20]),
    .rd_addr(ir[11:7]),
    .rd_data(wb_data),
    .we(reg_write),
    .clk(clk),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data),
    .test_addr(test_addr),
    .test_data(test_data)
);

generate
    if(ENABLE_FPU) begin: gen_fpu_state
        fregfile frf(
            .rs1_addr(ir[19:15]),
            .rs2_addr(ir[24:20]),
            .rd_addr(ir[11:7]),
            .rd_data(f_wb_data),
            .we(f_reg_write),
            .clk(clk),
            .rs1_data(frs1_data),
            .rs2_data(frs2_data)
        );
    end else begin: gen_no_fpu_state
        assign frs1_data = 32'b0;
        assign frs2_data = 32'b0;
    end
endgenerate

alu_control ac(
    .alu_op(alu_op),
    .funct3(ir[14:12]),
    .funct7(ir[31:25]),
    .opcode(ir[6:0]),
    .op(alu_op_out)
);

alu a(
    .a(alu_a),
    .b(alu_b),
    .op(alu_op_out),
    .result(alu_result),
    .zero(alu_zero)
);

mul m(
    .a(A),
    .b(B),
    .a_signed(mul_a_signed),
    .b_signed(mul_b_signed),
    .take_high(mul_take_high),
    .result(mul_result)
);

div d(
    .clk(clk),
    .rst(rst),
    .start(div_start),
    .a(A),
    .b(B),
    .is_signed(div_is_signed),
    .ready(div_ready),
    .quotient(div_quotient),
    .remainder(div_remainder)
);

assign fpu_op = is_fsqrt_s ? 3'd4 :
                is_fdiv_s  ? 3'd3 :
                is_fmul_s  ? 3'd2 :
                is_fsub_s  ? 3'd1 :
                              3'd0;

generate
    if(ENABLE_FPU) begin: gen_fpu_exec
        fpu_single fpu(
            .clk(clk),
            .rst(rst),
            .start(fpu_start),
            .op(fpu_op),
            .a(FA),
            .b(FB),
            .ready(fpu_ready),
            .result(fpu_result)
        );
    end else begin: gen_no_fpu_exec
        assign fpu_ready = 1'b1;
        assign fpu_result = 32'b0;
    end
endgenerate

assign md_result=(md_sel==2'b00)? mul_result:
                 (md_sel==2'b01)? div_quotient:
                 div_remainder;

wire [31:0] load_data;
wire [7:0]  load_byte = (alu_out[1:0]==2'b00)? mdr[7:0]:
                        (alu_out[1:0]==2'b01)? mdr[15:8]:
                        (alu_out[1:0]==2'b10)? mdr[23:16]:
                        mdr[31:24];
wire [15:0] load_half = alu_out[1]? mdr[31:16]: mdr[15:0];
assign load_data= (funct3==3'b000)? {{24{load_byte[7]}},load_byte}: // lb
                  (funct3==3'b001)? {{16{load_half[15]}},load_half}: // lh
                  (funct3==3'b100)? {24'b0,load_byte}:               // lbu
                  (funct3==3'b101)? {16'b0,load_half}:               // lhu
                  mdr;                                                // lw

wire [31:0] store_operand = is_fp_store ? FB : B;
wire [31:0] store_byte_data = {4{store_operand[7:0]}};
wire [31:0] store_half_data = {2{store_operand[15:0]}};
wire [31:0] store_word_data = store_operand;
wire [3:0] store_byte_wstrb = 4'b0001 << alu_out[1:0];
wire [3:0] store_half_wstrb = alu_out[1] ? 4'b1100 : 4'b0011;
wire [31:0] store_data = (funct3==3'b000) ? store_byte_data :
                         (funct3==3'b001) ? store_half_data :
                         store_word_data;
wire [3:0] store_wstrb = (funct3==3'b000) ? store_byte_wstrb :
                         (funct3==3'b001) ? store_half_wstrb :
                         4'b1111;

wire [4:0] amo_funct5 = ir[31:27];
wire is_sc_w = (ir[6:0] == 7'b0101111) && (ir[14:12] == 3'b010) && (amo_funct5 == 5'b00011);
wire is_branch = ir[6:0] == 7'b1100011;
wire is_jal = ir[6:0] == 7'b1101111;
wire is_jalr = ir[6:0] == 7'b1100111;
wire is_load = ir[6:0] == 7'b0000011;
wire is_store = ir[6:0] == 7'b0100011;
wire is_amo = ir[6:0] == 7'b0101111;
wire branch_taken =
    (ir[14:12] == 3'b000) ? alu_zero :
    (ir[14:12] == 3'b001) ? !alu_zero :
    (ir[14:12] == 3'b100) ? !alu_zero :
    (ir[14:12] == 3'b101) ? alu_zero :
    (ir[14:12] == 3'b110) ? !alu_zero :
    (ir[14:12] == 3'b111) ? alu_zero :
                             1'b0;
wire [31:0] branch_target = pc_reg + imm;
wire [31:0] jal_target = pc_reg + imm;
wire [31:0] jalr_sum = A + imm;
wire [31:0] jalr_target = {jalr_sum[31:1], 1'b0};
wire [31:0] next_fetch_addr =
    (is_jal) ? jal_target :
    (is_jalr) ? jalr_target :
    (is_branch && branch_taken) ? branch_target :
    pc_reg + 32'd4;
wire load_halfword = (ir[14:12] == 3'b001) || (ir[14:12] == 3'b101);
wire load_word = (ir[14:12] == 3'b010);
wire store_halfword = (ir[14:12] == 3'b001);
wire store_word = (ir[14:12] == 3'b010);
wire mem_halfword_access = (is_load && load_halfword) || (is_store && store_halfword);
wire mem_word_access = (is_load && load_word) || (is_store && store_word) ||
                       is_fp_load || is_fp_store || is_amo;

assign pc_next= (trap_pc_src)? mepc:
                (pc_src==2'b00)? pc_reg+4:
                (pc_src==2'b01)? pc_reg+imm:
                (pc_src==2'b10)? jalr_target:
                mtvec;

wire signed [31:0] amo_old_signed = amo_old;
wire signed [31:0] amo_operand_signed = B;
wire [31:0] amo_result =
    (amo_funct5 == 5'b00000) ? amo_old + B :
    (amo_funct5 == 5'b00001) ? B :
    (amo_funct5 == 5'b00100) ? amo_old ^ B :
    (amo_funct5 == 5'b01000) ? amo_old | B :
    (amo_funct5 == 5'b01100) ? amo_old & B :
    (amo_funct5 == 5'b10000) ? ((amo_old_signed < amo_operand_signed) ? amo_old : B) :
    (amo_funct5 == 5'b10100) ? ((amo_old_signed < amo_operand_signed) ? B : amo_old) :
    (amo_funct5 == 5'b11000) ? ((amo_old < B) ? amo_old : B) :
    (amo_funct5 == 5'b11100) ? ((amo_old < B) ? B : amo_old) :
                                B;
wire [31:0] amo_store_data = is_sc_w ? B : amo_result;
wire [31:0] amo_rd_data = is_sc_w ? (sc_success_reg ? 32'd0 : 32'd1) : amo_old;

assign fp_int_result = !FPU_ON      ? 32'b0:
                       is_feq_s     ? {31'b0, fp_eq(FA, FB)}:
                       is_flt_s     ? {31'b0, fp_lt(FA, FB)}:
                       is_fle_s     ? {31'b0, fp_lt(FA, FB) || fp_eq(FA, FB)}:
                       is_fclass_s  ? fp_class_bits(FA):
                       is_fcvt_w_s  ? fp_to_i32(FA, 1'b0):
                       is_fcvt_wu_s ? fp_to_i32(FA, 1'b1):
                                      FA;

assign fp_local_result = !FPU_ON     ? 32'b0:
                         is_fsgnj_s  ? {FB[31], FA[30:0]}:
                         is_fsgnjn_s ? {~FB[31], FA[30:0]}:
                         is_fsgnjx_s ? {FA[31] ^ FB[31], FA[30:0]}:
                         is_fmin_s   ? fp_min(FA, FB):
                         is_fmax_s   ? fp_max(FA, FB):
                         is_fcvt_s_w ? i32_to_fp(A, 1'b0):
                         is_fcvt_s_wu? i32_to_fp(A, 1'b1):
                                       fpu_result;

assign wb_data= (wb_src==3'b000)? alu_out:
                (wb_src==3'b001)? load_data:
                (wb_src==3'b010)? pc_reg+4:
                (wb_src==3'b011)? md_result:
                (wb_src==3'b100)? csr_rdata:
                (wb_src==3'b101)? imm:
                (wb_src==3'b110)? amo_rd_data:
                fp_int_result;

assign f_wb_data=(f_wb_src==2'b00)? fpu_result:
                 (f_wb_src==2'b01)? mdr:
                 (f_wb_src==2'b10)? A:
                 fp_local_result;

assign alu_a=   alu_src_a? pc_reg:A;
assign alu_b=   (alu_src_b==2'b00)? B:
                (alu_src_b==2'b01)? imm:
                (alu_src_b==2'b10)? 32'd4: //pc+4
                32'd0;

assign csr_wdata=ir[14]? zimm:rs1_data;

assign mem_addr=alu_out;
assign mem_wdata=amo_wdata_sel ? amo_store_data : store_data;
assign mem_wstrb=amo_wdata_sel ? 4'b1111 : store_wstrb;
assign i_addr_misaligned = (is_branch || is_jal || is_jalr) && next_fetch_addr[1:0] != 2'b00;
assign d_addr_misaligned = (mem_word_access && alu_out[1:0] != 2'b00) ||
                           (mem_halfword_access && alu_out[0]);
assign i_trap_addr=next_fetch_addr;
assign zero=alu_zero;
assign funct3=ir[14:12];
assign funct7=ir[31:25];
assign opcode=ir[6:0];
assign csr_addr=ir[31:20];
assign zimm={27'b0,ir[19:15]};
assign pc=pc_reg;
assign exception_pc=pc;
assign trap_value=trap_value_in;
assign amo_sc_success=reservation_valid && (reservation_addr == alu_out);


always @(posedge clk) begin
    if(rst) begin
        ir<=32'b0;
        A<=32'b0;
        B<=32'b0;
        pc_reg<=RESET_VECTOR;
        alu_out<=32'b0;
        mdr<=32'b0;
        amo_old<=32'b0;
        reservation_valid<=1'b0;
        reservation_addr<=32'b0;
        sc_success_reg<=1'b0;
    end else begin
        if(ab_write) begin
            A<=rs1_data;
            B<=rs2_data;
            FA<=frs1_data;
            FB<=frs2_data;
        end

        if(alu_out_write)
            alu_out<=alu_result;

        if(amo_old_write)
            amo_old<=mdr;

        if(amo_sc_check)
            sc_success_reg<=amo_sc_success;

        if(amo_reservation_clear)
            reservation_valid<=1'b0;

        if(amo_reservation_set) begin
            reservation_valid<=1'b1;
            reservation_addr<=alu_out;
        end

        mdr<=mem_rdata;

        if(pc_write)
            pc_reg<=pc_next;

        if(ir_write)
            ir<=inst;
    end
end

endmodule
