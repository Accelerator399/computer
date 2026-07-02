`timescale 1ns/1ps

// RISC-V Sv32 MMU with fillable TLB and a two-level hardware page-table walker.
// The walker reads 32-bit PTEs through a simple memory request/ready port.

module mmu #(
    parameter TLB_ENTRIES = 32
)(
    input clk,
    input rst,

    input csr_we,
    input [11:0] csr_addr,
    input [31:0] csr_wdata,
    output [31:0] csr_rdata,
    input sfence_vma,

    input [1:0] privilege,
    input [1:0] d_privilege,
    input mstatus_sum,
    input mstatus_mxr,

    input i_req_valid,
    input [31:0] i_vaddr,
    output [31:0] i_paddr,
    output i_page_fault,
    output i_translate_ready,

    input d_req_valid,
    input [31:0] d_vaddr,
    input d_write,
    output [31:0] d_paddr,
    output d_page_fault,
    output d_translate_ready,

    output [31:0] walker_mem_addr,
    output walker_mem_req,
    input [31:0] walker_mem_rdata,
    input walker_mem_ready,

    output [31:0] i_miss_count,
    output [31:0] d_miss_count,

    output dbg_mmu_enable,
    output dbg_i_bypass,
    output dbg_d_bypass,
    output dbg_i_tlb_hit,
    output dbg_d_tlb_hit,
    output dbg_i_tlb_miss,
    output dbg_d_tlb_miss
);

localparam PRIV_U = 2'b00;
localparam PRIV_M = 2'b11;

localparam WALK_IDLE    = 3'd0;
localparam WALK_L1_REQ  = 3'd1;
localparam WALK_L1_WAIT = 3'd2;
localparam WALK_L0_REQ  = 3'd3;
localparam WALK_L0_WAIT = 3'd4;
localparam WALK_FILL    = 3'd5;
localparam WALK_FAULT   = 3'd6;

reg [31:0] satp_reg;
reg tlb_flush;

always @(posedge clk) begin
    if(rst) begin
        satp_reg <= 32'b0;
        tlb_flush <= 1'b0;
    end else begin
        tlb_flush <= 1'b0;
        if(sfence_vma)
            tlb_flush <= 1'b1;
        if(csr_we && csr_addr == 12'h180) begin
            satp_reg <= csr_wdata;
            tlb_flush <= 1'b1;
        end
    end
end

assign csr_rdata = (csr_addr == 12'h180) ? satp_reg : 32'b0;

wire mmu_enable = satp_reg[31];
wire [21:0] root_ppn = satp_reg[21:0];

wire i_bypass = (privilege == PRIV_M) || !mmu_enable;
wire d_bypass = (d_privilege == PRIV_M) || !mmu_enable;

wire [33:0] tlb_i_paddr;
wire [33:0] tlb_d_paddr;
wire tlb_i_hit;
wire tlb_i_miss;
wire tlb_i_page_fault;
wire tlb_d_hit;
wire tlb_d_miss;
wire tlb_d_page_fault;

reg fill_valid;
reg [19:0] fill_vpn;
reg [21:0] fill_ppn;
reg fill_superpage;
reg fill_r;
reg fill_w;
reg fill_x;
reg fill_u;

mmu_tlb #(
    .TLB_ENTRIES(TLB_ENTRIES)
) tlb_inst (
    .clk(clk),
    .rst(rst),
    .flush(tlb_flush),
    .privilege(privilege),
    .d_privilege(d_privilege),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    .i_req_valid(i_req_valid && !i_bypass),
    .i_vaddr(i_vaddr),
    .i_paddr(tlb_i_paddr),
    .i_hit(tlb_i_hit),
    .i_miss(tlb_i_miss),
    .i_page_fault(tlb_i_page_fault),
    .d_req_valid(d_req_valid && !d_bypass),
    .d_vaddr(d_vaddr),
    .d_write(d_write),
    .d_paddr(tlb_d_paddr),
    .d_hit(tlb_d_hit),
    .d_miss(tlb_d_miss),
    .d_page_fault(tlb_d_page_fault),
    .fill_valid(fill_valid),
    .fill_vpn(fill_vpn),
    .fill_ppn(fill_ppn),
    .fill_superpage(fill_superpage),
    .fill_r(fill_r),
    .fill_w(fill_w),
    .fill_x(fill_x),
    .fill_u(fill_u)
);

reg [31:0] i_miss_count_reg;
reg [31:0] d_miss_count_reg;
assign i_miss_count = i_miss_count_reg;
assign d_miss_count = d_miss_count_reg;

reg [2:0] walk_state;
reg walk_is_data;
reg walk_write;
reg [1:0] walk_privilege;
reg [31:0] walk_vaddr;
reg walk_fault;
reg [31:0] l1_pte;
reg [31:0] l0_pte;
reg [31:0] walker_addr_reg;
reg walker_req_reg;

wire [31:0] active_pte = ((walk_state == WALK_L1_WAIT) || (walk_state == WALK_L0_WAIT)) ?
                         walker_mem_rdata : l0_pte;

wire pte_v = active_pte[0];
wire pte_r = active_pte[1];
wire pte_w = active_pte[2];
wire pte_x = active_pte[3];
wire pte_u = active_pte[4];
wire pte_a = active_pte[6];
wire pte_d = active_pte[7];
wire [21:0] pte_ppn = active_pte[31:10];
wire pte_leaf = pte_r || pte_x;
wire pte_invalid = !pte_v || (pte_w && !pte_r);
wire pte_priv_fault = (walk_privilege == PRIV_U) ? !pte_u :
                      (pte_u && (!walk_is_data || !mstatus_sum));
wire pte_read_allowed = pte_r || (mstatus_mxr && pte_x);
wire pte_perm_fault = walk_is_data ? (walk_write ? !pte_w : !pte_read_allowed) : !pte_x;
wire pte_ad_fault = !pte_a || (walk_is_data && walk_write && !pte_d);
wire leaf_access_fault = pte_priv_fault || pte_perm_fault || pte_ad_fault;
wire leaf_page_fault = pte_invalid || !pte_leaf || leaf_access_fault;
wire superpage_align_fault = |pte_ppn[9:0];

wire [9:0] walk_vpn1 = walk_vaddr[31:22];
wire [9:0] walk_vpn0 = walk_vaddr[21:12];
wire [19:0] walk_vpn = walk_vaddr[31:12];
wire [33:0] l1_pte_addr = {root_ppn, 12'b0} + {22'b0, walk_vaddr[31:22], 2'b00};
wire [33:0] l0_pte_addr = {l1_pte[31:10], 12'b0} + {22'b0, walk_vaddr[21:12], 2'b00};

assign walker_mem_addr = walker_addr_reg;
assign walker_mem_req = walker_req_reg;

wire walker_busy = (walk_state != WALK_IDLE);
wire i_walk_active = walker_busy && !walk_is_data;
wire d_walk_active = walker_busy && walk_is_data;

wire i_miss_needs_walk = i_req_valid && !i_bypass && tlb_i_miss;
wire d_miss_needs_walk = d_req_valid && !d_bypass && tlb_d_miss;

wire start_i_walk = !walker_busy && i_miss_needs_walk;
wire start_d_walk = !walker_busy && !i_miss_needs_walk && d_miss_needs_walk;

assign i_paddr = i_bypass ? i_vaddr : tlb_i_paddr[31:0];
assign d_paddr = d_bypass ? d_vaddr : tlb_d_paddr[31:0];

assign i_translate_ready = i_bypass || tlb_i_hit || (i_page_fault && i_req_valid);
assign d_translate_ready = d_bypass || tlb_d_hit || (d_page_fault && d_req_valid);

assign i_page_fault = !i_bypass && (tlb_i_page_fault || (i_walk_active && walk_fault));
assign d_page_fault = !d_bypass && (tlb_d_page_fault || (d_walk_active && walk_fault));

assign dbg_mmu_enable = mmu_enable;
assign dbg_i_bypass = i_bypass;
assign dbg_d_bypass = d_bypass;
assign dbg_i_tlb_hit = tlb_i_hit;
assign dbg_d_tlb_hit = tlb_d_hit;
assign dbg_i_tlb_miss = tlb_i_miss;
assign dbg_d_tlb_miss = tlb_d_miss;

always @(posedge clk) begin
    if(rst) begin
        walk_state <= WALK_IDLE;
        walk_is_data <= 1'b0;
        walk_write <= 1'b0;
        walk_privilege <= PRIV_M;
        walk_vaddr <= 32'b0;
        walk_fault <= 1'b0;
        l1_pte <= 32'b0;
        l0_pte <= 32'b0;
        walker_addr_reg <= 32'b0;
        walker_req_reg <= 1'b0;
        fill_valid <= 1'b0;
        fill_vpn <= 20'b0;
        fill_ppn <= 22'b0;
        fill_superpage <= 1'b0;
        fill_r <= 1'b0;
        fill_w <= 1'b0;
        fill_x <= 1'b0;
        fill_u <= 1'b0;
        i_miss_count_reg <= 32'b0;
        d_miss_count_reg <= 32'b0;
    end else begin
        fill_valid <= 1'b0;
        walker_req_reg <= 1'b0;

        case(walk_state)
            WALK_IDLE: begin
                walk_fault <= 1'b0;
                if(start_i_walk) begin
                    walk_is_data <= 1'b0;
                    walk_write <= 1'b0;
                    walk_privilege <= privilege;
                    walk_vaddr <= i_vaddr;
                    walker_addr_reg <= {root_ppn, 12'b0} + {22'b0, i_vaddr[31:22], 2'b00};
                    walker_req_reg <= 1'b1;
                    walk_state <= WALK_L1_REQ;
                    i_miss_count_reg <= i_miss_count_reg + 1'b1;
                end else if(start_d_walk) begin
                    walk_is_data <= 1'b1;
                    walk_write <= d_write;
                    walk_privilege <= d_privilege;
                    walk_vaddr <= d_vaddr;
                    walker_addr_reg <= {root_ppn, 12'b0} + {22'b0, d_vaddr[31:22], 2'b00};
                    walker_req_reg <= 1'b1;
                    walk_state <= WALK_L1_REQ;
                    d_miss_count_reg <= d_miss_count_reg + 1'b1;
                end
            end

            WALK_L1_REQ: begin
                walker_req_reg <= 1'b1;
                walk_state <= WALK_L1_WAIT;
            end

            WALK_L1_WAIT: begin
                if(walker_mem_ready) begin
                    l1_pte <= walker_mem_rdata;
                    if(pte_invalid) begin
                        walk_fault <= 1'b1;
                        walk_state <= WALK_FAULT;
                    end else if(pte_leaf) begin
                        if(leaf_access_fault || superpage_align_fault) begin
                            walk_fault <= 1'b1;
                            walk_state <= WALK_FAULT;
                        end else begin
                            fill_valid <= 1'b1;
                            fill_vpn <= walk_vpn;
                            fill_ppn <= pte_ppn;
                            fill_superpage <= 1'b1;
                            fill_r <= pte_r;
                            fill_w <= pte_w;
                            fill_x <= pte_x;
                            fill_u <= pte_u;
                            walk_state <= WALK_FILL;
                        end
                    end else begin
                        walker_addr_reg <= {walker_mem_rdata[31:10], 12'b0} + {22'b0, walk_vpn0, 2'b00};
                        walker_req_reg <= 1'b1;
                        walk_state <= WALK_L0_REQ;
                    end
                end
            end

            WALK_L0_REQ: begin
                walker_req_reg <= 1'b1;
                walk_state <= WALK_L0_WAIT;
            end

            WALK_L0_WAIT: begin
                if(walker_mem_ready) begin
                    l0_pte <= walker_mem_rdata;
                    if(leaf_page_fault) begin
                        walk_fault <= 1'b1;
                        walk_state <= WALK_FAULT;
                    end else begin
                        fill_valid <= 1'b1;
                        fill_vpn <= walk_vpn;
                        fill_ppn <= pte_ppn;
                        fill_superpage <= 1'b0;
                        fill_r <= pte_r;
                        fill_w <= pte_w;
                        fill_x <= pte_x;
                        fill_u <= pte_u;
                        walk_state <= WALK_FILL;
                    end
                end
            end

            WALK_FILL: begin
                walk_state <= WALK_IDLE;
            end

            WALK_FAULT: begin
                if((walk_is_data && d_req_valid) || (!walk_is_data && i_req_valid))
                    walk_state <= WALK_FAULT;
                else
                    walk_state <= WALK_IDLE;
            end

            default: begin
                walk_state <= WALK_IDLE;
            end
        endcase
    end
end

endmodule
