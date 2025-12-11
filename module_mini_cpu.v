module module_mini_cpu (
    input  wire        clk,                                    
    input  wire        button_power,    
    input  wire        button_send,     
    input  wire [17:0] switches,     
    
    // Controle Global
    output reg         system_reset_out,     
    output reg         show_splash_req, 
    output reg         force_blank_req, 
    
    // Interface LCD                                       
    output reg         lcd_start,
    output reg [2:0]   lcd_opcode,
    output reg [3:0]   lcd_reg_index,
    output reg [15:0]  lcd_value,
    input  wire        lcd_busy
);

    // --- Definição do Conjunto de Instruções (Opcodes) ---
    localparam [2:0] OP_LOAD    = 3'b000;
    localparam [2:0] OP_ADD     = 3'b001;
    localparam [2:0] OP_ADDI    = 3'b010;
    localparam [2:0] OP_SUB     = 3'b011;
    localparam [2:0] OP_SUBI    = 3'b100;
    localparam [2:0] OP_MUL     = 3'b101;
    localparam [2:0] OP_CLEAR   = 3'b110;
    localparam [2:0] OP_DISPLAY = 3'b111;

    // --- Decodificação das Entradas ---
    wire [2:0] op_code      = switches[17:15];
    wire [3:0] reg_dest     = switches[14:11]; // Destino
    wire [3:0] reg_source_1 = switches[10:7];  // Fonte 1
    wire [3:0] reg_source_2 = switches[6:3];   // Fonte 2
    
    // Entrada de Imediato (7 bits: 1 Sinal + 6 Magnitude)
    wire [6:0] immediate_raw  = switches[6:0]; 
    wire       immediate_sign = immediate_raw[6];
    wire [5:0] immediate_mag  = immediate_raw[5:0];

    // --- Sinais Internos ---
    reg  memory_write_enable;
    reg  [15:0] memory_write_data;
    wire [15:0] memory_read_1, memory_read_2;
    
    reg  [15:0] alu_input_a, alu_input_b;
    wire signed [15:0] alu_result;
    
    reg clear_instruction_signal; 
    wire memory_reset = system_reset_out || clear_instruction_signal;

    // --- Lógica de Leitura Especial ---
    // Se for DISPLAY, lemos o registrador indicado em Destino
    wire [3:0] read_address_1;
    assign read_address_1 = (op_code == OP_DISPLAY) ? reg_dest : reg_source_1;

    // --- Conversão Sinal-Magnitude ---
    wire signed [15:0] immediate_extended;
    assign immediate_extended = (immediate_sign) ? -{10'd0, immediate_mag} : {10'd0, immediate_mag};

    // --- Detector de Borda (Soltar o Botão) ---
    reg btn_send_last, btn_power_last;
    wire send_released  = (btn_send_last == 1'b1 && button_send == 1'b0);
    wire power_released = (btn_power_last == 1'b1 && button_power == 1'b0);
    
    always @(posedge clk) begin
        btn_send_last  <= button_send;
        btn_power_last <= button_power;
    end

    // --- Instâncias ---
    memory mem_unit (
        .clk(clk), 
        .rst(memory_reset), 
        .we(memory_write_enable), 
        .write_addr(reg_dest), 
        .write_data(memory_write_data),
        .read_addr_1(read_address_1),
        .read_addr_2(reg_source_2),
        .read_data_1(memory_read_1), 
        .read_data_2(memory_read_2)
    );

    module_alu alu_unit (
        .opcode(op_code), 
        .operand_a(alu_input_a), 
        .operand_b(alu_input_b), 
        .result(alu_result)
    );

    // --- Máquina de Estados (FSM) ---
    localparam STATE_OFF        = 0, 
               STATE_WAIT_BOOT  = 1, 
               STATE_SPLASH     = 2, 
               STATE_IDLE       = 3, 
               STATE_EXECUTE    = 4, 
               STATE_LATCH      = 5, 
               STATE_SHUTDOWN   = 6, 
               STATE_UPDATE_LCD = 7, 
               STATE_WAIT_LCD   = 8;
               
    reg [3:0] current_state = STATE_OFF;
    reg [15:0] wait_timer; 

    always @(posedge clk) begin
        clear_instruction_signal <= 0; 

        case (current_state)
            // 1. Sistema Desligado
            STATE_OFF: begin
                system_reset_out <= 1; 
                memory_write_enable <= 0; 
                lcd_start <= 0; 
                show_splash_req <= 0; 
                force_blank_req <= 0; 
                wait_timer <= 0;
                
                if (power_released) begin 
                    system_reset_out <= 0; 
                    current_state <= STATE_WAIT_BOOT; 
                end
            end

            // 2. Aguarda Hardware LCD Inicializar
            STATE_WAIT_BOOT: begin
                if (wait_timer < 1000) begin
                    wait_timer <= wait_timer + 1;
                end else if (!lcd_busy) begin
                    current_state <= STATE_SPLASH;
                end
            end

            // 3. Mostra Tela de Inicialização
            STATE_SPLASH: begin 
                show_splash_req <= 1; 
                current_state <= STATE_UPDATE_LCD; 
            end

            // 4. Estado Ocioso
            STATE_IDLE: begin
                memory_write_enable <= 0; 
                lcd_start <= 0; 
                show_splash_req <= 0; 
                force_blank_req <= 0;
                
                if (power_released) begin
                    current_state <= STATE_SHUTDOWN;
                end else if (send_released) begin
                    current_state <= STATE_EXECUTE;
                end
            end
            
            // 5. Preparação para Desligar
            STATE_SHUTDOWN: begin 
                force_blank_req <= 1; 
                current_state <= STATE_UPDATE_LCD; 
            end

            // 6. Execução da Instrução
            STATE_EXECUTE: begin
                case (op_code)
                    OP_LOAD: begin 
                        alu_input_a <= 0; 
                        alu_input_b <= immediate_extended; 
                    end 
                    
                    OP_ADD, OP_SUB: begin 
                        alu_input_a <= memory_read_1; 
                        alu_input_b <= memory_read_2; 
                    end 
                    
                    OP_ADDI, OP_SUBI, OP_MUL: begin 
                        alu_input_a <= memory_read_1; 
                        alu_input_b <= immediate_extended; 
                    end 
                    
                    OP_CLEAR: begin 
                        alu_input_a <= 0; 
                        alu_input_b <= 0; 
                        clear_instruction_signal <= 1; 
                    end 
                    
                    OP_DISPLAY: begin 
                        alu_input_a <= memory_read_1; 
                        alu_input_b <= 0; 
                    end 
                    
                    default: begin alu_input_a <= 0; alu_input_b <= 0; end
                endcase
                current_state <= STATE_LATCH;
            end

            // 7. Salvar Resultado
            STATE_LATCH: begin
                // Escreve na memória (Exceto DISPLAY e CLEAR)
                if (op_code != OP_DISPLAY && op_code != OP_CLEAR) begin 
                    memory_write_enable <= 1; 
                    memory_write_data <= alu_result;
                end
                
                lcd_opcode <= op_code; 
                lcd_reg_index <= reg_dest; 
                lcd_value <= alu_result;
                
                current_state <= STATE_UPDATE_LCD;
            end

            // 8. Disparo do LCD
            STATE_UPDATE_LCD: begin 
                memory_write_enable <= 0; 
                lcd_start <= 1; 
                wait_timer <= 0; 
                current_state <= STATE_WAIT_LCD; 
            end

            // 9. Espera LCD Terminar
            STATE_WAIT_LCD: begin
                lcd_start <= 0; 
                if (wait_timer < 15) begin
                    wait_timer <= wait_timer + 1;
                end else if (!lcd_busy) begin
                    if (force_blank_req) current_state <= STATE_OFF;
                    else current_state <= STATE_IDLE;
                end
            end
        endcase
    end
endmodule