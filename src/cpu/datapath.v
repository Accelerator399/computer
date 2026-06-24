module datapath #(
    parameter RESET_VECTOR = 32'h0000_0000
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
wire [31:0] wb_data;
wire [3:0] alu_op_out;
wire [31:0] alu_a,alu_b;
wire [31:0] alu_result;
wire [31:0] mul_result;
wire [31:0] div_quotient,div_remainder;
wire [31:0] md_result;
wire [31:0] zimm;


reg [31:0] ir;
reg [31:0] A,B;
reg [31:0] pc_reg;
reg [31:0] alu_out;
reg [31:0] mdr;
reg [31:0] amo_old;
reg reservation_valid;
reg [31:0] reservation_addr;
reg sc_success_reg;

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
    .a(A),
    .b(B),
    .is_signed(div_is_signed),
    .quotient(div_quotient),
    .remainder(div_remainder)
);

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

wire [31:0] store_byte_data = {4{B[7:0]}};
wire [31:0] store_half_data = {2{B[15:0]}};
wire [31:0] store_word_data = B;
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
wire mem_word_access = (is_load && load_word) || (is_store && store_word) || is_amo;

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

assign wb_data= (wb_src==3'b000)? alu_out:
                (wb_src==3'b001)? load_data:
                (wb_src==3'b010)? pc_reg+4:
                (wb_src==3'b011)? md_result:
                (wb_src==3'b100)? csr_rdata:
                (wb_src==3'b110)? amo_rd_data:
                imm;

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
