// Testbench simples para module_mini_cpu
`timescale 1ns/1ps

module tb_mini_cpu;
    reg clk;
    reg reset_n;
    reg power_on;
    reg btn_enviar;
    reg [17:0] instrucao;

    wire LCD_RS, LCD_EN, LCD_RW, LCD_ON, LCD_BLON;
    wire [7:0] LCD_DATA;

    // DUT
    module_mini_cpu #(.FAST_SIM(1'b1)) dut (
        .clk(clk),
        .reset_n(reset_n),
        .power_on(power_on),
        .btn_enviar(btn_enviar),
        .instrucao(instrucao),
        .LCD_RS(LCD_RS),
        .LCD_EN(LCD_EN),
        .LCD_RW(LCD_RW),
        .LCD_DATA(LCD_DATA),
        .LCD_ON(LCD_ON),
        .LCD_BLON(LCD_BLON)
    );

    // Clock 50MHz -> 20ns period
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    task pulse_send;
    begin
        btn_enviar = 1'b1; #40;
        btn_enviar = 1'b0; #40;
    end
    endtask

    // Monitor LCD_EN pulses
    always @(posedge LCD_EN) begin
        $display("[%0t] LCD_EN pulse: RS=%b DATA=0x%02h (%s)", $time, LCD_RS, LCD_DATA, LCD_DATA);
    end

    initial begin
        reset_n   = 0;
        power_on  = 0;
        btn_enviar= 0;
        instrucao = 18'd0;
        #100;
        reset_n = 1;
        power_on = 1;

        // 1) LOAD R1, imm +5
        // formato imediato: opcode[17:15], dest[14:11], src1[10:7], sign[6], imm[5:0]
        instrucao = {3'b000, 4'd1, 4'd0, 1'b0, 6'b000101};
        pulse_send();
        #2000;

        // 2) ADD R2 = R1 + R1 (opcode=001, dest=2, src1=1, src2=1)
        // reg-reg: opcode[17:15], dest[14:11], src1[10:7], don't-care[6:4], src2[3:0]
        instrucao = {3'b001, 4'd2, 4'd1, 3'b000, 4'd1};
        pulse_send();
        #2000;

        // 3) DISPLAY R2 (opcode=111, dest=2)
        instrucao = {3'b111, 4'd2, 4'd0, 3'b000, 4'd0};
        pulse_send();
        #4000;

        $display("Testbench finished");
        $finish;
    end

endmodule
