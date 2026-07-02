module mig_app_cdc_bridge #(
    parameter ADDR_WIDTH = 27,
    parameter DATA_WIDTH = 128
)(
    input cpu_clk,
    input cpu_rst,

    input [ADDR_WIDTH-1:0] cpu_app_addr,
    input [2:0] cpu_app_cmd,
    input cpu_app_en,
    input [DATA_WIDTH-1:0] cpu_app_wdf_data,
    input cpu_app_wdf_end,
    input cpu_app_wdf_wren,
    input [DATA_WIDTH/8-1:0] cpu_app_wdf_mask,
    output cpu_app_rdy,
    output cpu_app_wdf_rdy,
    output reg [DATA_WIDTH-1:0] cpu_app_rd_data,
    output reg cpu_app_rd_data_end,
    output reg cpu_app_rd_data_valid,

    input mig_clk,
    input mig_rst,

    output reg [ADDR_WIDTH-1:0] mig_app_addr,
    output reg [2:0] mig_app_cmd,
    output reg mig_app_en,
    output reg [DATA_WIDTH-1:0] mig_app_wdf_data,
    output reg mig_app_wdf_end,
    output reg mig_app_wdf_wren,
    output reg [DATA_WIDTH/8-1:0] mig_app_wdf_mask,
    input mig_app_rdy,
    input mig_app_wdf_rdy,
    input [DATA_WIDTH-1:0] mig_app_rd_data,
    input mig_app_rd_data_end,
    input mig_app_rd_data_valid
);

localparam CMD_WRITE = 3'b000;

reg [ADDR_WIDTH-1:0] req_addr_cpu;
reg [2:0] req_cmd_cpu;
reg [DATA_WIDTH-1:0] req_wdf_data_cpu;
reg [DATA_WIDTH/8-1:0] req_wdf_mask_cpu;
reg req_is_write_cpu;
reg req_toggle_cpu;
reg cpu_busy;

reg complete_toggle_mig;
reg [DATA_WIDTH-1:0] resp_data_mig;
reg resp_is_read_mig;

(* ASYNC_REG = "TRUE" *) reg [2:0] complete_sync_cpu;
wire complete_seen_cpu = complete_sync_cpu[2] ^ complete_sync_cpu[1];

wire write_req_cpu = cpu_app_en && (cpu_app_cmd == CMD_WRITE);
wire read_req_cpu = cpu_app_en && (cpu_app_cmd != CMD_WRITE);
wire write_complete_cpu = write_req_cpu && cpu_app_wdf_wren && cpu_app_wdf_end;
wire accept_cpu = !cpu_busy && (read_req_cpu || write_complete_cpu);

assign cpu_app_rdy = !cpu_busy && (!write_req_cpu || write_complete_cpu);
assign cpu_app_wdf_rdy = !cpu_busy && (!cpu_app_wdf_wren || write_complete_cpu);

always @(posedge cpu_clk) begin
    if (cpu_rst) begin
        req_addr_cpu <= {ADDR_WIDTH{1'b0}};
        req_cmd_cpu <= 3'b001;
        req_wdf_data_cpu <= {DATA_WIDTH{1'b0}};
        req_wdf_mask_cpu <= {DATA_WIDTH/8{1'b1}};
        req_is_write_cpu <= 1'b0;
        req_toggle_cpu <= 1'b0;
        cpu_busy <= 1'b0;
        complete_sync_cpu <= 3'b000;
        cpu_app_rd_data <= {DATA_WIDTH{1'b0}};
        cpu_app_rd_data_end <= 1'b0;
        cpu_app_rd_data_valid <= 1'b0;
    end else begin
        complete_sync_cpu <= {complete_sync_cpu[1:0], complete_toggle_mig};
        cpu_app_rd_data_end <= 1'b0;
        cpu_app_rd_data_valid <= 1'b0;

        if (accept_cpu) begin
            req_addr_cpu <= cpu_app_addr;
            req_cmd_cpu <= cpu_app_cmd;
            req_wdf_data_cpu <= cpu_app_wdf_data;
            req_wdf_mask_cpu <= cpu_app_wdf_mask;
            req_is_write_cpu <= (cpu_app_cmd == CMD_WRITE);
            req_toggle_cpu <= ~req_toggle_cpu;
            cpu_busy <= 1'b1;
        end

        if (complete_seen_cpu) begin
            if (resp_is_read_mig) begin
                cpu_app_rd_data <= resp_data_mig;
                cpu_app_rd_data_end <= 1'b1;
                cpu_app_rd_data_valid <= 1'b1;
            end
            cpu_busy <= 1'b0;
        end
    end
end

(* ASYNC_REG = "TRUE" *) reg [2:0] req_sync_mig;
wire req_seen_mig = req_sync_mig[2] ^ req_sync_mig[1];

reg active_mig;
reg is_write_mig;
reg cmd_accepted_mig;
reg wdf_accepted_mig;

always @(posedge mig_clk) begin
    if (mig_rst) begin
        req_sync_mig <= 3'b000;
        active_mig <= 1'b0;
        is_write_mig <= 1'b0;
        cmd_accepted_mig <= 1'b0;
        wdf_accepted_mig <= 1'b0;
        mig_app_addr <= {ADDR_WIDTH{1'b0}};
        mig_app_cmd <= 3'b001;
        mig_app_en <= 1'b0;
        mig_app_wdf_data <= {DATA_WIDTH{1'b0}};
        mig_app_wdf_end <= 1'b0;
        mig_app_wdf_wren <= 1'b0;
        mig_app_wdf_mask <= {DATA_WIDTH/8{1'b1}};
        complete_toggle_mig <= 1'b0;
        resp_data_mig <= {DATA_WIDTH{1'b0}};
        resp_is_read_mig <= 1'b0;
    end else begin
        req_sync_mig <= {req_sync_mig[1:0], req_toggle_cpu};

        if (mig_app_en && mig_app_rdy)
            mig_app_en <= 1'b0;
        if (mig_app_wdf_wren && mig_app_wdf_rdy) begin
            mig_app_wdf_wren <= 1'b0;
            mig_app_wdf_end <= 1'b0;
        end

        if (!active_mig && req_seen_mig) begin
            active_mig <= 1'b1;
            is_write_mig <= req_is_write_cpu;
            cmd_accepted_mig <= 1'b0;
            wdf_accepted_mig <= !req_is_write_cpu;
            mig_app_addr <= req_addr_cpu;
            mig_app_cmd <= req_cmd_cpu;
            mig_app_en <= 1'b1;
            mig_app_wdf_data <= req_wdf_data_cpu;
            mig_app_wdf_mask <= req_wdf_mask_cpu;
            if (req_is_write_cpu) begin
                mig_app_wdf_wren <= 1'b1;
                mig_app_wdf_end <= 1'b1;
            end
        end

        if (active_mig) begin
            if (mig_app_en && mig_app_rdy)
                cmd_accepted_mig <= 1'b1;
            if (is_write_mig && mig_app_wdf_wren && mig_app_wdf_rdy)
                wdf_accepted_mig <= 1'b1;

            if (is_write_mig) begin
                if ((cmd_accepted_mig || (mig_app_en && mig_app_rdy)) &&
                    (wdf_accepted_mig || (mig_app_wdf_wren && mig_app_wdf_rdy))) begin
                    active_mig <= 1'b0;
                    resp_is_read_mig <= 1'b0;
                    complete_toggle_mig <= ~complete_toggle_mig;
                end
            end else begin
                if (mig_app_rd_data_valid && mig_app_rd_data_end) begin
                    active_mig <= 1'b0;
                    resp_data_mig <= mig_app_rd_data;
                    resp_is_read_mig <= 1'b1;
                    complete_toggle_mig <= ~complete_toggle_mig;
                end
            end
        end
    end
end

endmodule
