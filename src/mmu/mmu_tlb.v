`timescale 1ns/1ps

// Fillable fully-associative Sv32 TLB.
// Entries are cleared on reset/flush and populated by the MMU page-table walker.

module mmu_tlb #(
    parameter TLB_ENTRIES = 32
)(
    input clk,
    input rst,
    input flush,

    input [1:0] privilege,       // 00=U, 01=S, 11=M
    input mstatus_sum,
    input mstatus_mxr,

    input i_req_valid,
    input [31:0] i_vaddr,
    output reg [33:0] i_paddr,
    output reg i_hit,
    output reg i_miss,
    output reg i_page_fault,

    input d_req_valid,
    input [31:0] d_vaddr,
    input d_write,
    output reg [33:0] d_paddr,
    output reg d_hit,
    output reg d_miss,
    output reg d_page_fault,

    input fill_valid,
    input [19:0] fill_vpn,
    input [21:0] fill_ppn,
    input fill_superpage,
    input fill_r,
    input fill_w,
    input fill_x,
    input fill_u
);

reg        tlb_valid [TLB_ENTRIES-1:0];
reg [19:0] tlb_vpn   [TLB_ENTRIES-1:0];
reg [21:0] tlb_ppn   [TLB_ENTRIES-1:0];
reg        tlb_superpage [TLB_ENTRIES-1:0];
reg        tlb_r     [TLB_ENTRIES-1:0];
reg        tlb_w     [TLB_ENTRIES-1:0];
reg        tlb_x     [TLB_ENTRIES-1:0];
reg        tlb_u     [TLB_ENTRIES-1:0];

reg [4:0] replace_ptr;

wire [19:0] i_vpn = i_vaddr[31:12];
wire [11:0] i_offset = i_vaddr[11:0];
wire [19:0] d_vpn = d_vaddr[31:12];
wire [11:0] d_offset = d_vaddr[11:0];

wire [TLB_ENTRIES-1:0] i_match;
wire [TLB_ENTRIES-1:0] d_match;
wire [TLB_ENTRIES-1:0] fill_match;

genvar k;
generate
    for(k=0; k<TLB_ENTRIES; k=k+1) begin: gen_match
        assign i_match[k] = tlb_valid[k] &&
                            (tlb_superpage[k] ? (tlb_vpn[k][19:10] == i_vpn[19:10]) :
                                                (tlb_vpn[k] == i_vpn));
        assign d_match[k] = tlb_valid[k] &&
                            (tlb_superpage[k] ? (tlb_vpn[k][19:10] == d_vpn[19:10]) :
                                                (tlb_vpn[k] == d_vpn));
        assign fill_match[k] = tlb_valid[k] && (tlb_superpage[k] == fill_superpage) &&
                               (fill_superpage ? (tlb_vpn[k][19:10] == fill_vpn[19:10]) :
                                                 (tlb_vpn[k] == fill_vpn));
    end
endgenerate

wire i_is_hit = |i_match;
wire d_is_hit = |d_match;
wire fill_is_update = |fill_match;

reg [4:0] i_hit_idx;
reg [4:0] d_hit_idx;
reg [4:0] fill_idx;

integer m;
always @(*) begin
    i_hit_idx = 5'd0;
    d_hit_idx = 5'd0;
    fill_idx = replace_ptr;

    for(m=0; m<TLB_ENTRIES; m=m+1) begin
        if(i_match[m])
            i_hit_idx = m[4:0];
        if(d_match[m])
            d_hit_idx = m[4:0];
        if(fill_match[m])
            fill_idx = m[4:0];
    end
end

wire i_priv_ok = (privilege == 2'b00) ? tlb_u[i_hit_idx] : !tlb_u[i_hit_idx];
wire d_priv_ok = (privilege == 2'b00) ? tlb_u[d_hit_idx] :
                 (tlb_u[d_hit_idx] ? mstatus_sum : 1'b1);
wire d_read_ok = tlb_r[d_hit_idx] || (mstatus_mxr && tlb_x[d_hit_idx]);

always @(*) begin
    if(i_req_valid && i_is_hit) begin
        i_paddr = tlb_superpage[i_hit_idx] ?
                  {tlb_ppn[i_hit_idx][21:10], i_vaddr[21:0]} :
                  {tlb_ppn[i_hit_idx], i_offset};
        i_hit = 1'b1;
        i_miss = 1'b0;
        i_page_fault = !tlb_x[i_hit_idx] || !i_priv_ok;
    end else if(i_req_valid) begin
        i_paddr = 34'b0;
        i_hit = 1'b0;
        i_miss = 1'b1;
        i_page_fault = 1'b0;
    end else begin
        i_paddr = 34'b0;
        i_hit = 1'b0;
        i_miss = 1'b0;
        i_page_fault = 1'b0;
    end

    if(d_req_valid && d_is_hit) begin
        d_paddr = tlb_superpage[d_hit_idx] ?
                  {tlb_ppn[d_hit_idx][21:10], d_vaddr[21:0]} :
                  {tlb_ppn[d_hit_idx], d_offset};
        d_hit = 1'b1;
        d_miss = 1'b0;
        d_page_fault = !d_priv_ok || (d_write ? !tlb_w[d_hit_idx] : !d_read_ok);
    end else if(d_req_valid) begin
        d_paddr = 34'b0;
        d_hit = 1'b0;
        d_miss = 1'b1;
        d_page_fault = 1'b0;
    end else begin
        d_paddr = 34'b0;
        d_hit = 1'b0;
        d_miss = 1'b0;
        d_page_fault = 1'b0;
    end
end

integer i;
always @(posedge clk) begin
    if(rst || flush) begin
        for(i=0; i<TLB_ENTRIES; i=i+1) begin
            tlb_valid[i] <= 1'b0;
            tlb_vpn[i] <= 20'b0;
            tlb_ppn[i] <= 22'b0;
            tlb_superpage[i] <= 1'b0;
            tlb_r[i] <= 1'b0;
            tlb_w[i] <= 1'b0;
            tlb_x[i] <= 1'b0;
            tlb_u[i] <= 1'b0;
        end
        replace_ptr <= 5'd0;
    end else if(fill_valid) begin
        tlb_valid[fill_idx] <= 1'b1;
        tlb_vpn[fill_idx] <= fill_vpn;
        tlb_ppn[fill_idx] <= fill_ppn;
        tlb_superpage[fill_idx] <= fill_superpage;
        tlb_r[fill_idx] <= fill_r;
        tlb_w[fill_idx] <= fill_w;
        tlb_x[fill_idx] <= fill_x;
        tlb_u[fill_idx] <= fill_u;

        if(!fill_is_update) begin
            if(replace_ptr == TLB_ENTRIES-1)
                replace_ptr <= 5'd0;
            else
                replace_ptr <= replace_ptr + 5'd1;
        end
    end
end

endmodule
