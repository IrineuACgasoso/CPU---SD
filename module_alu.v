module module_alu (
    input wire [3:0] alu_op,
    input wire [15:0] alu_in1,
    input wire [15:0] alu_in2,
    output reg [15:0] alu_result
);

    always @(*) begin
        case (alu_op)
            4'b0000: alu_result = alu_in1 + alu_in2; // ADD (exemplo)
            4'b0001: alu_result = alu_in1 - alu_in2; // SUB (exemplo)
            // Demais operações aqui
            default: alu_result = 16'd0;
        endcase
    end

endmodule
