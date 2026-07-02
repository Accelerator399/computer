module uart_ddr_loader #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200,
    parameter ADDR_WIDTH = 27
)(
    input clk,
    input rst,

    input uart_rx,
    output uart_tx,

    output reg done,
    output reg error,
    output reg [31:0] line_count,

    output reg [ADDR_WIDTH-1:0] app_addr,
    output reg [2:0] app_cmd,
    output reg app_en,
    output reg [127:0] app_wdf_data,
    output reg app_wdf_end,
    output reg app_wdf_wren,
    output reg [15:0] app_wdf_mask,
    input app_rdy,
    input app_wdf_rdy
);

localparam [2:0] CMD_WRITE = 3'b000;

localparam S_WAIT_LINE = 3'd0;
localparam S_WRITE = 3'd1;
localparam S_ACK = 3'd2;
localparam S_GO_ACK = 3'd3;
localparam S_ERROR_ACK = 3'd4;
localparam S_DONE = 3'd5;
localparam S_READY_ACK = 3'd6;
localparam S_RELEASE_DELAY = 3'd7;

localparam ACK_READY_LEN = 4;
localparam ACK_OK_LEN = 3;
localparam ACK_GO_LEN = 3;
localparam ACK_ERR_LEN = 4;
localparam integer RELEASE_DELAY_CYCLES = CLK_FREQ / 10;
localparam integer RELEASE_DELAY_BITS = (RELEASE_DELAY_CYCLES <= 1) ? 1 : $clog2(RELEASE_DELAY_CYCLES + 1);
localparam integer RX_FIFO_DEPTH = 512;

wire [7:0] rx_data;
wire rx_ready;
wire frame_error;
reg rx_clear;

reg tx_start;
reg [7:0] tx_data;
wire tx_busy;

wire rx_fifo_push;
wire rx_fifo_pop;
wire [7:0] rx_fifo_data;
wire rx_fifo_empty;
wire rx_fifo_full;

uart #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) u_uart (
    .clk(clk),
    .rst(rst),
    .tx_start(tx_start),
    .tx_data(tx_data),
    .tx_busy(tx_busy),
    .rx_data(rx_data),
    .rx_ready(rx_ready),
    .frame_error(frame_error),
    .rx_read_clear(rx_clear),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx)
);

byte_fifo #(
    .DEPTH(RX_FIFO_DEPTH)
) u_rx_fifo (
    .clk(clk),
    .rst(rst),
    .push(rx_fifo_push),
    .din(rx_data),
    .pop(rx_fifo_pop),
    .dout(rx_fifo_data),
    .empty(rx_fifo_empty),
    .full(rx_fifo_full)
);

reg [2:0] state;
reg [3:0] addr_digits;
reg [5:0] data_digits;
reg [31:0] parsed_addr;
reg [127:0] parsed_data;
reg got_space;
reg cmd_done;
reg wdf_done;
reg [2:0] ack_index;
reg tx_busy_d;
reg rx_ready_seen;
reg [RELEASE_DELAY_BITS-1:0] release_delay_count;

wire tx_done = tx_busy_d && !tx_busy;
assign rx_fifo_push = rx_ready && !rx_ready_seen && !rx_fifo_full;
assign rx_fifo_pop = (state == S_WAIT_LINE) && !rx_fifo_empty;

function [4:0] hex_value;
    input [7:0] ch;
    begin
        if(ch >= "0" && ch <= "9")
            hex_value = {1'b0, ch[3:0]};
        else if(ch >= "a" && ch <= "f")
            hex_value = 5'd10 + {1'b0, ch[3:0]} - 5'd1;
        else if(ch >= "A" && ch <= "F")
            hex_value = 5'd10 + {1'b0, ch[3:0]} - 5'd1;
        else
            hex_value = 5'h10;
    end
endfunction

function is_hex;
    input [7:0] ch;
    begin
        is_hex = hex_value(ch) < 5'h10;
    end
endfunction

function is_blank;
    input [7:0] ch;
    begin
        is_blank = (ch == 8'h20) || (ch == 8'h09) || (ch == 8'h0d);
    end
endfunction

function [7:0] ack_ok_byte;
    input [2:0] idx;
    begin
        case(idx)
            3'd0: ack_ok_byte = "O";
            3'd1: ack_ok_byte = "K";
            default: ack_ok_byte = 8'h0a;
        endcase
    end
endfunction

function [7:0] ack_ready_byte;
    input [2:0] idx;
    begin
        case(idx)
            3'd0: ack_ready_byte = "R";
            3'd1: ack_ready_byte = "D";
            3'd2: ack_ready_byte = "Y";
            default: ack_ready_byte = 8'h0a;
        endcase
    end
endfunction

function [7:0] ack_go_byte;
    input [2:0] idx;
    begin
        case(idx)
            3'd0: ack_go_byte = "G";
            3'd1: ack_go_byte = "O";
            default: ack_go_byte = 8'h0a;
        endcase
    end
endfunction

function [7:0] ack_err_byte;
    input [2:0] idx;
    begin
        case(idx)
            3'd0: ack_err_byte = "E";
            3'd1: ack_err_byte = "R";
            3'd2: ack_err_byte = "R";
            default: ack_err_byte = 8'h0a;
        endcase
    end
endfunction

task reset_line_parser;
    begin
        addr_digits <= 4'd0;
        data_digits <= 6'd0;
        parsed_addr <= 32'b0;
        parsed_data <= 128'b0;
        got_space <= 1'b0;
    end
endtask

task start_ack;
    input [2:0] next_state;
    begin
        ack_index <= 3'd0;
        state <= next_state;
    end
endtask

task parser_error;
    begin
        error <= 1'b1;
        reset_line_parser();
        start_ack(S_ERROR_ACK);
    end
endtask

wire line_complete = (addr_digits == 4'd8) && got_space && (data_digits == 6'd32);
wire [4:0] rx_hex = hex_value(rx_fifo_data);
wire rx_is_go = ((rx_fifo_data == "G") || (rx_fifo_data == "g")) && (addr_digits == 4'd0) && !got_space;

always @(posedge clk) begin
    if(rst) begin
        state <= S_READY_ACK;
        done <= 1'b0;
        error <= 1'b0;
        line_count <= 32'b0;
        app_addr <= {ADDR_WIDTH{1'b0}};
        app_cmd <= CMD_WRITE;
        app_en <= 1'b0;
        app_wdf_data <= 128'b0;
        app_wdf_end <= 1'b0;
        app_wdf_wren <= 1'b0;
        app_wdf_mask <= 16'hffff;
        cmd_done <= 1'b0;
        wdf_done <= 1'b0;
        tx_start <= 1'b0;
        tx_data <= 8'h00;
        rx_clear <= 1'b0;
        tx_busy_d <= 1'b0;
        rx_ready_seen <= 1'b0;
        ack_index <= 3'd0;
        release_delay_count <= {RELEASE_DELAY_BITS{1'b0}};
        reset_line_parser();
    end else begin
        tx_start <= 1'b0;
        rx_clear <= 1'b0;
        tx_busy_d <= tx_busy;
        if(!rx_ready)
            rx_ready_seen <= 1'b0;

        if(rx_ready && !rx_ready_seen) begin
            rx_ready_seen <= 1'b1;
            rx_clear <= 1'b1;
            if(rx_fifo_full)
                error <= 1'b1;
        end

        if(frame_error)
            error <= 1'b1;

        case(state)
            S_WAIT_LINE: begin
                app_en <= 1'b0;
                app_wdf_wren <= 1'b0;
                app_wdf_end <= 1'b0;

                if(rx_fifo_pop) begin
                    if(rx_is_go) begin
                        reset_line_parser();
                        start_ack(S_GO_ACK);
                    end else if(rx_fifo_data == 8'h0a) begin
                        if(line_complete) begin
                            app_addr <= parsed_addr[ADDR_WIDTH-1:0];
                            app_cmd <= CMD_WRITE;
                            app_wdf_data <= parsed_data;
                            app_wdf_mask <= 16'h0000;
                            app_wdf_end <= 1'b1;
                            app_en <= 1'b1;
                            app_wdf_wren <= 1'b1;
                            cmd_done <= 1'b0;
                            wdf_done <= 1'b0;
                            state <= S_WRITE;
                        end else if(addr_digits == 4'd0 && !got_space && data_digits == 6'd0) begin
                            reset_line_parser();
                        end else begin
                            parser_error();
                        end
                    end else if(is_blank(rx_fifo_data)) begin
                        if(addr_digits == 4'd8)
                            got_space <= 1'b1;
                    end else if(is_hex(rx_fifo_data)) begin
                        if(!got_space) begin
                            if(addr_digits < 4'd8) begin
                                parsed_addr <= {parsed_addr[27:0], rx_hex[3:0]};
                                addr_digits <= addr_digits + 4'd1;
                            end else begin
                                parser_error();
                            end
                        end else begin
                            if(data_digits < 6'd32) begin
                                parsed_data <= {parsed_data[123:0], rx_hex[3:0]};
                                data_digits <= data_digits + 6'd1;
                            end else begin
                                parser_error();
                            end
                        end
                    end else begin
                        parser_error();
                    end
                end
            end

            S_WRITE: begin
                if(app_en && app_rdy) begin
                    app_en <= 1'b0;
                    cmd_done <= 1'b1;
                end
                if(app_wdf_wren && app_wdf_rdy) begin
                    app_wdf_wren <= 1'b0;
                    app_wdf_end <= 1'b0;
                    wdf_done <= 1'b1;
                end

                if((cmd_done || (app_en && app_rdy)) &&
                   (wdf_done || (app_wdf_wren && app_wdf_rdy))) begin
                    line_count <= line_count + 32'd1;
                    reset_line_parser();
                    start_ack(S_ACK);
                end
            end

            S_READY_ACK: begin
                if(tx_done) begin
                    if(ack_index == ACK_READY_LEN - 1) begin
                        ack_index <= 3'd0;
                        state <= S_WAIT_LINE;
                    end else begin
                        ack_index <= ack_index + 3'd1;
                    end
                end else if(!tx_busy && !tx_start) begin
                    tx_data <= ack_ready_byte(ack_index);
                    tx_start <= 1'b1;
                end
            end

            S_ACK: begin
                if(tx_done) begin
                    if(ack_index == ACK_OK_LEN - 1) begin
                        ack_index <= 3'd0;
                        state <= S_WAIT_LINE;
                    end else begin
                        ack_index <= ack_index + 3'd1;
                    end
                end else if(!tx_busy && !tx_start) begin
                    tx_data <= ack_ok_byte(ack_index);
                    tx_start <= 1'b1;
                end
            end

            S_GO_ACK: begin
                if(tx_done) begin
                    if(ack_index == ACK_GO_LEN - 1) begin
                        release_delay_count <= RELEASE_DELAY_CYCLES[RELEASE_DELAY_BITS-1:0];
                        state <= S_RELEASE_DELAY;
                    end else begin
                        ack_index <= ack_index + 3'd1;
                    end
                end else if(!tx_busy && !tx_start) begin
                    tx_data <= ack_go_byte(ack_index);
                    tx_start <= 1'b1;
                end
            end

            S_ERROR_ACK: begin
                if(tx_done) begin
                    if(ack_index == ACK_ERR_LEN - 1) begin
                        ack_index <= 3'd0;
                        state <= S_WAIT_LINE;
                    end else begin
                        ack_index <= ack_index + 3'd1;
                    end
                end else if(!tx_busy && !tx_start) begin
                    tx_data <= ack_err_byte(ack_index);
                    tx_start <= 1'b1;
                end
            end

            S_RELEASE_DELAY: begin
                if(release_delay_count == {RELEASE_DELAY_BITS{1'b0}}) begin
                    done <= 1'b1;
                    state <= S_DONE;
                end else begin
                    release_delay_count <= release_delay_count - 1'b1;
                end
            end

            S_DONE: begin
                app_en <= 1'b0;
                app_wdf_wren <= 1'b0;
                app_wdf_end <= 1'b0;
                done <= 1'b1;
            end

            default: begin
                state <= S_WAIT_LINE;
            end
        endcase
    end
end

endmodule
