module lcd_driver (
    // Entradas da Placa FPGA (DE2-115)
    input wire clk,             // Clock principal (50MHz)
    input wire reset_n,         // Reset Ativo Baixo (sincroniza o reset)
    input wire power_on,        // Sinal do botão Ligar/Desligar (entrada bruta)
    input wire btn_enviar,      // Sinal do botão Enviar Instrução (entrada bruta)

    // Entradas de Dados (Resultado da Mini-CPU)
    input wire [15:0] cpu_reg_result,     // Valor de resultado para exibir (Mini CPU)
    input wire [3:0]  cpu_dest_reg_addr,  // Endereço do Registrador de Destino (Mini CPU)
    input wire [3:0]  cpu_opcode,         // Opcode da instrução (Mini CPU)

    // Saídas para a Interface Física do LCD
    output reg RS,              // Register Select (Comando/Dado)
    output reg RW,              // Read/Write (Escrita/Leitura - Manter em 0 para Escrita)
    output reg E,               // Enable (Sinal de Strobe)
    output reg [7:0] Data_Bus   // Barramento de Dados (D7-D0)
);

    // ====================================================================
    // 1. VARIÁVEIS DE ESTADO E CONTADORES
    // ====================================================================

    // Definição dos Estados (Estendida para a sequência de inicialização)
    parameter
        S_POWER_OFF      = 4'h0, // Desligado, esperando botão 'Ligar'
        S_INIT_START     = 4'h1, // Início (Function Set: 8-bit, 2 linhas)
        S_INIT_CMD_2     = 4'h2, // Display ON/OFF Control
        S_INIT_CMD_3     = 4'h3, // Clear Display
        S_INIT_CMD_4     = 4'h4, // Entry Mode Set
        S_IDLE_WAIT_INST = 4'h5, // Pronto, esperando 'Enviar'
        S_E_PULSE_HIGH   = 4'h6, // Estado transiente para E=1
        S_WAIT_1MS       = 4'h7, // Espera obrigatória de 1ms
        S_PROCESS_INST   = 4'h8, // Início do processamento e formatação
        S_SEND_DATA      = 4'h9; // Envio de caracteres para o LCD
        
    // Estado atual e próximo
    reg [3:0] current_state, next_state;

    // Contador para o delay de 1ms (50.000 ciclos para um clock de 50MHz)
    reg [16:0] ms_counter;
    reg ms_done; // Sinalizador de que 1ms passou
    
    // Variável para rastrear a próxima transição após o WAIT_1MS
    reg [3:0] next_state_after_wait; 

    // Buffer para armazenamento dos caracteres ASCII a serem enviados (até 16 caracteres por linha, por exemplo)
    reg [7:0] ascii_buffer [0:31]; // [0:15] = linha 1, [16:31] = linha 2
    reg [5:0] ascii_index;          // Posição do caractere sendo enviado no buffer
    reg [5:0] ascii_len;            // Quantos caracteres serão enviados
    
    // Sinal para indicar buffer pronto para envio
    reg buffer_pronto;

    // ====================================================================
    // 2. DETECÇÃO DE BORDA (PULSOS DOS BOTÕES) - CRÍTICO PARA FUNCIONAMENTO
    // ====================================================================
    // Os botões devem gerar um pulso de 1 ciclo quando são soltos (negedge).

    reg power_on_d1;
    reg btn_enviar_d1;
    wire power_on_solto;
    wire btn_enviar_solto;

    // Registradores de atraso para detectar a borda
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            power_on_d1 <= 1'b0;
            btn_enviar_d1 <= 1'b0;
        end else begin
            power_on_d1 <= power_on;
            btn_enviar_d1 <= btn_enviar;
        end
    end

    // Geração do pulso: (Botão foi alto) E (Botão está baixo) -> negedge (solto)
    assign power_on_solto = power_on_d1 & ~power_on;
    assign btn_enviar_solto = btn_enviar_d1 & ~btn_enviar;


    // ====================================================================
    // 3. LÓGICA SEQUENCIAL (REGISTROS DA FSM E CONTADOR)
    // ====================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state <= S_POWER_OFF;
            ms_counter <= 17'd0;
            ms_done <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // Lógica do Contador de 1ms
            if (current_state == S_WAIT_1MS) begin
                if (ms_counter == 17'd50000) begin // 50.000 ciclos para 1ms @ 50MHz
                    ms_counter <= 17'd0;
                    ms_done <= 1'b1; // Sinaliza que o tempo acabou
                end else begin
                    ms_counter <= ms_counter + 17'd1;
                    ms_done <= 1'b0;
                end
            end else begin
                ms_counter <= 17'd0; // Zera o contador em outros estados
                ms_done <= 1'b0;
            end
        end
    end

    // ====================================================================
    // 4. LÓGICA COMBINACIONAL (TRANSIÇÕES DE ESTADO E SAÍDAS)
    // ====================================================================
    // Rotina de formatação para ASCII
    // Apenas exemplo inicial para demonstrar a montagem
    task formatar_ascii;
        input [3:0] op;
        input [3:0] reg_dest;
        input [15:0] valor;
        output [7:0] buffer [0:31];
        output [5:0] len;
        integer i;
        begin
            // 1ª linha: Operação (apenas ADD/SUB/LOAD/DISPLAY)
            case (op)
                4'b0000: begin buffer[0] = "L"; buffer[1] = "O"; buffer[2] = "A"; buffer[3] = "D"; len = 4; end
                4'b0001: begin buffer[0] = "A"; buffer[1] = "D"; buffer[2] = "D"; len = 3; end
                4'b0010: begin buffer[0] = "A"; buffer[1] = "D"; buffer[2] = "D"; buffer[3] = "I"; len = 4; end
                4'b0011: begin buffer[0] = "S"; buffer[1] = "U"; buffer[2] = "B"; len = 3; end
                4'b0100: begin buffer[0] = "S"; buffer[1] = "U"; buffer[2] = "B"; buffer[3] = "I"; len = 4; end
                4'b0101: begin buffer[0] = "M"; buffer[1] = "U"; buffer[2] = "L"; len = 3; end
                4'b0110: begin buffer[0] = "C"; buffer[1] = "L"; buffer[2] = "E"; buffer[3] = "A"; buffer[4] = "R"; len = 5; end
                4'b0111: begin buffer[0] = "D"; buffer[1] = "I"; buffer[2] = "S"; buffer[3] = "P"; buffer[4] = "L"; buffer[5] = "A"; buffer[6] = "Y"; len = 7; end
                default: begin buffer[0] = "-"; len = 1; end
            endcase
            // Espaço
            buffer[len] = " "; len = len + 1;
            // [NNNN] (reg_dest em binário)
            buffer[len] = "["; len = len + 1;
            for (i = 3; i >= 0; i = i - 1) begin
                buffer[len] = (reg_dest[i]) ? "1" : "0";
                len = len + 1;
            end
            buffer[len] = "]"; len = len + 1;
            buffer[len] = " "; len = len + 1;

            // Sinal do valor
            if (valor[15]) begin buffer[len] = "-"; end else begin buffer[len] = "+"; end
            len = len + 1;

            // Valor em decimal (simples, apenas para valores pequenos; para maiores, expandir depois)
            buffer[len] = ((valor/10000)%10) + 8'd48; len = len + 1;
            buffer[len] = ((valor/1000)%10) + 8'd48; len = len + 1;
            buffer[len] = ((valor/100)%10) + 8'd48; len = len + 1;
            buffer[len] = ((valor/10)%10) + 8'd48; len = len + 1;
            buffer[len] = (valor%10) + 8'd48; len = len + 1;
        end
    endtask

    // Chamada da task formatar_ascii no estado S_PROCESS_INST
    always @(*) begin
        // Valores de saída padrão (default)
        next_state = current_state;
        RS = 1'b0;  // Padrão: Comando
        RW = 1'b0;  // Padrão: Escrita
        E = 1'b0;   // Padrão: Enable Baixo
        Data_Bus = 8'h00; 

        // Sinais auxiliares (RW=0 em todos os estados de escrita)
        RW = 1'b0;

        case (current_state)
            // --- 0. POWER OFF (Desligado) ---
            S_POWER_OFF: begin
                // Se o botão de ligar for solto (negedge detectado)
                if (power_on_solto) begin
                    next_state = S_INIT_START; // Inicia a primeira etapa da inicialização
                end
                // Data_Bus = 8'h08; // Poderia ser um comando para forçar o display a desligar se necessário
            end
            
            // --- 1. COMANDO 1: FUNCTION SET (8-bit, 2 linhas) ---
            S_INIT_START: begin
                Data_Bus = 8'b00111000; // Function Set (8 bits, 2 linhas, 5x8 font)
                next_state_after_wait = S_INIT_CMD_2; // Próximo comando após a espera
                next_state = S_E_PULSE_HIGH;
            end
            
            // --- 2. COMANDO 2: DISPLAY ON/OFF CONTROL ---
            S_INIT_CMD_2: begin
                Data_Bus = 8'b00001100; // Display ON (D=1), Cursor OFF (C=0), Blink OFF (B=0)
                next_state_after_wait = S_INIT_CMD_3; // Próximo comando: Limpar Display
                next_state = S_E_PULSE_HIGH;
            end

            // --- 3. COMANDO 3: CLEAR DISPLAY ---
            S_INIT_CMD_3: begin
                Data_Bus = 8'b00000001; // Clear Display
                next_state_after_wait = S_INIT_CMD_4; // Próximo comando: Entry Mode Set
                next_state = S_E_PULSE_HIGH;
            end
            
            // --- 4. COMANDO 4: ENTRY MODE SET ---
            S_INIT_CMD_4: begin
                Data_Bus = 8'b00000110; // Entry Mode Set (I/D=1: Incrementa cursor; S=0: Shift desativado)
                next_state_after_wait = S_IDLE_WAIT_INST; // Inicialização concluída
                next_state = S_E_PULSE_HIGH;
            end

            // --- 5. ESTADO TRANSITÓRIO: E=1 (Inicia o pulso) ---
            S_E_PULSE_HIGH: begin
                E = 1'b1; // Habilita o pulso
                // Neste mesmo estado, completamos o pulso E=1 -> E=0
                next_state = S_WAIT_1MS; // Vai para a espera, onde E=0 por default
            end
            
            // --- 6. ESPERA OBRIGATÓRIA (1ms) ---
            S_WAIT_1MS: begin
                E = 1'b0; // Garante o negedge e que E está baixo durante a espera
                if (ms_done) begin
                    next_state = next_state_after_wait; // Transiciona para o próximo comando
                end
                // Sinais: RS=0, RW=0, E=0. Data_Bus pode ser ignorado.
            end
            
            // --- 7. IDLE (Pronto para Instrução) ---
            S_IDLE_WAIT_INST: begin
                // 1. Ligar/Desligar: Se o botão de ligar for solto, volta para POWER_OFF
                if (power_on_solto) begin
                    next_state = S_POWER_OFF;
                end 
                // 2. Enviar Instrução: Se o botão de envio for solto, inicia o processamento
                else if (btn_enviar_solto) begin
                    next_state = S_PROCESS_INST; 
                end
            end

            // --- 8. PROCESSAMENTO DA INSTRUÇÃO ---
            S_PROCESS_INST: begin
                formatar_ascii(cpu_opcode, cpu_dest_reg_addr, cpu_reg_result, ascii_buffer, ascii_len);
                buffer_pronto = 1;
                if (buffer_pronto)
                    next_state = S_SEND_DATA;
                // else continua nesse estado até o buffer estar pronto
            end
            
            // --- 9. ENVIO DE DADOS (CARACTERES ASCII) ---
            S_SEND_DATA: begin
                RS = 1'b1; // Agora é dado (não comando)
                // Aqui, ascii_buffer[ascii_index] é enviado via Data_Bus
                Data_Bus = ascii_buffer[ascii_index];
                // Gera pulso Enable (E), incrementa ascii_index para o próximo caractere
                // Exemplo (pseudo):
                // if (ascii_index < ascii_len)
                //     ascii_index = ascii_index + 1;
                // else
                //     next_state = S_IDLE_WAIT_INST;
            end


            default: next_state = S_POWER_OFF; // Default de segurança
        endcase
    end

endmodule
