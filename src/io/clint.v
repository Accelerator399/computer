module clint #(
    parameter BASE_ADDR = 32'h1000_0000
)(
    input clk,
    input rst,

    input [31:0] addr,
    input [31:0] wdata,
    input [3:0] wstrb,
    input we,
    output [31:0] rdata,

    output timer_int,
    output soft_int
);

localparam MSIP_OFF      = 32'h0000_0000;
localparam MTIMECMP_LO   = 32'h0000_4000;
localparam MTIMECMP_HI   = 32'h0000_4004;
localparam MTIME_LO      = 32'h0000_bff8;
localparam MTIME_HI      = 32'h0000_bffc;

reg [31:0] msip;
reg [63:0] mtimecmp;
reg [63:0] mtime;

wire [31:0] offset = addr - BASE_ADDR;

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

always @(posedge clk) begin
    if(rst) begin
        msip <= 32'b0;
        mtimecmp <= 64'hffff_ffff_ffff_ffff;
        mtime <= 64'b0;
    end else begin
        mtime <= mtime + 64'd1;

        if(we) begin
            case(offset)
                MSIP_OFF: begin
                    msip <= write_masked(msip, wdata, wstrb) & 32'h0000_0001;
                end
                MTIMECMP_LO: begin
                    mtimecmp[31:0] <= write_masked(mtimecmp[31:0], wdata, wstrb);
                end
                MTIMECMP_HI: begin
                    mtimecmp[63:32] <= write_masked(mtimecmp[63:32], wdata, wstrb);
                end
                MTIME_LO: begin
                    mtime[31:0] <= write_masked(mtime[31:0], wdata, wstrb);
                end
                MTIME_HI: begin
                    mtime[63:32] <= write_masked(mtime[63:32], wdata, wstrb);
                end
            endcase
        end
    end
end

assign rdata = (offset == MSIP_OFF)    ? msip :
               (offset == MTIMECMP_LO) ? mtimecmp[31:0] :
               (offset == MTIMECMP_HI) ? mtimecmp[63:32] :
               (offset == MTIME_LO)    ? mtime[31:0] :
               (offset == MTIME_HI)    ? mtime[63:32] :
                                          32'b0;

assign timer_int = (mtime >= mtimecmp);
assign soft_int = msip[0];

endmodule
