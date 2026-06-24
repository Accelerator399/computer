module cpu #(
    parameter RESET_VECTOR = 32'h0000_0000
)(
    //全局
    input clk,
    input rst,

    //iCache
    output [31:0] pc,
    input [31:0] inst,
    input icache_hit,
    input i_page_fault,
    output i_addr_misaligned,

    //dCache
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    output [3:0] mem_wstrb,
    output mem_write,
    input [31:0] mem_rdata,
    input dcache_hit,
    input d_page_fault,
    output d_addr_misaligned,

    //外部CSR（MMU/satp）
    output external_csr_we,
    output [11:0] external_csr_addr,
    output [31:0] external_csr_wdata,
    input [31:0] external_csr_rdata,
    output sfence_vma,
    output fence_i,
    output mstatus_sum,
    output mstatus_mxr,
    output [1:0] privilege_mode,

    //中断输入
    input ext_int,
    input timer_int,
    input soft_int,

    //调试端口
    input [4:0] test_addr,
    output [31:0] test_data,
    output [2:0] state
);

wire [6:0] opcode;
wire [2:0] funct3;
wire [6:0] funct7;
wire zero;
wire pc_write;
wire [1:0] pc_src;
wire ir_write;
wire reg_write;
wire [2:0] wb_src;
wire alu_src_a;
wire [1:0] alu_src_b;
wire [1:0] alu_op;
wire mem_write_en;
wire alu_out_write;
wire ab_write;
wire mul_a_signed;
wire mul_b_signed;
wire mul_take_high;
wire div_is_signed;
wire [1:0] md_sel;
wire trap_pc_src;
wire csr_we;
wire [1:0] csr_op;
wire exception;
wire [31:0] cause;
wire mret;
wire sret;
wire sfence_vma_wire;
wire fence_i_wire;
wire amo_old_write;
wire amo_sc_check;
wire amo_reservation_set;
wire amo_reservation_clear;
wire amo_wdata_sel;
wire amo_sc_success;

wire [31:0] ret_epc;
wire [31:0] trap_vec;
wire [31:0] csr_rdata;
wire [31:0] csr_wdata;
wire [11:0] csr_addr;
wire [31:0] exception_pc;
wire [31:0] trap_value;
wire [31:0] exception_value;
wire [31:0] i_trap_addr;
wire mie;
wire int_pending;
wire [31:0] mip;
wire [1:0] privilege;
wire mstatus_sum_wire;
wire mstatus_mxr_wire;

control ct(
    .clk(clk),
    .rst(rst),
    .opcode(opcode),
    .funct3(funct3),
    .funct7(funct7),
    .funct12(csr_addr),
    .zero(zero),
    .icache_hit(icache_hit),
    .dcache_hit(dcache_hit),
    .i_page_fault(i_page_fault),
    .d_page_fault(d_page_fault),
    .i_addr_misaligned(i_addr_misaligned),
    .d_addr_misaligned(d_addr_misaligned),
    .int_pending(int_pending),
    .mie(mie),
    .mtvec(trap_vec),
    .mepc(ret_epc),
    .mip(mip),
    .privilege(privilege),
    .amo_sc_success(amo_sc_success),
    .pc_write(pc_write),
    .pc_src(pc_src),
    .ir_write(ir_write),
    .reg_write(reg_write),
    .wb_src(wb_src),
    .alu_src_a(alu_src_a),
    .alu_src_b(alu_src_b),
    .alu_op(alu_op),
    .mem_write(mem_write_en),
    .alu_out_write(alu_out_write),
    .ab_write(ab_write),
    .mul_a_signed(mul_a_signed),
    .mul_b_signed(mul_b_signed),
    .mul_take_high(mul_take_high),
    .div_is_signed(div_is_signed),
    .md_sel(md_sel),
    .csr_we(csr_we),
    .csr_op(csr_op),
    .exception(exception),
    .cause(cause),
    .mret(mret),
    .sret(sret),
    .sfence_vma(sfence_vma_wire),
    .fence_i(fence_i_wire),
    .amo_old_write(amo_old_write),
    .amo_sc_check(amo_sc_check),
    .amo_reservation_set(amo_reservation_set),
    .amo_reservation_clear(amo_reservation_clear),
    .amo_wdata_sel(amo_wdata_sel),
    .trap_pc_src(trap_pc_src),
    .state_out(state)
);

datapath #(
    .RESET_VECTOR(RESET_VECTOR)
) dp (
    .clk(clk),
    .rst(rst),
    .pc_write(pc_write),
    .pc_src(pc_src),
    .ir_write(ir_write),
    .reg_write(reg_write),
    .wb_src(wb_src),
    .alu_src_a(alu_src_a),
    .alu_src_b(alu_src_b),
    .alu_op(alu_op),
    .mem_write(mem_write_en),
    .alu_out_write(alu_out_write),
    .ab_write(ab_write),
    .mul_a_signed(mul_a_signed),
    .mul_b_signed(mul_b_signed),
    .mul_take_high(mul_take_high),
    .div_is_signed(div_is_signed),
    .md_sel(md_sel),
    .trap_pc_src(trap_pc_src),
    .amo_old_write(amo_old_write),
    .amo_sc_check(amo_sc_check),
    .amo_reservation_set(amo_reservation_set),
    .amo_reservation_clear(amo_reservation_clear),
    .amo_wdata_sel(amo_wdata_sel),
    .mepc(ret_epc),
    .mtvec(trap_vec),
    .csr_rdata(csr_rdata),
    .trap_value_in(exception_value),
    .csr_wdata(csr_wdata),
    .csr_addr(csr_addr),
    .exception_pc(exception_pc),
    .trap_value(trap_value),
    .pc(pc),
    .inst(inst),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata),
    .i_addr_misaligned(i_addr_misaligned),
    .d_addr_misaligned(d_addr_misaligned),
    .i_trap_addr(i_trap_addr),
    .opcode(opcode),
    .funct3(funct3),
    .funct7(funct7),
    .zero(zero),
    .amo_sc_success(amo_sc_success),
    .test_addr(test_addr),
    .test_data(test_data)
);

csr cs(
    .clk(clk),
    .rst(rst),
    .csr_op(csr_op),
    .csr_addr(csr_addr),
    .csr_wdata(csr_wdata),
    .csr_we(csr_we),
    .csr_rdata(csr_rdata),
    .external_csr_we(external_csr_we),
    .external_csr_addr(external_csr_addr),
    .external_csr_wdata(external_csr_wdata),
    .external_csr_rdata(external_csr_rdata),
    .exception(exception),
    .exception_pc(exception_pc),
    .cause(cause),
    .trap_value(trap_value),
    .mret(mret),
    .sret(sret),
    .ext_int(ext_int),
    .timer_int(timer_int),
    .soft_int(soft_int),
    .trap_vec(trap_vec),
    .ret_epc(ret_epc),
    .mie(mie),
    .int_pending(int_pending),
    .mip_out(mip),
    .mstatus_sum(mstatus_sum_wire),
    .mstatus_mxr(mstatus_mxr_wire),
    .privilege(privilege)
);

assign mem_write=mem_write_en;
assign sfence_vma=sfence_vma_wire;
assign fence_i=fence_i_wire;
assign mstatus_sum=mstatus_sum_wire;
assign mstatus_mxr=mstatus_mxr_wire;
assign privilege_mode=privilege;

assign exception_value=(cause==32'd0)? i_trap_addr:
                       (cause==32'd12)? pc:
                       ((cause==32'd4)||(cause==32'd6)||(cause==32'd13)||(cause==32'd15))? mem_addr:
                       32'b0;

endmodule
