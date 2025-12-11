module module_alu (
    input  wire [2:0]  opcode,
    input  wire signed [15:0] operand_a,
    input  wire signed [15:0] operand_b,
    output reg  signed [15:0] result
);
    // Definição dos Opcodes
    localparam OP_LOAD  = 3'b000;
    localparam OP_ADD   = 3'b001;
    localparam OP_ADDI  = 3'b010;
    localparam OP_SUB   = 3'b011;
    localparam OP_SUBI  = 3'b100;
    localparam OP_MUL   = 3'b101;
    localparam OP_CLEAR = 3'b110;
    localparam OP_DSPLY = 3'b111; 

    always @(*) begin
        case (opcode)
            OP_LOAD:  result = operand_b;        // Passa Imediato
            OP_ADD:   result = operand_a + operand_b;
            OP_ADDI:  result = operand_a + operand_b;
            OP_SUB:   result = operand_a - operand_b;
            OP_SUBI:  result = operand_a - operand_b;
            OP_MUL:   result = operand_a * operand_b;
            OP_CLEAR: result = 16'd0;            // Zera
            OP_DSPLY: result = operand_a;        // Passa valor do Registrador
            
            default:  result = 16'd0;
        endcase
    end
endmodule