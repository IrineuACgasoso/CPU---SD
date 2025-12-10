module module_alu (
    input signed [15:0] A,          // First operand (from register file)
    input signed [15:0] B,          // Second operand (register or immediate value)
    input [2:0] Opcode,            // 3-bit operation code
    output reg signed [15:0] Result, // Operation result
    output Zero                    // Zero flag (1 if result is zero)
);

    // Internal signal for multiplication result (32 bits to handle overflow)
    wire signed [31:0] mul_result;
    
    // Calculate multiplication result (32 bits)
    assign mul_result = A * B;
    
    // Zero flag generation
    assign Zero = (Result == 16'd0) ? 1'b1 : 1'b0;
    
    // Main ALU operation selection
    always @(*) begin
        case (Opcode)
            3'b000: // LOAD: Pass-through B
                Result = B;
                
            3'b001, // ADD: A + B
            3'b010: // ADDI: A + B (immediate)
                Result = A + B;
                
            3'b011, // SUB: A - B
            3'b100: // SUBI: A - B (immediate)
                Result = A - B;
                
            3'b101: // MUL: A * B (16 LSBs)
                Result = mul_result[15:0];  // Truncate to 16 bits
                
            3'b110: // CLEAR: Output zero
                Result = 16'd0;
                
            3'b111: // DISPLAY: Pass-through A
                Result = A;
                
            default: // Default case (shouldn't happen if Opcode is 3 bits)
                Result = 16'd0;
        endcase
    end

endmodule
