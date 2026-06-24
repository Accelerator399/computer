module plic #(
    parameter BASE_ADDR = 32'h1003_0000,
    parameter NUM_SOURCES = 2
)(
    input clk,
    input rst,

    input [NUM_SOURCES-1:0] irq_sources,

    input [31:0] addr,
    input [31:0] wdata,
    input [3:0] wstrb,
    input we,
    output reg [31:0] rdata,

    output irq_out
);

localparam PRIORITY_BASE = 32'h0000_0000;
localparam PENDING_OFF   = 32'h0000_1000;
localparam ENABLE0_OFF   = 32'h0000_2000;
localparam THRESHOLD_OFF = 32'h0020_0000;
localparam CLAIM_OFF     = 32'h0020_0004;

reg [31:0] src_prio [0:NUM_SOURCES-1];
reg [NUM_SOURCES-1:0] pending;
reg [NUM_SOURCES-1:0] enable;
reg [31:0] threshold0;

wire [31:0] offset = addr - BASE_ADDR;
reg [31:0] claim_id;
reg [31:0] best_priority;
reg [31:0] pending_word;
reg [31:0] enable_word;
reg [NUM_SOURCES-1:0] pending_next;
integer pending_idx;
integer claim_idx;
integer rdata_idx;
integer seq_idx;

function [31:0] write_masked;
    input [31:0] old_value;
    input [31:0] new_value;
    input [3:0] byte_en;
    begin
        write_masked[7:0]   = byte_en[0] ? new_value[7:0]   : old_value[7:0];
        write_masked[15:8]  = byte_en[1] ? new_value[15:8]  : old_value[15:8];
        write_masked[23:16] = byte_en[2] ? new_value[23:16] : old_value[23:16];
        write_masked[31:24] = byte_en[3] ? new_value[31:24] : old_value[31:24];
    end
endfunction

wire [31:0] enable_word_next = write_masked(enable_word, wdata, wstrb);

always @(*) begin
    pending_word = 32'b0;
    enable_word = 32'b0;
    for(pending_idx = 0; pending_idx < NUM_SOURCES; pending_idx = pending_idx + 1) begin
        pending_word[pending_idx + 1] = pending[pending_idx];
        enable_word[pending_idx + 1] = enable[pending_idx];
    end
end

always @(*) begin
    claim_id = 32'b0;
    best_priority = threshold0;
    for(claim_idx = 0; claim_idx < NUM_SOURCES; claim_idx = claim_idx + 1) begin
        if(pending[claim_idx] && enable[claim_idx] && (src_prio[claim_idx] > best_priority)) begin
            best_priority = src_prio[claim_idx];
            claim_id = claim_idx + 1;
        end
    end
end

always @(*) begin
    rdata = 32'b0;
    for(rdata_idx = 0; rdata_idx < NUM_SOURCES; rdata_idx = rdata_idx + 1) begin
        if(offset == (PRIORITY_BASE + ((rdata_idx + 1) * 32'd4)))
            rdata = src_prio[rdata_idx];
    end

    if(offset == PENDING_OFF)
        rdata = pending_word;
    else if(offset == ENABLE0_OFF)
        rdata = enable_word;
    else if(offset == THRESHOLD_OFF)
        rdata = threshold0;
    else if(offset == CLAIM_OFF)
        rdata = claim_id;
end

always @(posedge clk) begin
    if(rst) begin
        for(seq_idx = 0; seq_idx < NUM_SOURCES; seq_idx = seq_idx + 1) begin
            src_prio[seq_idx] <= 32'b0;
            pending[seq_idx] <= 1'b0;
            enable[seq_idx] <= 1'b0;
        end
        threshold0 <= 32'b0;
    end else begin
        pending_next = pending | irq_sources;

        if(we && offset == CLAIM_OFF) begin
            for(seq_idx = 0; seq_idx < NUM_SOURCES; seq_idx = seq_idx + 1) begin
                if(wdata == (seq_idx + 1))
                    pending_next[seq_idx] = 1'b0;
            end
        end

        pending <= pending_next;

        if(we) begin
            for(seq_idx = 0; seq_idx < NUM_SOURCES; seq_idx = seq_idx + 1) begin
                if(offset == (PRIORITY_BASE + ((seq_idx + 1) * 32'd4)))
                    src_prio[seq_idx] <= write_masked(src_prio[seq_idx], wdata, wstrb);
                if(offset == ENABLE0_OFF)
                    enable[seq_idx] <= enable_word_next[seq_idx + 1];
            end

            if(offset == THRESHOLD_OFF)
                threshold0 <= write_masked(threshold0, wdata, wstrb);
        end
    end
end

assign irq_out = claim_id != 32'b0;

endmodule
