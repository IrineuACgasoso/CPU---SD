`timescale 1ns/1ps
module tb_lcd_ascii;
    // Entradas para task
    reg [3:0] op;
    reg [3:0] reg_dest;
    reg [15:0] valor;
    reg [7:0] ascii_buffer [0:31];
    reg [5:0] ascii_len;
    integer i;

    // Instanciar o DUT (Device Under Test) apenas para usar a task
    lcd_driver dummy();

    initial begin
        // --- Teste 1: ADD R1, +12 ---
        op = 4'b0001;
        reg_dest = 4'b0001;
        valor = 16'd12;
        dummy.formatar_ascii(op, reg_dest, valor, ascii_buffer, ascii_len);
        $display("Teste 1 (ADD R1, +12):");
        for (i = 0; i < ascii_len; i = i + 1) $write("%s", ascii_buffer[i]);
        $display("");

        // --- Teste 2: SUBI R2, -13 ---
        op = 4'b0100;
        reg_dest = 4'b0010;
        valor = 16'b1111111111110011; // -13 em binário de 16 bits, sinal 2's complement
        dummy.formatar_ascii(op, reg_dest, valor, ascii_buffer, ascii_len);
        $display("Teste 2 (SUBI R2, -13):");
        for (i = 0; i < ascii_len; i = i + 1) $write("%s", ascii_buffer[i]);
        $display("");

        // --- Teste 3: DISPLAY R9, +7 ---
        op = 4'b0111;
        reg_dest = 4'b1001;
        valor = 16'd7;
        dummy.formatar_ascii(op, reg_dest, valor, ascii_buffer, ascii_len);
        $display("Teste 3 (DISPLAY R9, +7):");
        for (i = 0; i < ascii_len; i = i + 1) $write("%s", ascii_buffer[i]);
        $display("");

        $finish;
    end
endmodule
