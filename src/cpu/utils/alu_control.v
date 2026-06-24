module alu_control(
    input [1:0] alu_op,
    input [2:0] funct3,
    input [6:0] funct7,
    input [6:0] opcode,
    output reg [3:0] op
);

always @(*) begin
    case(alu_op)
        2'b00: op=4'b0000; // add
        2'b01: op=4'b0001; // sub
        2'b10: begin
            if(opcode==7'b1100011) begin
                // Branch: BLT/BGE用SLT, BLTU/BGEU用SLTU
                op=funct3[1]? 4'b1001:4'b1000;
            end else begin
                case(funct3)
                    3'b000: begin
                        if(opcode==7'b0110011 && funct7[5])
                            op=4'b0001; // sub
                        else
                            op=4'b0000; // add
                    end
                    3'b111: op=4'b0010; // and
                    3'b110: op=4'b0011; // or
                    3'b100: op=4'b0100; // xor
                    3'b001: op=4'b0101; // sll
                    3'b101: op=(funct7[5])? 4'b0111:4'b0110; // sra/srl
                    3'b010: op=4'b1000; // slt
                    3'b011: op=4'b1001; // sltu
                    default: op=4'b1111;
                endcase
            end
        end
        default: op=4'b1111;
    endcase
end

endmodule