// mmu_ddr_adapter.v
// MMU 到 DDR/MIG 的适配模块
// 支持 ICache 和 DCache 的 128 位突发读写

module mmu_ddr_adapter #(
    parameter ADDR_WIDTH = 28,    // MIG 地址位宽
    parameter DATA_WIDTH = 128    // MIG 数据位宽
)(
    // 系统信号
    input clk,
    input rst,

    // ICache 接口
    input                      icache_req,
    input                      icache_we,       // ICache 通常只读
    input [31:0]               icache_addr,
    input [DATA_WIDTH-1:0]     icache_wdata,
    input [DATA_WIDTH/8-1:0]   icache_wstrb,
    output reg [DATA_WIDTH-1:0] icache_rdata,
    output reg                 icache_ready,

    // DCache 接口
    input                      dcache_req,
    input                      dcache_we,
    input [31:0]               dcache_addr,
    input [DATA_WIDTH-1:0]     dcache_wdata,
    input [DATA_WIDTH/8-1:0]   dcache_wstrb,
    output reg [DATA_WIDTH-1:0] dcache_rdata,
    output reg                 dcache_ready,

    // Page-table walker read interface
    input                      walker_req,
    input [31:0]               walker_addr,
    output reg [DATA_WIDTH-1:0] walker_rdata,
    output reg                 walker_ready,

    // MIG user interface
    input ui_clk_sync_rst,
    input init_calib_complete,

    output reg [ADDR_WIDTH-1:0] app_addr,
    output reg [2:0]            app_cmd,
    output reg                  app_en,
    output reg [DATA_WIDTH-1:0] app_wdf_data,
    output reg                  app_wdf_end,
    output reg                  app_wdf_wren,
    output reg [DATA_WIDTH/8-1:0] app_wdf_mask,
    input                       app_rdy,
    input                       app_wdf_rdy,
    input [DATA_WIDTH-1:0]      app_rd_data,
    input                       app_rd_data_end,
    input                       app_rd_data_valid
);

// MIG 命令
localparam CMD_WRITE = 3'b000;
localparam CMD_READ  = 3'b001;

// 状态机
localparam IDLE    = 3'd0;
localparam I_READ  = 3'd1;
localparam D_READ  = 3'd2;
localparam D_WRITE = 3'd3;
localparam WAIT_RD = 3'd4;
localparam W_READ  = 3'd5;

reg [2:0] state;

// 当前操作
reg [31:0] curr_addr;
reg [DATA_WIDTH-1:0] curr_wdata;
reg [DATA_WIDTH/8-1:0] curr_wstrb;
reg [1:0] curr_target;  // 0=ICache, 1=DCache, 2=Walker

// Round-robin 仲裁：last_served=1 表示上次服务 ICache，本次优先 DCache
reg last_served;

// The MMU walker issues short request pulses while MIG reads can be busy for
// many cycles.  Latch one outstanding walker read so a page walk is not lost
// behind an I-cache or D-cache transaction.
reg walker_pending;
reg [31:0] walker_pending_addr;
reg walker_req_d;
wire walker_req_rise = walker_req && !walker_req_d;
wire take_walker_direct = (state == IDLE) && init_calib_complete &&
                          !walker_pending && walker_req;
wire [31:0] next_walker_addr = walker_pending ? walker_pending_addr : walker_addr;

// Cache-side mem_req is level-style: it stays high until the cache observes
// ready.  After producing a ready pulse, wait for that level request to drop
// before accepting another transaction from the same cache.
reg icache_req_blocked;
reg dcache_req_blocked;
wire icache_req_allowed = icache_req && !icache_req_blocked;
wire dcache_req_allowed = dcache_req && !dcache_req_blocked;

// 输出逻辑和 MIG 握手
always @(posedge clk) begin
    if (rst || ui_clk_sync_rst) begin
        state <= IDLE;
        app_addr <= 0;
        app_cmd <= CMD_READ;
        app_en <= 0;
        app_wdf_data <= 0;
        app_wdf_end <= 0;
        app_wdf_wren <= 0;
        app_wdf_mask <= {DATA_WIDTH/8{1'b1}};
        icache_ready <= 0;
        dcache_ready <= 0;
        walker_ready <= 0;
        curr_addr <= 0;
        curr_wdata <= 0;
        curr_wstrb <= 0;
        curr_target <= 0;
        last_served <= 0;
        walker_pending <= 1'b0;
        walker_pending_addr <= 32'b0;
        walker_req_d <= 1'b0;
        icache_req_blocked <= 1'b0;
        dcache_req_blocked <= 1'b0;
    end else begin
        // 默认 ready 脉冲为低；MIG valid 信号在发送态保持到 ready。
        icache_ready <= 0;
        dcache_ready <= 0;
        walker_ready <= 0;
        walker_req_d <= walker_req;

        if(!icache_req)
            icache_req_blocked <= 1'b0;
        if(!dcache_req)
            dcache_req_blocked <= 1'b0;

        if (walker_req_rise && !take_walker_direct) begin
            walker_pending <= 1'b1;
            walker_pending_addr <= walker_addr;
        end

        case (state)
            IDLE: begin
                app_en <= 0;
                app_wdf_wren <= 0;
                app_wdf_end <= 0;
                if (init_calib_complete) begin
                    if (walker_pending || walker_req) begin
                        curr_addr <= next_walker_addr;
                        curr_target <= 2'd2;
                        app_addr <= {next_walker_addr[ADDR_WIDTH-1:4], 4'b0};
                        app_cmd <= CMD_READ;
                        app_en <= 1;
                        walker_pending <= 1'b0;
                        state <= W_READ;
                    end else
                    // 与状态转移逻辑保持一致的 round-robin 选择
                    if (last_served) begin
                        if (dcache_req_allowed) begin
                            curr_addr <= dcache_addr;
                            curr_wdata <= dcache_wdata;
                            curr_wstrb <= dcache_wstrb;
                            curr_target <= 2'd1;
                            app_addr <= dcache_addr[ADDR_WIDTH-1:0];
                            app_cmd <= dcache_we ? CMD_WRITE : CMD_READ;
                            if (dcache_we) begin
                                app_wdf_data <= dcache_wdata;
                                app_wdf_end <= 1;
                                app_wdf_wren <= 1;
                                app_wdf_mask <= ~dcache_wstrb;
                                app_en <= 1;
                                state <= D_WRITE;
                            end else begin
                                app_en <= 1;
                                state <= D_READ;
                            end
                        end else if (icache_req_allowed) begin
                            curr_addr <= icache_addr;
                            curr_target <= 2'd0;
                            app_addr <= icache_addr[ADDR_WIDTH-1:0];
                            app_cmd <= CMD_READ;
                            app_en <= 1;
                            state <= I_READ;
                        end
                    end else begin
                        if (icache_req_allowed) begin
                            curr_addr <= icache_addr;
                            curr_target <= 2'd0;
                            app_addr <= icache_addr[ADDR_WIDTH-1:0];
                            app_cmd <= CMD_READ;
                            app_en <= 1;
                            state <= I_READ;
                        end else if (dcache_req_allowed) begin
                            curr_addr <= dcache_addr;
                            curr_wdata <= dcache_wdata;
                            curr_wstrb <= dcache_wstrb;
                            curr_target <= 2'd1;
                            app_addr <= dcache_addr[ADDR_WIDTH-1:0];
                            app_cmd <= dcache_we ? CMD_WRITE : CMD_READ;
                            if (dcache_we) begin
                                app_wdf_data <= dcache_wdata;
                                app_wdf_end <= 1;
                                app_wdf_wren <= 1;
                                app_wdf_mask <= ~dcache_wstrb;
                                app_en <= 1;
                                state <= D_WRITE;
                            end else begin
                                app_en <= 1;
                                state <= D_READ;
                            end
                        end
                    end
                end
            end

            I_READ, D_READ, W_READ: begin
                // 保持读命令直到 MIG 接收一次。
                if (app_en && app_rdy) begin
                    app_en <= 0;
                    state <= WAIT_RD;
                end else begin
                    app_en <= 1;
                end
            end

            D_WRITE: begin
                // MIG 命令通道和写数据通道可独立 ready；各自只提交一次。
                if (app_en && app_rdy)
                    app_en <= 0;
                if (app_wdf_wren && app_wdf_rdy) begin
                    app_wdf_wren <= 0;
                    app_wdf_end <= 0;
                end

                if ((!app_en || app_rdy) && (!app_wdf_wren || app_wdf_rdy)) begin
                    state <= IDLE;
                    dcache_ready <= 1;
                    dcache_req_blocked <= 1'b1;
                    last_served <= 0;  // 写是 DCache 操作
                end
            end

            WAIT_RD: begin
                app_en <= 0;
                if (app_rd_data_valid && app_rd_data_end) begin
                    // 读数据返回
                    if (curr_target == 2'd0) begin
                        icache_rdata <= app_rd_data;
                        icache_ready <= 1;
                        icache_req_blocked <= 1'b1;
                        last_served <= 1;  // 本次服务了 ICache
                        state <= IDLE;
                    end else if (curr_target == 2'd1) begin
                        dcache_rdata <= app_rd_data;
                        dcache_ready <= 1;
                        dcache_req_blocked <= 1'b1;
                        last_served <= 0;  // 本次服务了 DCache
                        state <= IDLE;
                    end else begin
                        walker_rdata <= app_rd_data;
                        walker_ready <= 1;
                        state <= IDLE;
                    end
                end
            end

            default: begin
                state <= IDLE;
            end
        endcase
    end
end

endmodule
