module axi_lite_mmio_bridge #(
    parameter ADDR_WIDTH = 13
)(
    input clk,
    input rst,

    input req_valid,
    input req_write,
    input [ADDR_WIDTH-1:0] req_addr,
    input [31:0] req_wdata,
    input [3:0] req_wstrb,
    output req_ready,
    output reg [31:0] req_rdata,

    output reg [ADDR_WIDTH-1:0] m_axi_awaddr,
    output reg m_axi_awvalid,
    input m_axi_awready,
    output reg [31:0] m_axi_wdata,
    output reg [3:0] m_axi_wstrb,
    output reg m_axi_wvalid,
    input m_axi_wready,
    input [1:0] m_axi_bresp,
    input m_axi_bvalid,
    output m_axi_bready,

    output reg [ADDR_WIDTH-1:0] m_axi_araddr,
    output reg m_axi_arvalid,
    input m_axi_arready,
    input [31:0] m_axi_rdata,
    input [1:0] m_axi_rresp,
    input m_axi_rvalid,
    output m_axi_rready
);

localparam S_IDLE       = 3'd0;
localparam S_WRITE      = 3'd1;
localparam S_WRITE_RESP = 3'd2;
localparam S_READ_ADDR  = 3'd3;
localparam S_READ_DATA  = 3'd4;
localparam S_DONE       = 3'd5;
localparam S_RELEASE    = 3'd6;

reg [2:0] state;

assign req_ready = state == S_DONE;
assign m_axi_bready = 1'b1;
assign m_axi_rready = 1'b1;

wire unused_resp = ^m_axi_bresp ^ ^m_axi_rresp;

always @(posedge clk) begin
    if(rst) begin
        state <= S_IDLE;
        req_rdata <= 32'b0;
        m_axi_awaddr <= {ADDR_WIDTH{1'b0}};
        m_axi_awvalid <= 1'b0;
        m_axi_wdata <= 32'b0;
        m_axi_wstrb <= 4'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_araddr <= {ADDR_WIDTH{1'b0}};
        m_axi_arvalid <= 1'b0;
    end else begin
        case(state)
            S_IDLE: begin
                if(req_valid && req_write) begin
                    m_axi_awaddr <= req_addr;
                    m_axi_awvalid <= 1'b1;
                    m_axi_wdata <= req_wdata;
                    m_axi_wstrb <= req_wstrb;
                    m_axi_wvalid <= 1'b1;
                    state <= S_WRITE;
                end else if(req_valid) begin
                    m_axi_araddr <= req_addr;
                    m_axi_arvalid <= 1'b1;
                    state <= S_READ_ADDR;
                end
            end

            S_WRITE: begin
                if(m_axi_awvalid && m_axi_awready)
                    m_axi_awvalid <= 1'b0;
                if(m_axi_wvalid && m_axi_wready)
                    m_axi_wvalid <= 1'b0;
                if((!m_axi_awvalid || m_axi_awready) &&
                   (!m_axi_wvalid || m_axi_wready))
                    state <= S_WRITE_RESP;
            end

            S_WRITE_RESP: begin
                if(m_axi_bvalid)
                    state <= S_DONE;
            end

            S_READ_ADDR: begin
                if(m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    state <= S_READ_DATA;
                end
            end

            S_READ_DATA: begin
                if(m_axi_rvalid) begin
                    req_rdata <= m_axi_rdata;
                    state <= S_DONE;
                end
            end

            S_DONE: begin
                state <= req_valid ? S_RELEASE : S_IDLE;
            end

            S_RELEASE: begin
                if(!req_valid)
                    state <= S_IDLE;
            end

            default: begin
                state <= S_IDLE;
            end
        endcase
    end
end

endmodule
