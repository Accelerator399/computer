module control(
    input clk,
    input rst,
    input [6:0] opcode,
    input [2:0] funct3,
    input [6:0] funct7,
    input [11:0] funct12,
    input zero,
    input icache_hit,
    input dcache_hit,
    input i_page_fault,
    input d_page_fault,
    input i_addr_misaligned,
    input d_addr_misaligned,
    input int_pending,
    input mie,
    input [31:0] mtvec,
    input [31:0] mepc,
    input [31:0] mip,
    input [1:0] privilege,
    input amo_sc_success,
    output reg pc_write,
    output reg [1:0] pc_src,
    output reg ir_write,
    output reg reg_write,
    output reg [2:0] wb_src,
    output reg alu_src_a,
    output reg [1:0] alu_src_b,
    output reg [1:0] alu_op,
    output reg mem_write,
    output reg alu_out_write,
    output reg ab_write,
    output reg mul_a_signed,
    output reg mul_b_signed,
    output reg mul_take_high,
    output reg div_is_signed,
    output reg [1:0] md_sel,
    output reg csr_we,
    output reg [1:0] csr_op,
    output reg exception,
    output reg [31:0] cause,
    output reg mret,
    output reg sret,
    output reg sfence_vma,
    output reg fence_i,
    output reg amo_old_write,
    output reg amo_sc_check,
    output reg amo_reservation_set,
    output reg amo_reservation_clear,
    output reg amo_wdata_sel,
    output reg trap_pc_src,
    output [2:0] state_out
);

parameter IF=3'd0;
parameter ID=3'd1;
parameter EX=3'd2;
parameter MEM=3'd3;
parameter WB=3'd4;
parameter TRAP=3'd5;
parameter AMO_CALC=3'd6;
parameter AMO_WRITE=3'd7;

reg [2:0] next_state;
reg [2:0] state;
reg [31:0] trap_cause_reg;

assign state_out=state;

wire is_system_inst;
wire is_priv_inst;
wire is_csr_inst;
wire is_ecall,is_ebreak,is_mret,is_sret,is_sfence_vma;
wire is_wfi;
wire legal_system_inst;
wire illegal_inst;
wire is_fence_inst;
wire is_fence_i;
wire is_amo_inst;
wire legal_amo_inst;
wire is_lr_w;
wire is_sc_w;
wire [4:0] amo_funct5;

assign is_system_inst=(opcode==7'b1110011);
assign is_priv_inst=is_system_inst&&(funct3==3'b000);
assign is_csr_inst=is_system_inst&&(funct3!=3'b000);
assign is_ecall=is_priv_inst&&(funct12==12'h000);
assign is_ebreak=is_priv_inst&&(funct12==12'h001);
assign is_mret=is_priv_inst&&(funct12==12'h302);
assign is_sret=is_priv_inst&&(funct12==12'h102);
assign is_sfence_vma=is_priv_inst&&(funct7==7'b0001001);
assign is_wfi=is_priv_inst&&(funct12==12'h105);
assign legal_system_inst=is_csr_inst||is_ecall||is_ebreak||is_mret||is_sret||is_sfence_vma||is_wfi;

assign is_fence_inst=(opcode==7'b0001111);
assign is_fence_i=is_fence_inst&&(funct3==3'b001);

assign is_amo_inst=(opcode==7'b0101111)&&(funct3==3'b010);
assign amo_funct5=funct7[6:2];
assign is_lr_w=is_amo_inst&&(amo_funct5==5'b00010);
assign is_sc_w=is_amo_inst&&(amo_funct5==5'b00011);
assign legal_amo_inst=is_amo_inst&&
    (amo_funct5==5'b00000||amo_funct5==5'b00001||
     amo_funct5==5'b00010||amo_funct5==5'b00011||
     amo_funct5==5'b00100||amo_funct5==5'b01000||
     amo_funct5==5'b01100||amo_funct5==5'b10000||
     amo_funct5==5'b10100||amo_funct5==5'b11000||
     amo_funct5==5'b11100);

assign illegal_inst=(state==ID)&&
    !(opcode==7'b0110011||opcode==7'b0010011||
      opcode==7'b0000011||opcode==7'b0100011||
      opcode==7'b1100011||opcode==7'b1101111||
      opcode==7'b1100111||opcode==7'b0110111||
      opcode==7'b0010111||(is_system_inst&&legal_system_inst)||
      is_fence_inst||
      legal_amo_inst);

wire [31:0] interrupt_cause = mip[11] ? 32'h8000000B :
                              mip[9]  ? 32'h80000009 :
                              mip[7]  ? 32'h80000007 :
                              mip[5]  ? 32'h80000005 :
                              mip[3]  ? 32'h80000003 :
                              mip[1]  ? 32'h80000001 :
                                        32'h8000000B;
wire [31:0] ecall_cause = (privilege==2'b00) ? 32'd8 :
                          (privilege==2'b01) ? 32'd9 :
                                                32'd11;
wire [31:0] d_misaligned_cause = ((opcode==7'b0000011)||is_lr_w) ? 32'd4 : 32'd6;
wire [31:0] trap_cause_next =
    (i_addr_misaligned && state==EX) ? 32'd0 :
    (d_addr_misaligned && (state==MEM || state==AMO_CALC || state==AMO_WRITE)) ?
                                  d_misaligned_cause :
    (i_page_fault && state==IF)  ? 32'd12 :
    (d_page_fault && (state==MEM || state==AMO_WRITE)) ?
                                  (((opcode==7'b0100011) || state==AMO_WRITE) ? 32'd15 : 32'd13) :
    (int_pending && state==IF)   ? interrupt_cause :
    is_ecall                     ? ecall_cause :
    is_ebreak                    ? 32'd3 :
    illegal_inst                 ? 32'd2 :
                                   32'd0;

always @(posedge clk) begin
    if(rst) begin
        state<=IF;
        trap_cause_reg<=32'b0;
    end else begin
        state<=next_state;
        if(state!=TRAP && next_state==TRAP)
            trap_cause_reg<=trap_cause_next;
    end
end

always @(*) begin
    if(i_addr_misaligned && state==EX) begin
        next_state=TRAP;
    end else if(i_page_fault&&state==IF) begin
        next_state=TRAP;
    end else if(int_pending&&state==IF) begin
        next_state=TRAP;
    end else begin
        case(state)
            IF:next_state=icache_hit? ID:IF;
            ID:begin
                if(illegal_inst||is_ecall||is_ebreak)
                    next_state=TRAP;
                else if(is_mret||is_sret)
                    next_state=EX;
                else
                    next_state=EX;
            end
            EX:begin
                case(opcode)
                    7'b0000011:next_state=MEM; // Load
                    7'b0100011:next_state=MEM; // Store
                    7'b0101111:next_state=is_sc_w ? AMO_CALC : MEM; // Atomic
                    7'b0001111:next_state=IF;  // FENCE/FENCE.I
                    7'b1100011:next_state=IF;  // Branch不写回
                    7'b1101111:next_state=IF;  // JAL需要写回但PC已更新
                    7'b1100111:next_state=IF;  // JALR需要写回但PC已更新
                    7'b1110011:begin
                        if(is_mret||is_sret||is_sfence_vma||is_wfi)
                            next_state=IF;
                        else
                            next_state=WB;
                    end
                    default:next_state=WB;
                endcase
            end
            MEM:begin
                if(d_addr_misaligned)
                    next_state=TRAP;
                else if(d_page_fault)
                    next_state=TRAP;
                else if(dcache_hit) begin
                    case(opcode)
                        7'b0100011:next_state=IF; // Store不写回
                        7'b0101111:next_state=AMO_CALC;
                        default:next_state=WB;
                    endcase
                end else
                    next_state=MEM;
            end
            AMO_CALC:begin
                if(d_addr_misaligned)
                    next_state=TRAP;
                else if(is_lr_w)
                    next_state=WB;
                else if(is_sc_w)
                    next_state=amo_sc_success ? AMO_WRITE : WB;
                else
                    next_state=AMO_WRITE;
            end
            AMO_WRITE:begin
                if(d_addr_misaligned)
                    next_state=TRAP;
                else if(d_page_fault)
                    next_state=TRAP;
                else
                    next_state=dcache_hit ? WB : AMO_WRITE;
            end
            WB:next_state=IF;
            TRAP:next_state=IF;
            default:next_state=IF;
        endcase
    end
end

always @(*) begin
    // 默认值
    pc_write=1'b0;
    ir_write=1'b0;
    reg_write=1'b0;
    mem_write=1'b0;
    alu_out_write=1'b0;
    ab_write=1'b0;
    pc_src=2'b00;
    alu_src_a=1'b0;
    alu_src_b=2'b00;
    alu_op=2'b00;
    wb_src=3'b000;
    mul_a_signed=1'b0;
    mul_b_signed=1'b0;
    mul_take_high=1'b0;
    div_is_signed=1'b0;
    md_sel=2'b00;
    csr_we=1'b0;
    csr_op=2'b00;
    exception=1'b0;
    cause=32'b0;
    mret=1'b0;
    sret=1'b0;
    sfence_vma=1'b0;
    fence_i=1'b0;
    amo_old_write=1'b0;
    amo_sc_check=1'b0;
    amo_reservation_set=1'b0;
    amo_reservation_clear=1'b0;
    amo_wdata_sel=1'b0;
    trap_pc_src=1'b0;

    case(state)
        IF:begin
            ir_write=icache_hit && !i_page_fault;
        end

        ID:begin
            ab_write=1'b1; // ID阶段锁存A/B
        end

        EX:begin
            alu_out_write=1'b1; // EX阶段锁存ALU结果
            case(opcode)
                7'b0110011:begin // R型
                    if(funct7==7'b0000001) begin // M扩展
                        case(funct3)
                            3'b000:begin // MUL
                                mul_a_signed=1'b1;
                                mul_b_signed=1'b1;
                                md_sel=2'b00;
                            end
                            3'b001:begin // MULH
                                mul_a_signed=1'b1;
                                mul_b_signed=1'b1;
                                mul_take_high=1'b1;
                                md_sel=2'b00;
                            end
                            3'b010:begin // MULHSU
                                mul_a_signed=1'b1;
                                md_sel=2'b00;
                                mul_take_high=1'b1;
                            end
                            3'b011:begin // MULHU
                                mul_take_high=1'b1;
                                md_sel=2'b00;
                            end
                            3'b100:begin // DIV
                                div_is_signed=1'b1;
                                md_sel=2'b01;
                            end
                            3'b101:begin // DIVU
                                md_sel=2'b01;
                            end
                            3'b110:begin // REM
                                div_is_signed=1'b1;
                                md_sel=2'b10;
                            end
                            3'b111:begin // REMU
                                md_sel=2'b10;
                            end
                        endcase
                    end else begin
                        alu_src_a=1'b0;
                        alu_src_b=2'b00;
                        alu_op=2'b10;
                    end
                end
                7'b0010011:begin // I型运算
                    alu_src_a=1'b0;
                    alu_src_b=2'b01;
                    alu_op=2'b10;
                end
                7'b0000011:begin // Load
                    alu_src_a=1'b0;
                    alu_src_b=2'b01;
                    alu_op=2'b00; // ADD计算地址
                end
                7'b0100011:begin // Store
                    alu_src_a=1'b0;
                    alu_src_b=2'b01;
                    alu_op=2'b00; // ADD计算地址
                end
                7'b0101111:begin // Atomic
                    alu_src_a=1'b0;
                    alu_src_b=2'b11;
                    alu_op=2'b00; // rs1 + 0
                end
                7'b0001111:begin // FENCE/FENCE.I
                    fence_i=is_fence_i;
                    pc_write=1'b1;
                    pc_src=2'b00; // PC+4
                end
                7'b1100011:begin // Branch
                    alu_src_a=1'b0;
                    alu_src_b=2'b00;
                    case(funct3)
                        3'b000:begin // BEQ: SUB, branch if zero
                            alu_op=2'b01;
                            pc_src=zero? 2'b01:2'b00;
                        end
                        3'b001:begin // BNE: SUB, branch if !zero
                            alu_op=2'b01;
                            pc_src=~zero? 2'b01:2'b00;
                        end
                        3'b100:begin // BLT: SLT, branch if result=1 (!zero)
                            alu_op=2'b10;
                            pc_src=~zero? 2'b01:2'b00;
                        end
                        3'b101:begin // BGE: SLT, branch if result=0 (zero)
                            alu_op=2'b10;
                            pc_src=zero? 2'b01:2'b00;
                        end
                        3'b110:begin // BLTU: SLTU, branch if result=1 (!zero)
                            alu_op=2'b10;
                            pc_src=~zero? 2'b01:2'b00;
                        end
                        3'b111:begin // BGEU: SLTU, branch if result=0 (zero)
                            alu_op=2'b10;
                            pc_src=zero? 2'b01:2'b00;
                        end
                        default:begin
                            alu_op=2'b01;
                            pc_src=2'b00;
                        end
                    endcase
                    pc_write=!i_addr_misaligned;
                end
                7'b1101111:begin // JAL
                    alu_src_a=1'b1; // PC
                    alu_src_b=2'b01;
                    alu_op=2'b00;
                    pc_write=!i_addr_misaligned;
                    pc_src=2'b01; // PC+imm
                    reg_write=!i_addr_misaligned;
                    wb_src=3'b010; // PC+4
                end
                7'b1100111:begin // JALR
                    alu_src_a=1'b0; // A
                    alu_src_b=2'b01;
                    alu_op=2'b00;
                    pc_write=!i_addr_misaligned;
                    pc_src=2'b10; // A+imm
                    reg_write=!i_addr_misaligned;
                    wb_src=3'b010; // PC+4
                end
                7'b0110111:begin // LUI
                    alu_src_a=1'b0;
                    alu_src_b=2'b01;
                    alu_op=2'b00;
                end
                7'b0010111:begin // AUIPC
                    alu_src_a=1'b1; // PC
                    alu_src_b=2'b01;
                    alu_op=2'b00;
                end
                7'b1110011:begin // CSR指令和特权指令
                    if(is_csr_inst) begin
                        // CSR读写在WB阶段完成
                    end else if(is_mret) begin
                        mret=1'b1;
                        pc_write=1'b1;
                        trap_pc_src=1'b1; // PC=mepc
                    end else if(is_sret) begin
                        sret=1'b1;
                        pc_write=1'b1;
                        trap_pc_src=1'b1; // PC=sepc
                    end else if(is_sfence_vma) begin
                        sfence_vma=1'b1;
                        pc_write=1'b1;
                        pc_src=2'b00; // PC+4
                    end else if(is_wfi) begin
                        pc_write=1'b1;
                        pc_src=2'b00; // WFI acts as a conservative NOP for now.
                    end
                end
                default:begin
                end
            endcase
        end

        MEM:begin
            case(opcode)
                7'b0100011:begin // Store
                    mem_write=!d_addr_misaligned;
                    amo_reservation_clear=!d_addr_misaligned;
                    if(dcache_hit && !d_page_fault) begin
                        pc_write=1'b1;
                        pc_src=2'b00; // PC+4
                    end
                end
                default:begin // Load
                end
            endcase
        end

        AMO_CALC:begin
            amo_old_write=!d_addr_misaligned && !is_sc_w;
            amo_sc_check=!d_addr_misaligned && is_sc_w;
        end

        AMO_WRITE:begin
            mem_write=!d_addr_misaligned;
            amo_wdata_sel=1'b1;
            amo_reservation_clear=!d_addr_misaligned;
        end

        WB:begin
            reg_write=1'b1;
            pc_write=1'b1;
            pc_src=2'b00; // PC+4
            case(opcode)
                7'b0000011:wb_src=3'b001; // Load: mdr
                7'b0101111:begin
                    wb_src=3'b110; // Atomic old value or SC status
                    if(is_lr_w)
                        amo_reservation_set=1'b1;
                    else if(is_sc_w)
                        amo_reservation_clear=1'b1;
                end
                7'b0110011:begin
                    if(funct7==7'b0000001) begin // M扩展
                        wb_src=3'b011;
                        case(funct3)
                            3'b000:begin mul_a_signed=1'b1; mul_b_signed=1'b1; end
                            3'b001:begin mul_a_signed=1'b1; mul_b_signed=1'b1; mul_take_high=1'b1; end
                            3'b010:begin mul_a_signed=1'b1; mul_take_high=1'b1; end
                            3'b011:begin mul_take_high=1'b1; end
                            3'b100:begin div_is_signed=1'b1; md_sel=2'b01; end
                            3'b101:begin md_sel=2'b01; end
                            3'b110:begin div_is_signed=1'b1; md_sel=2'b10; end
                            3'b111:begin md_sel=2'b10; end
                        endcase
                    end else
                        wb_src=3'b000;
                end
                7'b1110011:begin // CSR指令
                    if(is_csr_inst) begin
                        csr_we=1'b1;
                        wb_src=3'b100; // csr_rdata
                        case(funct3)
                            3'b001,3'b101:csr_op=2'b00; // CSRRW/CSRRWI
                            3'b010,3'b110:csr_op=2'b01; // CSRRS/CSRRSI
                            3'b011,3'b111:csr_op=2'b10; // CSRRC/CSRRCI
                        endcase
                    end else begin
                        reg_write=1'b0;
                        wb_src=3'b000;
                    end
                end
                default:wb_src=3'b000;    // alu_out
                7'b0110111:wb_src=3'b101; // LUI: imm
            endcase
        end

        TRAP:begin
            exception=1'b1;
            pc_write=1'b1;
            pc_src=2'b11; // mtvec/stvec
            trap_pc_src=1'b0;
            cause=trap_cause_reg;
        end
    endcase
end

endmodule

