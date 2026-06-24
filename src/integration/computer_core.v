module computer_core #(
    parameter CLK_FREQ      = 50_000_000,
    parameter BAUD_RATE     = 115200,
    parameter RESET_VECTOR  = 32'h0000_0000,
    parameter MMIO_BASE     = 32'h1000_0000,
    parameter CLINT_BASE    = 32'h1000_0000,
    parameter PLIC_BASE     = 32'h1003_0000,
    parameter BOOT_ROM_ENABLE = 0,
    parameter BOOT_ROM_BASE = 32'h0000_0000,
    parameter BOOT_ROM_WORDS = 64,
    parameter BOOT_ROM_INIT_FILE = "",
    parameter TLB_ENTRIES   = 32
)(
    input clk,
    input rst,

    inout [31:0] pad,

    input ext_int,
    input timer_int,
    input soft_int,

    input [4:0] test_addr,
    output [31:0] test_data,
    output [2:0] state,

    output [31:0] pc_out,
    output [31:0] inst_out,
    output [31:0] mem_addr_out,
    output [31:0] mem_wdata_out,
    output [3:0] mem_wstrb_out,
    output mem_write_out,
    output [1:0] privilege_out,

    output [31:0] i_vaddr_out,
    output [31:0] d_vaddr_out,
    output [31:0] i_paddr_out,
    output [31:0] d_paddr_out,
    output i_page_fault_out,
    output d_page_fault_out,
    output [31:0] satp_out,
    output [31:0] i_tlb_miss_count_out,
    output [31:0] d_tlb_miss_count_out,

    output icache_mem_req,
    output icache_mem_we,
    output [31:0] icache_mem_addr,
    output [127:0] icache_mem_wdata,
    output [15:0] icache_mem_wstrb,
    input [127:0] icache_mem_rdata,
    input icache_mem_ready,

    output dcache_mem_req,
    output dcache_mem_we,
    output [31:0] dcache_mem_addr,
    output [127:0] dcache_mem_wdata,
    output [15:0] dcache_mem_wstrb,
    input [127:0] dcache_mem_rdata,
    input dcache_mem_ready,

    output walker_mem_req,
    output [31:0] walker_mem_addr,
    input [127:0] walker_mem_rdata,
    input walker_mem_ready
);

wire [31:0] cpu_pc;
wire [31:0] cpu_inst;
wire cpu_icache_ready;
wire [31:0] cpu_daddr;
wire [31:0] cpu_wdata;
wire [3:0] cpu_wstrb;
wire cpu_mem_write;
wire [31:0] cpu_rdata;
wire cpu_dcache_ready;
wire [1:0] cpu_privilege;

wire external_csr_we;
wire [11:0] external_csr_addr;
wire [31:0] external_csr_wdata;
wire [31:0] external_csr_rdata;
wire cpu_sfence_vma;
wire cpu_fence_i;
wire cpu_mstatus_sum;
wire cpu_mstatus_mxr;

wire [31:0] i_paddr;
wire [31:0] d_paddr;
wire i_page_fault;
wire d_page_fault;
wire i_translate_ready;
wire d_translate_ready;
wire i_translate_ready_raw;
wire d_translate_ready_raw;
wire [31:0] i_miss_count;
wire [31:0] d_miss_count;

localparam CPU_IF  = 3'd0;
localparam CPU_MEM = 3'd3;
localparam CPU_AMO_WRITE = 3'd7;

reg [31:0] satp_shadow;

always @(posedge clk) begin
    if(rst)
        satp_shadow<=32'b0;
    else if(external_csr_we && external_csr_addr==12'h180)
        satp_shadow<=external_csr_wdata;
end

wire i_req_valid = (state == CPU_IF);
wire d_req_valid = (state == CPU_MEM) || (state == CPU_AMO_WRITE);
wire mmu_active = satp_shadow[31] && (cpu_privilege != 2'b11);
wire direct_mmio = (cpu_daddr >= MMIO_BASE) && !mmu_active;
wire i_addr_misaligned;
wire d_addr_misaligned;
wire d_access_misaligned = d_req_valid && d_addr_misaligned;
wire [31:0] effective_d_paddr = direct_mmio ? cpu_daddr : d_paddr;
wire is_mmio = direct_mmio || (d_translate_ready && !d_page_fault && (effective_d_paddr >= MMIO_BASE));
wire is_clint = is_mmio && (effective_d_paddr >= CLINT_BASE) && (effective_d_paddr < (CLINT_BASE + 32'h0001_0000));
wire is_plic = is_mmio && (effective_d_paddr >= PLIC_BASE) && (effective_d_paddr < (PLIC_BASE + 32'h0040_0000));
wire [31:0] walker_pte =
    (walker_mem_addr[3:2] == 2'd0) ? walker_mem_rdata[31:0] :
    (walker_mem_addr[3:2] == 2'd1) ? walker_mem_rdata[63:32] :
    (walker_mem_addr[3:2] == 2'd2) ? walker_mem_rdata[95:64] :
                                      walker_mem_rdata[127:96];

mmu #(
    .TLB_ENTRIES(TLB_ENTRIES)
) u_mmu (
    .clk(clk),
    .rst(rst),
    .csr_we(external_csr_we),
    .csr_addr(external_csr_addr),
    .csr_wdata(external_csr_wdata),
    .csr_rdata(external_csr_rdata),
    .sfence_vma(cpu_sfence_vma),
    .privilege(cpu_privilege),
    .mstatus_sum(cpu_mstatus_sum),
    .mstatus_mxr(cpu_mstatus_mxr),
    .i_req_valid(i_req_valid),
    .i_vaddr(cpu_pc),
    .i_paddr(i_paddr),
    .i_page_fault(i_page_fault),
    .i_translate_ready(i_translate_ready_raw),
    .d_req_valid(d_req_valid && !direct_mmio && !d_access_misaligned),
    .d_vaddr(cpu_daddr),
    .d_write(cpu_mem_write),
    .d_paddr(d_paddr),
    .d_page_fault(d_page_fault),
    .d_translate_ready(d_translate_ready_raw),
    .walker_mem_addr(walker_mem_addr),
    .walker_mem_req(walker_mem_req),
    .walker_mem_rdata(walker_pte),
    .walker_mem_ready(walker_mem_ready),
    .i_miss_count(i_miss_count),
    .d_miss_count(d_miss_count),
    .dbg_mmu_enable(),
    .dbg_i_bypass(),
    .dbg_d_bypass(),
    .dbg_i_tlb_hit(),
    .dbg_d_tlb_hit(),
    .dbg_i_tlb_miss(),
    .dbg_d_tlb_miss()
);

assign i_translate_ready = i_translate_ready_raw;
assign d_translate_ready = d_translate_ready_raw && !d_access_misaligned;

reg icache_waiting;
reg icache_done;
reg [31:0] icache_req_paddr;
reg [31:0] icache_done_paddr;
wire [31:0] boot_rom_rdata;
wire boot_rom_hit_raw;
wire boot_rom_hit = BOOT_ROM_ENABLE && i_translate_ready && !i_page_fault && boot_rom_hit_raw;
wire boot_rom_fetch = i_req_valid && boot_rom_hit;
wire icache_done_current = icache_done && (icache_done_paddr == i_paddr);
wire icache_response_valid = cpu_icache_ready && icache_waiting &&
                             (icache_req_paddr == i_paddr) &&
                             i_req_valid && i_translate_ready &&
                             !boot_rom_hit && !i_page_fault;
wire icache_start = i_req_valid && i_translate_ready && !boot_rom_hit &&
                    !icache_waiting && !icache_done_current && !i_page_fault;
wire [31:0] icache_rdata;
wire cpu_if_ready = boot_rom_fetch || icache_response_valid;

boot_rom #(
    .BASE_ADDR(BOOT_ROM_BASE),
    .WORDS(BOOT_ROM_WORDS),
    .INIT_FILE(BOOT_ROM_INIT_FILE)
) u_boot_rom (
    .addr(i_paddr),
    .rdata(boot_rom_rdata),
    .hit(boot_rom_hit_raw)
);

always @(posedge clk) begin
    if(rst || !i_req_valid) begin
        icache_waiting<=1'b0;
        icache_done<=1'b0;
        icache_req_paddr<=32'b0;
        icache_done_paddr<=32'b0;
    end else begin
        if(icache_start)
        begin
            icache_waiting<=1'b1;
            icache_req_paddr<=i_paddr;
            icache_done<=1'b0;
            icache_done_paddr<=32'b0;
        end
        if(cpu_icache_ready) begin
            icache_waiting<=1'b0;
            if(icache_waiting && icache_req_paddr == i_paddr &&
               i_translate_ready && !i_page_fault && !boot_rom_hit) begin
                icache_done<=1'b1;
                icache_done_paddr<=icache_req_paddr;
            end
        end
        if(!icache_waiting && icache_done && !icache_done_current)
            icache_done<=1'b0;
    end
end

cache u_icache (
    .clk(clk),
    .rst(rst),
    .flush(cpu_fence_i),
    .cpu_req(icache_start),
    .cpu_we(1'b0),
    .cpu_addr(i_paddr),
    .cpu_wdata(32'b0),
    .cpu_wstrb(4'b0),
    .cpu_rdata(icache_rdata),
    .cpu_ready(cpu_icache_ready),
    .mem_req(icache_mem_req),
    .mem_we(icache_mem_we),
    .mem_addr(icache_mem_addr),
    .mem_wdata(icache_mem_wdata),
    .mem_wstrb(icache_mem_wstrb),
    .mem_rdata(icache_mem_rdata),
    .mem_ready(icache_mem_ready)
);

wire dcache_req_base = d_req_valid && d_translate_ready && !is_mmio && !d_page_fault;
reg dcache_waiting;
reg dcache_done;
reg [31:0] dcache_req_paddr;
reg [31:0] dcache_done_paddr;
wire dcache_ready;
wire dcache_done_current = dcache_done && (dcache_done_paddr == effective_d_paddr);
wire dcache_response_valid = dcache_ready && dcache_waiting &&
                             (dcache_req_paddr == effective_d_paddr) &&
                             d_req_valid && d_translate_ready &&
                             !is_mmio && !d_page_fault;
wire dcache_start = dcache_req_base && !dcache_waiting && !dcache_done_current;
wire [31:0] dcache_rdata;

always @(posedge clk) begin
    if(rst || !d_req_valid) begin
        dcache_waiting<=1'b0;
        dcache_done<=1'b0;
        dcache_req_paddr<=32'b0;
        dcache_done_paddr<=32'b0;
    end else begin
        if(dcache_start) begin
            dcache_waiting<=1'b1;
            dcache_req_paddr<=effective_d_paddr;
            dcache_done<=1'b0;
            dcache_done_paddr<=32'b0;
        end
        if(dcache_ready) begin
            dcache_waiting<=1'b0;
            if(dcache_waiting && dcache_req_paddr == effective_d_paddr &&
               d_translate_ready && !is_mmio && !d_page_fault) begin
                dcache_done<=1'b1;
                dcache_done_paddr<=dcache_req_paddr;
            end
        end
        if(!dcache_waiting && dcache_done && !dcache_done_current)
            dcache_done<=1'b0;
    end
end

cache u_dcache (
    .clk(clk),
    .rst(rst),
    .flush(1'b0),
    .cpu_req(dcache_start),
    .cpu_we(cpu_mem_write),
    .cpu_addr(effective_d_paddr),
    .cpu_wdata(cpu_wdata),
    .cpu_wstrb(cpu_wstrb),
    .cpu_rdata(dcache_rdata),
    .cpu_ready(dcache_ready),
    .mem_req(dcache_mem_req),
    .mem_we(dcache_mem_we),
    .mem_addr(dcache_mem_addr),
    .mem_wdata(dcache_mem_wdata),
    .mem_wstrb(dcache_mem_wstrb),
    .mem_rdata(dcache_mem_rdata),
    .mem_ready(dcache_mem_ready)
);

wire [31:0] iomux_rdata;
wire [31:0] clint_rdata;
wire clint_timer_int;
wire clint_soft_int;
wire [31:0] plic_rdata;
wire plic_ext_int;
wire uart_irq;

clint #(
    .BASE_ADDR(CLINT_BASE)
) u_clint (
    .clk(clk),
    .rst(rst),
    .addr(effective_d_paddr),
    .wdata(cpu_wdata),
    .wstrb(cpu_wstrb),
    .we(cpu_mem_write && is_clint && d_req_valid),
    .rdata(clint_rdata),
    .timer_int(clint_timer_int),
    .soft_int(clint_soft_int)
);

plic #(
    .BASE_ADDR(PLIC_BASE),
    .NUM_SOURCES(2)
) u_plic (
    .clk(clk),
    .rst(rst),
    .irq_sources({uart_irq, ext_int}),
    .addr(effective_d_paddr),
    .wdata(cpu_wdata),
    .wstrb(cpu_wstrb),
    .we(cpu_mem_write && is_plic && d_req_valid),
    .rdata(plic_rdata),
    .irq_out(plic_ext_int)
);

iomux #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) u_iomux (
    .clk(clk),
    .rst(rst),
    .addr(effective_d_paddr),
    .wdata(cpu_wdata),
    .we(cpu_mem_write && is_mmio && !is_clint && !is_plic && d_req_valid),
    .rdata(iomux_rdata),
    .pad(pad),
    .uart_irq(uart_irq)
);

assign cpu_rdata = is_mmio ? (is_clint ? clint_rdata : (is_plic ? plic_rdata : iomux_rdata)) : dcache_rdata;
assign cpu_dcache_ready = is_mmio ? d_req_valid : dcache_response_valid;

cpu #(
    .RESET_VECTOR(RESET_VECTOR)
) u_cpu (
    .clk(clk),
    .rst(rst),
    .pc(cpu_pc),
    .inst(cpu_inst),
    .icache_hit(i_page_fault ? 1'b0 : cpu_if_ready),
    .i_page_fault(i_page_fault),
    .i_addr_misaligned(i_addr_misaligned),
    .mem_addr(cpu_daddr),
    .mem_wdata(cpu_wdata),
    .mem_wstrb(cpu_wstrb),
    .mem_write(cpu_mem_write),
    .mem_rdata(cpu_rdata),
    .dcache_hit(d_page_fault || d_access_misaligned ? 1'b0 : cpu_dcache_ready),
    .d_page_fault(d_page_fault),
    .d_addr_misaligned(d_addr_misaligned),
    .external_csr_we(external_csr_we),
    .external_csr_addr(external_csr_addr),
    .external_csr_wdata(external_csr_wdata),
    .external_csr_rdata(external_csr_rdata),
    .sfence_vma(cpu_sfence_vma),
    .fence_i(cpu_fence_i),
    .mstatus_sum(cpu_mstatus_sum),
    .mstatus_mxr(cpu_mstatus_mxr),
    .privilege_mode(cpu_privilege),
    .ext_int(plic_ext_int),
    .timer_int(timer_int | clint_timer_int),
    .soft_int(soft_int | clint_soft_int),
    .test_addr(test_addr),
    .test_data(test_data),
    .state(state)
);

assign cpu_inst = boot_rom_fetch ? boot_rom_rdata : icache_rdata;

assign pc_out = cpu_pc;
assign inst_out = cpu_inst;
assign mem_addr_out = cpu_daddr;
assign mem_wdata_out = cpu_wdata;
assign mem_wstrb_out = cpu_wstrb;
assign mem_write_out = cpu_mem_write;
assign privilege_out = cpu_privilege;

assign i_vaddr_out = cpu_pc;
assign d_vaddr_out = cpu_daddr;
assign i_paddr_out = i_paddr;
assign d_paddr_out = effective_d_paddr;
assign i_page_fault_out = i_page_fault;
assign d_page_fault_out = d_page_fault;
assign satp_out = satp_shadow;
assign i_tlb_miss_count_out = i_miss_count;
assign d_tlb_miss_count_out = d_miss_count;

endmodule
