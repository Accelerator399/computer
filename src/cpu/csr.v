module csr(
    input clk,
    input rst,

    input [1:0] csr_op,
    input [11:0] csr_addr,
    input [31:0] csr_wdata,
    input csr_we,
    output reg [31:0] csr_rdata,

    output external_csr_we,
    output [11:0] external_csr_addr,
    output [31:0] external_csr_wdata,
    input [31:0] external_csr_rdata,

    input exception,
    input [31:0] exception_pc,
    input [31:0] cause,
    input [31:0] trap_value,
    input mret,
    input sret,
    input fp_dirty,

    input ext_int,
    input timer_int,
    input soft_int,

    output [31:0] trap_vec,
    output [31:0] ret_epc,
    output mie,
    output int_pending,
    output [31:0] mip_out,
    output mstatus_sum,
    output mstatus_mxr,
    output [1:0] privilege
);

reg [31:0] mstatus_reg;
reg [31:0] mtvec_reg;
reg [31:0] mepc_reg;
reg [31:0] mcause_reg;
reg [31:0] mtval_reg;
reg [31:0] mie_reg;
reg [31:0] mip_sw_reg;
reg [31:0] mideleg_reg;
reg [31:0] medeleg_reg;
reg [4:0] fflags_reg;
reg [2:0] frm_reg;

reg [31:0] stvec_reg;
reg [31:0] sepc_reg;
reg [31:0] scause_reg;
reg [31:0] stval_reg;
reg [31:0] sscratch_reg;

reg [1:0] privilege_mode;

wire [31:0] mip;
wire [31:0] misa_value = 32'h4014_1121; // RV32 + F/I/M/A + user/supervisor support.
wire [31:0] mvendorid_value = 32'h0000_0000;
wire [31:0] marchid_value = 32'h0000_0001;
wire [31:0] mimpid_value = 32'h0000_0001;
wire [31:0] mhartid_value = 32'h0000_0000;

wire [31:0] sstatus_mask=32'h800DE762;
wire [31:0] sie_mask=32'h0000_0222;
wire [31:0] sstatus=mstatus_reg&sstatus_mask;
wire [31:0] sie=mie_reg&sie_mask;
wire [31:0] sip=mip&sie_mask;
wire [31:0] fcsr={24'b0,frm_reg,fflags_reg};

wire external_csr_sel=(csr_addr==12'h180); // satp is owned by the MMU.

wire soft_to_s = mideleg_reg[1];
wire timer_to_s = mideleg_reg[5];
wire ext_to_s = mideleg_reg[9];
wire soft_pending = mip_sw_reg[3] | mip_sw_reg[1] | soft_int;

assign mip={20'b0,
            ext_int & !ext_to_s, 1'b0, ext_int & ext_to_s, 1'b0,
            timer_int & !timer_to_s, 1'b0, timer_int & timer_to_s, 1'b0,
            soft_pending & !soft_to_s, 1'b0, soft_pending & soft_to_s, 1'b0};

wire [31:0] csr_cur;
assign csr_cur= (csr_addr==12'h001)? {27'b0,fflags_reg}:
                (csr_addr==12'h002)? {29'b0,frm_reg}:
                (csr_addr==12'h003)? fcsr:
                (csr_addr==12'h300)? mstatus_reg:
                (csr_addr==12'h301)? misa_value:
                (csr_addr==12'h302)? medeleg_reg:
                (csr_addr==12'h303)? mideleg_reg:
                (csr_addr==12'h304)? mie_reg:
                (csr_addr==12'h305)? mtvec_reg:
                (csr_addr==12'h341)? mepc_reg:
                (csr_addr==12'h342)? mcause_reg:
                (csr_addr==12'h343)? mtval_reg:
                (csr_addr==12'h344)? mip:
                (csr_addr==12'h100)? sstatus:
                (csr_addr==12'h104)? sie:
                (csr_addr==12'h105)? stvec_reg:
                (csr_addr==12'h140)? sscratch_reg:
                (csr_addr==12'h141)? sepc_reg:
                (csr_addr==12'h142)? scause_reg:
                (csr_addr==12'h143)? stval_reg:
                (csr_addr==12'h144)? sip:
                (csr_addr==12'hf11)? mvendorid_value:
                (csr_addr==12'hf12)? marchid_value:
                (csr_addr==12'hf13)? mimpid_value:
                (csr_addr==12'hf14)? mhartid_value:
                (external_csr_sel)? external_csr_rdata:
                32'b0;

wire [31:0] csr_reg;
assign csr_reg= (csr_op==2'b00)? csr_wdata:
                (csr_op==2'b01)? csr_cur|csr_wdata:
                (csr_op==2'b10)? csr_cur&(~csr_wdata):
                csr_cur;


always @(*) begin
    case(csr_addr)
        12'h001: csr_rdata={27'b0,fflags_reg};
        12'h002: csr_rdata={29'b0,frm_reg};
        12'h003: csr_rdata=fcsr;
        12'h300: csr_rdata=mstatus_reg;
        12'h301: csr_rdata=misa_value;
        12'h302: csr_rdata=medeleg_reg;
        12'h303: csr_rdata=mideleg_reg;
        12'h304: csr_rdata=mie_reg;
        12'h305: csr_rdata=mtvec_reg;
        12'h341: csr_rdata=mepc_reg;
        12'h342: csr_rdata=mcause_reg;
        12'h343: csr_rdata=mtval_reg;
        12'h344: csr_rdata=mip;

        12'h100: csr_rdata=sstatus;
        12'h104: csr_rdata=sie;
        12'h105: csr_rdata=stvec_reg;
        12'h140: csr_rdata=sscratch_reg;
        12'h141: csr_rdata=sepc_reg;
        12'h142: csr_rdata=scause_reg;
        12'h143: csr_rdata=stval_reg;
        12'h144: csr_rdata=sip;
        12'h180: csr_rdata=external_csr_rdata;
        12'hf11: csr_rdata=mvendorid_value;
        12'hf12: csr_rdata=marchid_value;
        12'hf13: csr_rdata=mimpid_value;
        12'hf14: csr_rdata=mhartid_value;
        default: csr_rdata=32'b0;
    endcase
end

wire is_int=cause[31];
wire trap_to_s= (privilege_mode<2'b11)&&
                (is_int? mideleg_reg[cause[4:0]]:
                medeleg_reg[cause[4:0]]);

always @(posedge clk) begin
    if(rst) begin
        mstatus_reg<=32'b0;
        mtvec_reg<=32'b0;
        mepc_reg<=32'b0;
        mcause_reg<=32'b0;
        mtval_reg<=32'b0;
        mie_reg<=32'b0;
        mip_sw_reg<=32'b0;
        mideleg_reg<=32'b0;
        medeleg_reg<=32'b0;
        fflags_reg<=5'b0;
        frm_reg<=3'b0;

        stvec_reg<=32'b0;
        sepc_reg<=32'b0;
        scause_reg<=32'b0;
        stval_reg<=32'b0;
        sscratch_reg<=32'b0;

        privilege_mode<=2'b11;
    end

    else if(exception) begin
        if(trap_to_s) begin
            sepc_reg<=exception_pc;
            scause_reg<=cause;
            stval_reg<=trap_value;
            mstatus_reg[8]<=privilege_mode[0];
            mstatus_reg[5]<=mstatus_reg[1];
            mstatus_reg[1]<=1'b0;
            privilege_mode<=2'b01;
        end else begin
            mepc_reg<=exception_pc;
            mcause_reg<=cause;
            mtval_reg<=trap_value;
            mstatus_reg[12:11]<=privilege_mode;
            mstatus_reg[7]<=mstatus_reg[3];
            mstatus_reg[3]<=1'b0;
            privilege_mode<=2'b11;
        end
    end else if(mret) begin
        privilege_mode<=mstatus_reg[12:11];
        mstatus_reg[3]<=mstatus_reg[7];
        mstatus_reg[7]<=1'b1;
    end else if(sret) begin
        privilege_mode<={1'b0,mstatus_reg[8]};
        mstatus_reg[1]<=mstatus_reg[5];
        mstatus_reg[5]<=1'b1;
    end else if(csr_we) begin
        case(csr_addr)
            12'h001: fflags_reg<=csr_reg[4:0];
            12'h002: frm_reg<=csr_reg[2:0];
            12'h003: begin
                fflags_reg<=csr_reg[4:0];
                frm_reg<=csr_reg[7:5];
            end
            12'h300: mstatus_reg<=csr_reg;
            12'h302: medeleg_reg<=csr_reg;
            12'h303: mideleg_reg<=csr_reg;
            12'h304: mie_reg<=csr_reg;
            12'h305: mtvec_reg<=csr_reg;
            12'h341: mepc_reg<=csr_reg;
            12'h342: mcause_reg<=csr_reg;
            12'h343: mtval_reg<=csr_reg;
            12'h344: begin
                mip_sw_reg[3]<=csr_reg[3];
                mip_sw_reg[1]<=csr_reg[1];
            end

            12'h100: mstatus_reg<=(mstatus_reg&~sstatus_mask)|(csr_reg&sstatus_mask);
            12'h104: mie_reg<=(mie_reg&~sie_mask)|(csr_reg&sie_mask);
            12'h105: stvec_reg<=csr_reg;
            12'h140: sscratch_reg<=csr_reg;
            12'h141: sepc_reg<=csr_reg;
            12'h142: scause_reg<=csr_reg;
            12'h143: stval_reg<=csr_reg;
            12'h144: mip_sw_reg[1]<=csr_reg[1];
        endcase
    end else if(fp_dirty) begin
        mstatus_reg[14:13]<=2'b11;
    end
end

assign trap_vec=trap_to_s? stvec_reg:mtvec_reg;
assign ret_epc=sret? sepc_reg:mepc_reg;
assign mie=mstatus_reg[3];
assign mip_out=mip;
assign mstatus_sum=mstatus_reg[18];
assign mstatus_mxr=mstatus_reg[19];
assign privilege=privilege_mode;

wire [31:0] pending=mie_reg&mip;
wire [31:0] m_pending=pending&(~mideleg_reg);
wire [31:0] s_pending=pending&mideleg_reg;
wire m_int_en=(privilege_mode<2'b11)||mstatus_reg[3];
wire s_int_en=(privilege_mode<2'b01)||((privilege_mode==2'b01)&&mstatus_reg[1]);
assign int_pending=((|m_pending)&&m_int_en)||((|s_pending)&&s_int_en);

assign external_csr_we=csr_we&&external_csr_sel;
assign external_csr_addr=csr_addr;
assign external_csr_wdata=csr_reg;

endmodule
