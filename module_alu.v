module module_alu (
    input  wire [2:0]  opcode,
    input  wire signed [15:0] A,
    input  wire signed [15:0] B,
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
    localparam OP_DSPLY = 3'b111; // Display

    always @(*) begin
        case (opcode)
            OP_LOAD:  result = B;      // Passa o Imediato
            OP_ADD:   result = A + B;
            OP_ADDI:  result = A + B;
            OP_SUB:   result = A - B;
            OP_SUBI:  result = A - B;
            OP_MUL:   result = A * B;
            OP_DSPLY: result = A;      
            
            default:  result = 16'd0;
        endcase
    end
endmodule