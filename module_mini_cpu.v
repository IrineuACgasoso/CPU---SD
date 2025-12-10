module module_mini_cpu #(
    parameter FAST_SIM = 1'b0  // Usa delays reduzidos no LCD para simulação
)(
    input  wire        clk,           // 50 MHz
    input  wire        reset_n,       // Reset global ativo baixo (KEY[0])
    input  wire        power_on,      // Botão de ligar/desligar (para LCD)
    input  wire        btn_enviar,    // Botão de envio da instrução (KEY[1], debounced internamente)
    input  wire [17:0] instrucao,     // SW[17:0]

    // Interface para LCD (driver)
    output wire        LCD_RS,
    output wire        LCD_EN,
    output wire        LCD_RW,
    output wire [7:0]  LCD_DATA,
    output wire        LCD_ON,
    output wire        LCD_BLON
);

    // Evita aviso de sinal não utilizado (power_on apenas repassado ao LCD)
    wire unused_power_on = power_on;

    // ------------------------------------------------------------
    // FSM de controle simples:
    // IDLE    : espera borda do botão Enviar
    // EXECUTE : decodifica instrução latched, seleciona operando/imediato e calcula na ULA
    // STORE   : grava resultado na memória (exceto DISPLAY/CLEAR)
    // LCD     : atualiza registradores de saída para o driver LCD
    // Depois retorna a IDLE
    // ------------------------------------------------------------
    localparam S_IDLE    = 2'd0;
    localparam S_EXECUTE = 2'd1;
    localparam S_STORE   = 2'd2;
    localparam S_LCD     = 2'd3;

    reg [1:0] state, next_state;

    // ------------------------------------------------------------
    // Debounce simples / detecção de borda de subida do botão Enviar (ativo alto)
    // ------------------------------------------------------------
    reg [2:0] btn_sync;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            btn_sync <= 3'b000;
        end else begin
            btn_sync <= {btn_sync[1:0], btn_enviar};
        end
    end
    wire btn_rise = (btn_sync[2:1] == 2'b01);

    // ------------------------------------------------------------
    // Latch da instrução ao apertar o botão (captura SW[17:0] em instr_reg)
    // ------------------------------------------------------------
    reg [17:0] instr_reg;
    // Campos da instrução (formato Reg-Reg ou Imediato)
    wire [2:0] opcode     = instr_reg[17:15]; // operação
    wire [3:0] reg_dest   = instr_reg[14:11];
    wire [3:0] reg_src1   = instr_reg[10:7];
    wire [3:0] reg_src2   = instr_reg[3:0];
    wire       is_immediate = (opcode == 3'b010) || (opcode == 3'b100) || (opcode == 3'b000); // ADDI, SUBI, LOAD usam imediato

    // Imediato com sinal: bits [6] (sinal) + [5:0] (valor). Extensão de sinal para 16 bits.
    wire [6:0]  imm7    = instr_reg[6:0];
    wire [15:0] imm_ext = {{9{imm7[6]}}, imm7};

    // ------------------------------------------------------------
    // Ligações com memória e ULA
    // ------------------------------------------------------------
    // Memória interna (endereços e dados)
    wire [3:0] mem_addr_read1 = reg_src1;
    wire [3:0] mem_addr_read2 = is_immediate ? 4'd0 : reg_src2;
    wire [3:0] mem_addr_write = reg_dest;
    wire [15:0] mem_data_in   = alu_result;
    wire [15:0] mem_data_out1;
    wire [15:0] mem_data_out2;
    wire        mem_we;

    // Operandos para a ULA (A=mem_data_out1, B=mem_data_out2 ou imediato)
    wire [15:0] alu_in1 = mem_data_out1;
    wire [15:0] alu_in2 = is_immediate ? imm_ext : mem_data_out2;
    wire [3:0]  alu_op  = {1'b0, opcode}; // exportado para debug
    wire [15:0] alu_result;

    // Memória: escrita somente no estado STORE (exceto DISPLAY 111 / CLEAR 110)
    wire will_write = (opcode != 3'b111) && (opcode != 3'b110);
    assign mem_we = (state == S_STORE) && will_write;

    // CLEAR: força reset dos registradores na memória (pulso de reset_n baixo durante EXECUTE do opcode CLEAR)
    wire mem_reset_n = reset_n & ~((state == S_EXECUTE) && (opcode == 3'b110));

    // ------------------------------------------------------------
    // Registradores repassados ao driver LCD (valor, registrador de destino, opcode)
    // ------------------------------------------------------------
    reg [15:0] reg_result;
    reg [3:0]  reg_dest_addr;
    reg [3:0]  reg_opcode;

    // ------------------------------------------------------------
    // Sequencial da FSM
    // ------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= S_IDLE;
            instr_reg     <= 18'd0;
            reg_result    <= 16'd0;
            reg_dest_addr <= 4'd0;
            reg_opcode    <= 4'd0;
        end else begin
            state <= next_state;

            // Latch da instrução na transição IDLE -> EXECUTE
            if (state == S_IDLE && btn_rise) begin
                instr_reg <= instrucao;
            end

            // Atualiza sinais para o LCD na saída do STORE -> LCD
            if (state == S_LCD) begin
                reg_result    <= (opcode == 3'b110) ? 16'd0 : alu_result; // CLEAR mostra zero
                reg_dest_addr <= reg_dest;
                reg_opcode    <= {1'b0, opcode};
            end
        end
    end

    // ------------------------------------------------------------
    // Combinacional da FSM
    // ------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:    next_state = btn_rise ? S_EXECUTE : S_IDLE;
            S_EXECUTE: next_state = S_STORE;
            S_STORE:   next_state = S_LCD;
            S_LCD:     next_state = S_IDLE;
            default:   next_state = S_IDLE;
        endcase
    end

    // ------------------------------------------------------------
    // Instâncias: memória, ULA e driver LCD (lcd_driver.v existente)
    // ------------------------------------------------------------
    memory mem_inst (
        .clk        (clk),
        .reset_n    (mem_reset_n),
        .we         (mem_we),
        .addr_write (mem_addr_write),
        .addr_read1 (mem_addr_read1),
        .addr_read2 (mem_addr_read2),
        .data_in    (mem_data_in),
        .data_out1  (mem_data_out1),
        .data_out2  (mem_data_out2)
    );

    module_alu alu_inst (
        .A      (alu_in1),
        .B      (alu_in2),
        .Opcode (opcode),
        .Result (alu_result),
        .Zero   ()
    );

    // Reutiliza o driver já presente (lcd_driver.v)
    lcd_driver lcd_inst (
        .clk              (clk),
        .reset_n          (reset_n),
        .power_on         (power_on),
        .btn_enviar       (btn_enviar),
        .cpu_reg_result   (reg_result),
        .cpu_dest_reg_addr(reg_dest_addr),
        .cpu_opcode       (reg_opcode),
        .RS               (LCD_RS),
        .RW               (LCD_RW),
        .E                (LCD_EN),
        .Data_Bus         (LCD_DATA)
    );

    // LCD sempre ligado na placa
    assign LCD_ON   = 1'b1;
    assign LCD_BLON = 1'b1;

endmodule
