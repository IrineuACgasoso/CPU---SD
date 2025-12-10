module module_mini_cpu (
    input  wire        clk,
    input  wire        rst,         // Botão KEY[0] (reset)
    input  wire        send_btn,    // Botão KEY[1] (Enviar)
    input  wire [17:0] switches,    // Instrução
    
    // Interface LCD
    output reg         lcd_update,
    output reg [2:0]   lcd_opcode,
    output reg [3:0]   lcd_reg_idx,
    output reg [15:0]  lcd_value,
    input  wire        lcd_busy
);

    // --- Decodificação dos Switches ---
    wire [2:0] opcode = switches[17:15];
    wire [3:0] r_dest = switches[14:11]; // Destino (onde grava)
    wire [3:0] r_src1 = switches[10:7];  // Fonte 1 (Operand A)
    wire [3:0] r_src2 = switches[6:3];   // Fonte 2 (Operand B - Reg)
    wire [6:0] imm7   = switches[6:0];   // Imediato pequeno (ADDI, SUBI)
    wire [10:0] imm11 = switches[10:0];  // Imediato grande (LOAD)

    // --- Sinais Internos ---
    reg mem_we;
    reg [15:0] mem_data_wr;
    wire [15:0] mem_out1, mem_out2;
    
    reg [15:0] alu_in_a, alu_in_b;
    wire signed [15:0] alu_result;

    // --- Instâncias ---
    memory mem_inst (
        .clk(clk), .rst(rst), .we(mem_we), 
        .addr_wr(r_dest), .data_in(mem_data_wr),
        .addr_rd1(r_src1), .addr_rd2(r_src2),
        .data_out1(mem_out1), .data_out2(mem_out2)
    );

    module_alu alu_inst (
        .opcode(opcode), .A(alu_in_a), .B(alu_in_b), .result(alu_result)
    );

    // Detector de borda do botão (Soltar o botão)
    reg btn_prev;
    wire btn_released = (btn_prev == 1'b0 && send_btn == 1'b1);
    always @(posedge clk) btn_prev <= send_btn;

    // --- Máquina de Estados (FSM) ---
    // Adicionado estado S_LATCH para estabilizar dados
    localparam S_WAIT_BTN = 0, S_EXECUTE = 1, S_LATCH = 2, S_UPDATE_LCD = 3, S_WAIT_LCD = 4;
    reg [2:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_WAIT_BTN;
            mem_we <= 0;
            lcd_update <= 0;
            alu_in_a <= 0; 
            alu_in_b <= 0;
        end else begin
            case (state)
                // 1. Espera usuário soltar botão enviar
                S_WAIT_BTN: begin
                    mem_we <= 0;
                    lcd_update <= 0;
                    if (btn_released && !lcd_busy) begin
                        state <= S_EXECUTE;
                    end
                end

                // 2. Configura as entradas da ALU (Ainda não temos o resultado)
                S_EXECUTE: begin
                    case (opcode)
                        3'b000: begin // LOAD
                            alu_in_a <= 0; 
                            alu_in_b <= {{5{imm11[10]}}, imm11}; // Extensão de sinal
                        end
                        3'b001, 3'b011, 3'b101: begin // ADD, SUB, MUL (Reg, Reg)
                            alu_in_a <= mem_out1; 
                            alu_in_b <= mem_out2;
                        end
                        3'b010, 3'b100: begin // ADDI, SUBI (Reg, Imm)
                            alu_in_a <= mem_out1; 
                            alu_in_b <= {{9{imm7[6]}}, imm7};
                        end
                        3'b110: begin // CLEAR
                             alu_in_a <= 0; alu_in_b <= 0;
                        end
                        3'b111: begin // DISPLAY (Lê valor do Reg)
                            // Para mostrar o valor, passamos ele pela ALU (A + 0)
                            alu_in_a <= mem_out1; 
                            alu_in_b <= 0;
                        end
                        default: begin alu_in_a <= 0; alu_in_b <= 0; end
                    endcase
                    state <= S_LATCH;
                end

                // 3. NOVO ESTADO: O resultado da ALU agora é válido.
                //    Aqui salvamos na memória e capturamos o valor para o LCD.
                S_LATCH: begin
                    // Escreve na memória (se não for DISPLAY)
                    if (opcode != 3'b111) begin
                        mem_we <= 1;
                        mem_data_wr <= alu_result;
                    end

                    // Prepara dados para o LCD
                    lcd_opcode  <= opcode;
                    lcd_reg_idx <= r_dest; 
                    lcd_value   <= alu_result; // Agora alu_result contém o valor calculado no ciclo anterior
                    
                    state <= S_UPDATE_LCD;
                end

                // 4. Manda o pulso para o controlador do LCD
                S_UPDATE_LCD: begin
                    mem_we <= 0;     // Para de escrever na memória
                    lcd_update <= 1; // Avisa o LCD: "Pode desenhar"
                    state <= S_WAIT_LCD;
                end

                // 5. Espera o LCD terminar
                S_WAIT_LCD: begin
                    lcd_update <= 0;
                    if (!lcd_busy) state <= S_WAIT_BTN;
                end
            endcase
        end
    end
endmodule