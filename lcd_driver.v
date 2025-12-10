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


    // VARIÁVEIS DE ESTADO E CONTADORES

    // Definição dos Estados
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

    // Contador para o delay de 1ms
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


    // DETECÇÃO DE BORDA (PULSOS DOS BOTÕES)
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


    // LÓGICA SEQUENCIAL (REGISTROS DA FSM E CONTADOR)
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state <= S_POWER_OFF;
            ms_counter <= 17'd0;
            ms_done <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // Lógica do Contador de 1ms
            if (current_state == S_WAIT_1MS) begin
                if (ms_counter == 17'd50000) begin // 50.000 ciclos para 1ms 
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

    // LÓGICA COMBINACIONAL (TRANSIÇÕES DE ESTADO E SAÍDAS)
    // Rotina de formatação para ASCII (estilo Verilog-2001: escreve direto no ascii_buffer)
    task formatar_ascii;
        input [3:0] op;
        input [3:0] reg_dest;
        input [15:0] valor;
        integer i;
        begin
            ascii_len = 0;
            // 1ª linha: Operação (apenas ADD/SUB/LOAD/DISPLAY)
            case (op)
                4'b0000: begin ascii_buffer[0] = "L"; ascii_buffer[1] = "O"; ascii_buffer[2] = "A"; ascii_buffer[3] = "D"; ascii_len = 4; end
                4'b0001: begin ascii_buffer[0] = "A"; ascii_buffer[1] = "D"; ascii_buffer[2] = "D"; ascii_len = 3; end
                4'b0010: begin ascii_buffer[0] = "A"; ascii_buffer[1] = "D"; ascii_buffer[2] = "D"; ascii_buffer[3] = "I"; ascii_len = 4; end
                4'b0011: begin ascii_buffer[0] = "S"; ascii_buffer[1] = "U"; ascii_buffer[2] = "B"; ascii_len = 3; end
                4'b0100: begin ascii_buffer[0] = "S"; ascii_buffer[1] = "U"; ascii_buffer[2] = "B"; ascii_buffer[3] = "I"; ascii_len = 4; end
                4'b0101: begin ascii_buffer[0] = "M"; ascii_buffer[1] = "U"; ascii_buffer[2] = "L"; ascii_len = 3; end
                4'b0110: begin ascii_buffer[0] = "C"; ascii_buffer[1] = "L"; ascii_buffer[2] = "E"; ascii_buffer[3] = "A"; ascii_buffer[4] = "R"; ascii_len = 5; end
                4'b0111: begin ascii_buffer[0] = "D"; ascii_buffer[1] = "I"; ascii_buffer[2] = "S"; ascii_buffer[3] = "P"; ascii_buffer[4] = "L"; ascii_buffer[5] = "A"; ascii_buffer[6] = "Y"; ascii_len = 7; end
                default: begin ascii_buffer[0] = "-"; ascii_len = 1; end
            endcase
            // Espaço + reg destino em binário
            ascii_buffer[ascii_len] = " "; ascii_len = ascii_len + 1;
            ascii_buffer[ascii_len] = "["; ascii_len = ascii_len + 1;
            for (i = 3; i >= 0; i = i - 1) begin
                ascii_buffer[ascii_len] = (reg_dest[i]) ? "1" : "0";
                ascii_len = ascii_len + 1;
            end
            ascii_buffer[ascii_len] = "]"; ascii_len = ascii_len + 1;
            ascii_buffer[ascii_len] = " "; ascii_len = ascii_len + 1;

            // Sinal do valor
            if (valor[15]) ascii_buffer[ascii_len] = "-"; else ascii_buffer[ascii_len] = "+";
            ascii_len = ascii_len + 1;

            // Valor em decimal (simples, 5 dígitos)
            ascii_buffer[ascii_len] = ((valor/10000)%10) + 8'd48; ascii_len = ascii_len + 1;
            ascii_buffer[ascii_len] = ((valor/1000)%10)  + 8'd48; ascii_len = ascii_len + 1;
            ascii_buffer[ascii_len] = ((valor/100)%10)   + 8'd48; ascii_len = ascii_len + 1;
            ascii_buffer[ascii_len] = ((valor/10)%10)    + 8'd48; ascii_len = ascii_len + 1;
            ascii_buffer[ascii_len] = (valor%10)         + 8'd48; ascii_len = ascii_len + 1;
        end
    endtask

    always @(*) begin
        // Valores de saída padrão
        next_state = current_state;
        RS = 1'b0;  // Padrão: Comando
        RW = 1'b0;  // Padrão: Escrita
        E = 1'b0;   // Padrão: Enable Baixo
        Data_Bus = 8'h00; 

        // Sinais auxiliares (RW=0 em todos os estados de escrita)
        RW = 1'b0;

        case (current_state)
            // Desligado
            S_POWER_OFF: begin
                // Se o botão de ligar for solto (negedge detectado)
                if (power_on_solto) begin
                    next_state = S_INIT_START; // Inicia a primeira etapa da inicialização
                end
                
            end
            
            // COMANDO 1: FUNCTION SET (8-bit, 2 linhas)
            S_INIT_START: begin
                Data_Bus = 8'b00111000; // Function Set (8 bits, 2 linhas, 5x8 font)
                next_state_after_wait = S_INIT_CMD_2; // Próximo comando após a espera
                next_state = S_E_PULSE_HIGH;
            end
            
            // COMANDO 2: DISPLAY ON/OFF CONTROL 
            S_INIT_CMD_2: begin
                Data_Bus = 8'b00001100; // Display ON (D=1), Cursor OFF (C=0), Blink OFF (B=0)
                next_state_after_wait = S_INIT_CMD_3; // Próximo comando: Limpar Display
                next_state = S_E_PULSE_HIGH;
            end

            // COMANDO 3: CLEAR DISPLAY
            S_INIT_CMD_3: begin
                Data_Bus = 8'b00000001; // Clear Display
                next_state_after_wait = S_INIT_CMD_4; // Próximo comando: Entry Mode Set
                next_state = S_E_PULSE_HIGH;
            end
            
            // COMANDO 4: ENTRY MODE SET 
            S_INIT_CMD_4: begin
                Data_Bus = 8'b00000110; // Entry Mode Set (I/D=1: Incrementa cursor; S=0: Shift desativado)
                next_state_after_wait = S_IDLE_WAIT_INST; // Inicialização concluída
                next_state = S_E_PULSE_HIGH;
            end

            // ESTADO TRANSITÓRIO: E=1 (Inicia o pulso) 
            S_E_PULSE_HIGH: begin
                E = 1'b1; // Habilita o pulso
                // Neste mesmo estado, completamos o pulso E=1 -> E=0
                next_state = S_WAIT_1MS; // Vai para a espera, onde E=0 por default
            end
            
            // ESPERA OBRIGATÓRIA (1ms) 
            S_WAIT_1MS: begin
                E = 1'b0; // Garante o negedge e que E está baixo durante a espera
                if (ms_done) begin
                    next_state = next_state_after_wait; // Transiciona para o próximo comando
                end
            end
            
            // IDLE (Pronto para Instrução) 
            S_IDLE_WAIT_INST: begin
                // Ligar/Desligar: Se o botão de ligar for solto, volta para POWER_OFF
                if (power_on_solto) begin
                    next_state = S_POWER_OFF;
                end 
                // Enviar Instrução: Se o botão de envio for solto, inicia o processamento
                else if (btn_enviar_solto) begin
                    next_state = S_PROCESS_INST; 
                end
            end

            // PROCESSAMENTO DA INSTRUÇÃO 
            S_PROCESS_INST: begin
                formatar_ascii(cpu_opcode, cpu_dest_reg_addr, cpu_reg_result);
                buffer_pronto = 1;
                if (buffer_pronto)
                    next_state = S_SEND_DATA;
            end
            
            // ENVIO DE DADOS (CARACTERES ASCII) 
            S_SEND_DATA: begin
                RS = 1'b1; // Agora é dado (não comando)
                // Aqui, ascii_buffer[ascii_index] é enviado via Data_Bus
                Data_Bus = ascii_buffer[ascii_index];
                // Gera pulso Enable (E), incrementa ascii_index para o próximo caractere
            end

            default: next_state = S_POWER_OFF; // Default de segurança
        endcase
    end

endmodule
