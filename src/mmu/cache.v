// cache.v
// 2-way set-associative cache with LRU replacement
// Write-Through policy (write to cache and memory simultaneously)
//
// 参数：
//   - 16 组（sets）× 2 路（ways）
//   - 每行 16 字节（128 位，匹配 DDR 数据宽度）
//   - 物理地址 32 位：{tag[27:8], index[7:4], offset[3:0]}
//
// 特性：
//   - Read: Cache Hit → 立即返回，Miss → 从 DDR 读取 + 填充
//   - Write: Write-Through，同时写 Cache 和 DDR

module cache #(
    parameter SETS = 16,           // 组数（2^4）
    parameter WAYS = 2,            // 路数
    parameter LINE_SIZE = 16,      // 缓存行大小（字节）
    parameter ADDR_WIDTH = 32,     // 物理地址位宽
    parameter DATA_WIDTH = 32      // CPU 数据位宽
)(
    input clk,
    input rst,
    input flush,

    // CPU 侧接口（连接 MMU 输出的物理地址）
    input                        cpu_req,       // 请求有效
    input                        cpu_we,        // 写使能（1=写，0=读）
    input  [ADDR_WIDTH-1:0]      cpu_addr,      // 物理地址
    input  [DATA_WIDTH-1:0]      cpu_wdata,     // 写数据
    input  [DATA_WIDTH/8-1:0]    cpu_wstrb,     // 写字节使能
    output reg [DATA_WIDTH-1:0]  cpu_rdata,     // 读数据
    output reg                   cpu_ready,     // 数据就绪

    // Memory（DDR）侧接口
    output reg                   mem_req,       // 内存请求
    output reg                   mem_we,        // 内存写使能
    output reg [ADDR_WIDTH-1:0]  mem_addr,      // 内存地址
    output reg [127:0]           mem_wdata,     // 内存写数据（128位整行）
    output reg [15:0]            mem_wstrb,     // 内存写字节使能
    input  [127:0]               mem_rdata,     // 内存读数据
    input                        mem_ready      // 内存就绪
);

// ============================================
// 地址拆分
// ============================================
// 物理地址 32 位：{tag[27:8], index[7:4], offset[3:0]}
localparam INDEX_BITS = 4;   // 16 组需要 4 位索引
localparam OFFSET_BITS = 4;  // 16 字节需要 4 位偏移
localparam TAG_BITS = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;

wire [TAG_BITS-1:0]    tag    = cpu_addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];
wire [INDEX_BITS-1:0]  index  = cpu_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
wire [OFFSET_BITS-1:0] offset = cpu_addr[OFFSET_BITS-1:0];

// 字偏移（在 128 位缓存行内的 32 位字位置）
wire [1:0] word_offset = offset[3:2];  // offset[3:2] 决定 4 个 32 位字中的哪一个

// ============================================
// Cache 存储结构
// ============================================
// 每组 2 路，每路包含：valid, tag, data[127:0]
reg                 valid [SETS-1:0][WAYS-1:0];
reg [TAG_BITS-1:0]  tag_mem [SETS-1:0][WAYS-1:0];
reg [127:0]         data_mem [SETS-1:0][WAYS-1:0];
reg                 lru [SETS-1:0];  // LRU 位：0=Way0 最近，1=Way1 最近

// ============================================
// 状态机
// ============================================
localparam IDLE        = 3'd0;
localparam COMPARE     = 3'd1;
localparam ALLOCATE    = 3'd2;
localparam WRITE_MEM   = 3'd3;

reg [2:0] state, next_state;

// 当前请求信息寄存
reg                      req_we;
reg [ADDR_WIDTH-1:0]     req_addr;
reg [DATA_WIDTH-1:0]     req_wdata;
reg [DATA_WIDTH/8-1:0]   req_wstrb;
reg [TAG_BITS-1:0]       req_tag;
reg [INDEX_BITS-1:0]     req_index;
reg [1:0]                req_word_offset;

// 命中判断
wire hit_way0 = valid[req_index][0] && (tag_mem[req_index][0] == req_tag);
wire hit_way1 = valid[req_index][1] && (tag_mem[req_index][1] == req_tag);
wire cache_hit = hit_way0 || hit_way1;
wire hit_way = hit_way1;  // 0=Way0 命中，1=Way1 命中

// 替换路选择（LRU）
wire replace_way = lru[req_index];  // LRU 位指示替换哪一路

// ============================================
// 状态机转移
// ============================================
always @(posedge clk) begin
    if (rst)
        state <= IDLE;
    else
        state <= next_state;
end

always @(*) begin
    next_state = state;
    case (state)
        IDLE: begin
            if (cpu_req)
                next_state = COMPARE;
        end

        COMPARE: begin
            if (cache_hit) begin
                if (req_we)
                    next_state = WRITE_MEM;  // Write-Through: 写内存
                else
                    next_state = IDLE;       // 读命中：直接返回
            end else begin
                next_state = req_we ? WRITE_MEM : ALLOCATE;
            end
        end

        ALLOCATE: begin
            if (mem_ready)
                next_state = IDLE;
        end

        WRITE_MEM: begin
            if (mem_ready)
                next_state = IDLE;
        end

        default: next_state = IDLE;
    endcase
end

// ============================================
// 状态机输出逻辑
// ============================================
integer i, j;

always @(posedge clk) begin
    if (rst || flush) begin
        cpu_ready <= 0;
        cpu_rdata <= 0;
        mem_req <= 0;
        mem_we <= 0;
        mem_addr <= 0;
        mem_wdata <= 0;
        mem_wstrb <= 0;
        req_we <= 0;
        req_addr <= 0;
        req_wdata <= 0;
        req_wstrb <= 0;
        req_tag <= 0;
        req_index <= 0;
        req_word_offset <= 0;

        // 初始化 Cache
        for (i = 0; i < SETS; i = i + 1) begin
            lru[i] <= 0;
            for (j = 0; j < WAYS; j = j + 1) begin
                valid[i][j] <= 0;
                tag_mem[i][j] <= 0;
                data_mem[i][j] <= 0;
            end
        end
    end else begin
        // 默认值
        cpu_ready <= 0;
        mem_req <= 0;

        case (state)
            IDLE: begin
                if (cpu_req) begin
                    // 锁存请求信息
                    req_we <= cpu_we;
                    req_addr <= cpu_addr;
                    req_wdata <= cpu_wdata;
                    req_wstrb <= cpu_wstrb;
                    req_tag <= tag;
                    req_index <= index;
                    req_word_offset <= word_offset;
                end
            end

            COMPARE: begin
                if (cache_hit) begin
                    if (req_we) begin
                        // 写命中：更新 Cache
                        if (hit_way0) begin
                            case (req_word_offset)
                                2'd0: begin
                                    if (req_wstrb[0]) data_mem[req_index][0][7:0]   <= req_wdata[7:0];
                                    if (req_wstrb[1]) data_mem[req_index][0][15:8]  <= req_wdata[15:8];
                                    if (req_wstrb[2]) data_mem[req_index][0][23:16] <= req_wdata[23:16];
                                    if (req_wstrb[3]) data_mem[req_index][0][31:24] <= req_wdata[31:24];
                                end
                                2'd1: begin
                                    if (req_wstrb[0]) data_mem[req_index][0][39:32]  <= req_wdata[7:0];
                                    if (req_wstrb[1]) data_mem[req_index][0][47:40]  <= req_wdata[15:8];
                                    if (req_wstrb[2]) data_mem[req_index][0][55:48]  <= req_wdata[23:16];
                                    if (req_wstrb[3]) data_mem[req_index][0][63:56]  <= req_wdata[31:24];
                                end
                                2'd2: begin
                                    if (req_wstrb[0]) data_mem[req_index][0][71:64]  <= req_wdata[7:0];
                                    if (req_wstrb[1]) data_mem[req_index][0][79:72]  <= req_wdata[15:8];
                                    if (req_wstrb[2]) data_mem[req_index][0][87:80]  <= req_wdata[23:16];
                                    if (req_wstrb[3]) data_mem[req_index][0][95:88]  <= req_wdata[31:24];
                                end
                                2'd3: begin
                                    if (req_wstrb[0]) data_mem[req_index][0][103:96]  <= req_wdata[7:0];
                                    if (req_wstrb[1]) data_mem[req_index][0][111:104] <= req_wdata[15:8];
                                    if (req_wstrb[2]) data_mem[req_index][0][119:112] <= req_wdata[23:16];
                                    if (req_wstrb[3]) data_mem[req_index][0][127:120] <= req_wdata[31:24];
                                end
                            endcase
                            lru[req_index] <= 1;  // Way0 命中，Way1 变成 LRU
                        end else begin  // hit_way1
                            case (req_word_offset)
                                2'd0: begin
                                    if (req_wstrb[0]) data_mem[req_index][1][7:0]   <= req_wdata[7:0];
                                    if (req_wstrb[1]) data_mem[req_index][1][15:8]  <= req_wdata[15:8];
                                    if (req_wstrb[2]) data_mem[req_index][1][23:16] <= req_wdata[23:16];
                                    if (req_wstrb[3]) data_mem[req_index][1][31:24] <= req_wdata[31:24];
                                end
                                2'd1: begin
                                    if (req_wstrb[0]) data_mem[req_index][1][39:32]  <= req_wdata[7:0];
                                    if (req_wstrb[1]) data_mem[req_index][1][47:40]  <= req_wdata[15:8];
                                    if (req_wstrb[2]) data_mem[req_index][1][55:48]  <= req_wdata[23:16];
                                    if (req_wstrb[3]) data_mem[req_index][1][63:56]  <= req_wdata[31:24];
                                end
                                2'd2: begin
                                    if (req_wstrb[0]) data_mem[req_index][1][71:64]  <= req_wdata[7:0];
                                    if (req_wstrb[1]) data_mem[req_index][1][79:72]  <= req_wdata[15:8];
                                    if (req_wstrb[2]) data_mem[req_index][1][87:80]  <= req_wdata[23:16];
                                    if (req_wstrb[3]) data_mem[req_index][1][95:88]  <= req_wdata[31:24];
                                end
                                2'd3: begin
                                    if (req_wstrb[0]) data_mem[req_index][1][103:96]  <= req_wdata[7:0];
                                    if (req_wstrb[1]) data_mem[req_index][1][111:104] <= req_wdata[15:8];
                                    if (req_wstrb[2]) data_mem[req_index][1][119:112] <= req_wdata[23:16];
                                    if (req_wstrb[3]) data_mem[req_index][1][127:120] <= req_wdata[31:24];
                                end
                            endcase
                            lru[req_index] <= 0;
                        end
                        // Write-Through：继续写内存
                    end else begin
                        // 读命中：返回数据
                        if (hit_way0) begin
                            case (req_word_offset)
                                2'd0: cpu_rdata <= data_mem[req_index][0][31:0];
                                2'd1: cpu_rdata <= data_mem[req_index][0][63:32];
                                2'd2: cpu_rdata <= data_mem[req_index][0][95:64];
                                2'd3: cpu_rdata <= data_mem[req_index][0][127:96];
                            endcase
                            lru[req_index] <= 1;  // Way0 命中，Way1 变成 LRU
                        end else begin
                            case (req_word_offset)
                                2'd0: cpu_rdata <= data_mem[req_index][1][31:0];
                                2'd1: cpu_rdata <= data_mem[req_index][1][63:32];
                                2'd2: cpu_rdata <= data_mem[req_index][1][95:64];
                                2'd3: cpu_rdata <= data_mem[req_index][1][127:96];
                            endcase
                            lru[req_index] <= 0;  // Way1 命中，Way0 变成 LRU
                        end
                        cpu_ready <= 1;
                    end
                end else begin
                    // 未命中：下个状态访问内存。读 miss 分配，写 miss 直接写穿。
                end
            end

            ALLOCATE: begin
                mem_req <= 1;
                mem_we <= 0;
                mem_addr <= {req_addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};

                if (mem_ready) begin
                    data_mem[req_index][replace_way] <= mem_rdata;
                    tag_mem[req_index][replace_way] <= req_tag;
                    valid[req_index][replace_way] <= 1;
                    lru[req_index] <= ~replace_way;  // 更新 LRU

                    case (req_word_offset)
                        2'd0: cpu_rdata <= mem_rdata[31:0];
                        2'd1: cpu_rdata <= mem_rdata[63:32];
                        2'd2: cpu_rdata <= mem_rdata[95:64];
                        2'd3: cpu_rdata <= mem_rdata[127:96];
                    endcase
                    cpu_ready <= 1;
                end
            end

            WRITE_MEM: begin
                mem_req <= 1;
                mem_we <= 1;
                mem_addr <= {req_addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
                mem_wdata <= {4{req_wdata}} << {req_word_offset, 5'b0};
                mem_wstrb <= {{12{1'b0}}, req_wstrb} << {req_word_offset, 2'b00};

                if (mem_ready) begin
                    cpu_ready <= 1;
                end
            end
        endcase
    end
end

endmodule
