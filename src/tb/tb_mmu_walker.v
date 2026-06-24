`timescale 1ns/1ps

module tb_mmu_walker;

localparam [1:0] PRIV_U = 2'b00;
localparam [1:0] PRIV_S = 2'b01;
localparam [1:0] PRIV_M = 2'b11;

localparam [7:0] PTE_V = 8'h01;
localparam [7:0] PTE_R = 8'h02;
localparam [7:0] PTE_W = 8'h04;
localparam [7:0] PTE_X = 8'h08;
localparam [7:0] PTE_U = 8'h10;
localparam [7:0] PTE_A = 8'h40;
localparam [7:0] PTE_D = 8'h80;

localparam [31:0] SATP_SV32_ROOT1 = 32'h8000_0001;

reg clk;
reg rst;

reg csr_we;
reg [11:0] csr_addr;
reg [31:0] csr_wdata;
wire [31:0] csr_rdata;
reg sfence_vma;
reg mstatus_sum;
reg mstatus_mxr;

reg [1:0] privilege;

reg i_req_valid;
reg [31:0] i_vaddr;
wire [31:0] i_paddr;
wire i_page_fault;
wire i_translate_ready;

reg d_req_valid;
reg [31:0] d_vaddr;
reg d_write;
wire [31:0] d_paddr;
wire d_page_fault;
wire d_translate_ready;

wire [31:0] walker_mem_addr;
wire walker_mem_req;
reg [31:0] walker_mem_rdata;
reg walker_mem_ready;

wire [31:0] i_miss_count;
wire [31:0] d_miss_count;

reg [31:0] pte_mem [0:16383];

mmu #(
    .TLB_ENTRIES(8)
) dut (
    .clk(clk),
    .rst(rst),
    .csr_we(csr_we),
    .csr_addr(csr_addr),
    .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata),
    .sfence_vma(sfence_vma),
    .privilege(privilege),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    .i_req_valid(i_req_valid),
    .i_vaddr(i_vaddr),
    .i_paddr(i_paddr),
    .i_page_fault(i_page_fault),
    .i_translate_ready(i_translate_ready),
    .d_req_valid(d_req_valid),
    .d_vaddr(d_vaddr),
    .d_write(d_write),
    .d_paddr(d_paddr),
    .d_page_fault(d_page_fault),
    .d_translate_ready(d_translate_ready),
    .walker_mem_addr(walker_mem_addr),
    .walker_mem_req(walker_mem_req),
    .walker_mem_rdata(walker_mem_rdata),
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

function automatic [31:0] make_pte;
    input [21:0] ppn;
    input [7:0] flags;
    begin
        make_pte = {ppn, 10'b0} | {24'b0, flags};
    end
endfunction

task automatic check;
    input condition;
    input string message;
    begin
        if(!condition) begin
            $display("FAIL: %s", message);
            $fatal(1);
        end else begin
            $display("PASS: %s", message);
        end
    end
endtask

task automatic set_pte;
    input [31:0] addr;
    input [31:0] pte;
    begin
        pte_mem[addr[15:2]] = pte;
    end
endtask

task automatic write_satp;
    input [31:0] value;
    begin
        @(negedge clk);
        csr_addr = 12'h180;
        csr_wdata = value;
        csr_we = 1'b1;
        @(negedge clk);
        csr_we = 1'b0;
        csr_addr = 12'b0;
        csr_wdata = 32'b0;
        @(posedge clk);
        #1;
    end
endtask

task automatic pulse_sfence_vma;
    begin
        @(negedge clk);
        sfence_vma = 1'b1;
        @(negedge clk);
        sfence_vma = 1'b0;
        @(posedge clk);
        #1;
    end
endtask

task automatic wait_i_ready;
    input integer max_cycles;
    input string message;
    integer n;
    reg seen;
    begin
        seen = 1'b0;
        for(n = 0; n < max_cycles; n = n + 1) begin
            @(posedge clk);
            #1;
            if(i_translate_ready) begin
                seen = 1'b1;
                n = max_cycles;
            end
        end
        check(seen, message);
    end
endtask

task automatic wait_d_ready;
    input integer max_cycles;
    input string message;
    integer n;
    reg seen;
    begin
        seen = 1'b0;
        for(n = 0; n < max_cycles; n = n + 1) begin
            @(posedge clk);
            #1;
            if(d_translate_ready) begin
                seen = 1'b1;
                n = max_cycles;
            end
        end
        check(seen, message);
    end
endtask

task automatic clear_i_req;
    begin
        i_req_valid = 1'b0;
        @(posedge clk);
        #1;
    end
endtask

task automatic clear_d_req;
    begin
        d_req_valid = 1'b0;
        d_write = 1'b0;
        @(posedge clk);
        #1;
    end
endtask

integer idx;

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

initial begin
    for(idx = 0; idx < 16384; idx = idx + 1)
        pte_mem[idx] = 32'b0;
end

always @(posedge clk) begin
    if(rst) begin
        walker_mem_ready <= 1'b0;
        walker_mem_rdata <= 32'b0;
    end else begin
        walker_mem_ready <= 1'b0;
        if(walker_mem_req) begin
            walker_mem_ready <= 1'b1;
            if(walker_mem_addr[31:16] == 16'b0)
                walker_mem_rdata <= pte_mem[walker_mem_addr[15:2]];
            else
                walker_mem_rdata <= 32'b0;
        end
    end
end

initial begin
    rst = 1'b1;
    csr_we = 1'b0;
    csr_addr = 12'b0;
    csr_wdata = 32'b0;
    sfence_vma = 1'b0;
    mstatus_sum = 1'b0;
    mstatus_mxr = 1'b0;
    privilege = PRIV_M;
    i_req_valid = 1'b0;
    i_vaddr = 32'b0;
    d_req_valid = 1'b0;
    d_vaddr = 32'b0;
    d_write = 1'b0;

    repeat(5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
    #1;

    privilege = PRIV_S;
    i_vaddr = 32'h1234_5678;
    i_req_valid = 1'b1;
    #1;
    check(i_translate_ready && !i_page_fault && i_paddr == 32'h1234_5678,
          "bare-mode translation bypasses the TLB");
    clear_i_req();

    set_pte(32'h0000_1000, make_pte(22'd2, PTE_V));
    set_pte(32'h0000_1004, make_pte(22'h000800, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D));
    set_pte(32'h0000_1008, make_pte(22'h000801, PTE_V | PTE_R | PTE_X | PTE_A | PTE_D));
    set_pte(32'h0000_2000, make_pte(22'd3, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D));
    set_pte(32'h0000_2004, make_pte(22'd4, PTE_V | PTE_R | PTE_W | PTE_A | PTE_D));
    set_pte(32'h0000_2008, make_pte(22'd5, PTE_V | PTE_X | PTE_A | PTE_D));
    set_pte(32'h0000_200c, make_pte(22'd6, PTE_V | PTE_R | PTE_W | PTE_X | PTE_U | PTE_A | PTE_D));
    set_pte(32'h0000_2010, make_pte(22'd9, PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D));
    set_pte(32'h0000_2014, make_pte(22'd10, PTE_V | PTE_R | PTE_W | PTE_A | PTE_D));
    set_pte(32'h0000_2018, make_pte(22'd11, PTE_V | PTE_R | PTE_W | PTE_D));
    set_pte(32'h0000_201c, make_pte(22'd12, PTE_V | PTE_R | PTE_W | PTE_A));

    write_satp(SATP_SV32_ROOT1);
    csr_addr = 12'h180;
    #1;
    check(csr_rdata == SATP_SV32_ROOT1, "satp CSR stores the Sv32 root PPN");

    privilege = PRIV_S;
    i_vaddr = 32'h0000_0000;
    i_req_valid = 1'b1;
    wait_i_ready(32, "instruction miss walks L1/L0 page tables");
    check(!i_page_fault, "instruction page walk succeeds");
    check(i_paddr == 32'h0000_3000, "instruction TLB fill maps VA 0x0 to PA 0x3000");
    check(i_miss_count == 32'd1, "instruction miss counter increments on walker start");
    clear_i_req();

    i_vaddr = 32'h0000_0004;
    i_req_valid = 1'b1;
    #1;
    check(i_translate_ready && !i_page_fault && i_paddr == 32'h0000_3004,
          "instruction TLB hit reuses the filled entry");
    check(i_miss_count == 32'd1, "instruction TLB hit does not start another walk");
    clear_i_req();

    d_vaddr = 32'h0000_1004;
    d_write = 1'b0;
    d_req_valid = 1'b1;
    wait_d_ready(32, "data load miss walks the page tables");
    check(!d_page_fault, "data load page walk succeeds");
    check(d_paddr == 32'h0000_4004, "data TLB fill maps VA 0x1004 to PA 0x4004");
    check(d_miss_count == 32'd1, "data miss counter increments on walker start");

    d_write = 1'b1;
    #1;
    check(d_translate_ready && !d_page_fault && d_paddr == 32'h0000_4004,
          "data store permission is preserved in the filled TLB entry");
    clear_d_req();

    set_pte(32'h0000_2000, make_pte(22'd7, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D));
    write_satp(SATP_SV32_ROOT1);

    i_vaddr = 32'h0000_0000;
    i_req_valid = 1'b1;
    wait_i_ready(32, "satp write flushes stale TLB entries before refilling");
    check(!i_page_fault, "instruction refill after satp flush succeeds");
    check(i_paddr == 32'h0000_7000, "updated page table changes the refilled PPN");
    check(i_miss_count == 32'd2, "refill after flush starts a second instruction walk");
    clear_i_req();

    set_pte(32'h0000_2000, make_pte(22'd8, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D));
    pulse_sfence_vma();

    i_vaddr = 32'h0000_0000;
    i_req_valid = 1'b1;
    wait_i_ready(32, "sfence.vma flushes stale TLB entries before refilling");
    check(!i_page_fault, "instruction refill after sfence.vma succeeds");
    check(i_paddr == 32'h0000_8000, "sfence.vma exposes the updated PPN without rewriting satp");
    check(i_miss_count == 32'd3, "refill after sfence.vma starts another instruction walk");
    clear_i_req();

    i_vaddr = 32'h0040_1234;
    i_req_valid = 1'b1;
    wait_i_ready(32, "instruction miss accepts an aligned L1 leaf superpage");
    check(!i_page_fault, "aligned Sv32 superpage instruction walk succeeds");
    check(i_paddr == 32'h0080_1234, "superpage maps VA 0x00401234 to PA 0x00801234");
    check(i_miss_count == 32'd4, "superpage miss counter increments on walker start");
    clear_i_req();

    i_vaddr = 32'h0040_5678;
    i_req_valid = 1'b1;
    #1;
    check(i_translate_ready && !i_page_fault && i_paddr == 32'h0080_5678,
          "instruction TLB hit reuses the Sv32 superpage entry");
    check(i_miss_count == 32'd4, "superpage TLB hit does not start another walk");
    clear_i_req();

    d_vaddr = 32'h0040_2004;
    d_write = 1'b1;
    d_req_valid = 1'b1;
    #1;
    check(d_translate_ready && !d_page_fault && d_paddr == 32'h0080_2004,
          "data TLB hit uses the Sv32 superpage entry");
    clear_d_req();

    i_vaddr = 32'h0080_0000;
    i_req_valid = 1'b1;
    wait_i_ready(32, "misaligned L1 leaf superpage returns a page fault");
    check(i_page_fault, "Sv32 superpage faults when PPN[0] is not aligned");
    clear_i_req();

    i_vaddr = 32'h0000_5000;
    i_req_valid = 1'b1;
    wait_i_ready(32, "instruction no-execute PTE returns a page fault");
    check(i_page_fault, "instruction access faults when X is clear");
    clear_i_req();

    privilege = PRIV_S;
    i_vaddr = 32'h0000_3000;
    i_req_valid = 1'b1;
    wait_i_ready(32, "supervisor access to U page returns a page fault");
    check(i_page_fault, "supervisor instruction access rejects U pages");
    clear_i_req();

    privilege = PRIV_U;
    i_vaddr = 32'h0000_3000;
    i_req_valid = 1'b1;
    wait_i_ready(32, "user access to U page walks and fills the TLB");
    check(!i_page_fault, "user instruction access accepts U pages");
    check(i_paddr == 32'h0000_6000, "user page maps VA 0x3000 to PA 0x6000");
    clear_i_req();

    privilege = PRIV_S;
    pulse_sfence_vma();
    d_vaddr = 32'h0000_3000;
    d_write = 1'b0;
    d_req_valid = 1'b1;
    wait_d_ready(32, "supervisor data access to U page without SUM returns a page fault");
    check(d_page_fault, "SUM=0 rejects supervisor data access to U pages");
    clear_d_req();

    mstatus_sum = 1'b1;
    d_vaddr = 32'h0000_4000;
    d_write = 1'b0;
    d_req_valid = 1'b1;
    wait_d_ready(32, "SUM allows supervisor data access to a U page");
    check(!d_page_fault, "SUM=1 accepts supervisor data access to U pages");
    check(d_paddr == 32'h0000_9000, "SUM-enabled user data page maps to PA 0x9000");
    clear_d_req();
    mstatus_sum = 1'b0;

    privilege = PRIV_S;
    d_vaddr = 32'h0000_2000;
    d_write = 1'b0;
    d_req_valid = 1'b1;
    wait_d_ready(32, "load from X-only page without MXR returns a page fault");
    check(d_page_fault, "MXR=0 rejects loads from execute-only pages");
    clear_d_req();

    mstatus_mxr = 1'b1;
    pulse_sfence_vma();
    d_vaddr = 32'h0000_2000;
    d_write = 1'b0;
    d_req_valid = 1'b1;
    wait_d_ready(32, "MXR allows load from an execute-only page");
    check(!d_page_fault, "MXR=1 accepts load from execute-only pages");
    check(d_paddr == 32'h0000_5000, "MXR-enabled execute-only page maps to PA 0x5000");
    clear_d_req();
    mstatus_mxr = 1'b0;

    privilege = PRIV_S;
    d_vaddr = 32'h0000_4000;
    d_write = 1'b0;
    d_req_valid = 1'b1;
    wait_d_ready(32, "invalid data PTE returns a page fault");
    check(d_page_fault, "data access faults on an invalid PTE");
    clear_d_req();

    d_vaddr = 32'h0000_6000;
    d_write = 1'b0;
    d_req_valid = 1'b1;
    wait_d_ready(32, "PTE with A=0 returns a page fault");
    check(d_page_fault, "software-managed Accessed bit faults when A=0");
    clear_d_req();

    d_vaddr = 32'h0000_7000;
    d_write = 1'b1;
    d_req_valid = 1'b1;
    wait_d_ready(32, "store to PTE with D=0 returns a page fault");
    check(d_page_fault, "software-managed Dirty bit faults when D=0 on store");
    clear_d_req();

    $display("MMU WALKER PASS");
    $finish;
end

endmodule
