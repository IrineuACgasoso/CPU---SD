`define POSITIVE 1'b0
`define NEGATIVE 1'b1
`define ZERO 4'd0
`define DISABLE 1'b0
`define ENABLE 1'b1

module control_unit (
    input wire          clk,
    input wire          rst,          // Botão Ligar/Desligar
    input wire          send,         // Botão Enviar
    
    // --- RECONECTADO: Entradas reais ---
    input wire          LCD_done,     // 1 = LCD Pronto/Livre
    input wire          store_done,   // 1 = Escrita concluída
    // -----------------------------------
    
    input wire [17:0]   switches,
    
    output reg [3:0]    DEST,
    output reg [3:0]    SRC1,
    output reg [3:0]    SRC2,
    output reg          IMM_SIGN,
    output reg [5:0]    IMM_MAGNETUDE,
    
    output reg [2:0]    alu_func,
    output reg          alu_enable,
    output reg          read_enable,
    output reg          write_enable, 
    output reg          clear_mem
);  

    // Estados da FSM
    parameter [3:0]
        BUTTON_OFF  = 4'b0000,
        BUTTON_ON   = 4'b0001,
        BUTTON_SEND = 4'b0010,
        OFF         = 4'b0011,
        INIT        = 4'b0100,
        IDLE        = 4'b0101,
        DECODE      = 4'b0110,
        EXECUTE     = 4'b0111,
        STORE       = 4'b1000;
    
    // Opcodes
    parameter [2:0]
        LOAD    = 3'b000,
        ADD     = 3'b001,
        ADDI    = 3'b010,
        SUB     = 3'b011,
        SUBI    = 3'b100,
        MUL     = 3'b101,
        CLEAR   = 3'b110,
        DISPLAY = 3'b111;

    wire pulse_on_off;
    wire pulse_send;

    // Debounces instanciados
    debounce inst0 (.clk(clk), .button_in(rst),  .button_pulse(pulse_on_off));
    debounce inst1 (.clk(clk), .button_in(send), .button_pulse(pulse_send));

    reg [3:0] current_state;
    reg [3:0] next_state;

    // Inicialização
    initial current_state = BUTTON_OFF;

    always @(posedge clk) begin
        current_state <= next_state;
    end

    always @(*) begin
        next_state = current_state;

        case (current_state)
            BUTTON_OFF: begin
                if (pulse_on_off) next_state = OFF;
            end

            BUTTON_ON: begin
                if (pulse_on_off) next_state = INIT;
            end
            
            BUTTON_SEND: begin
                if (pulse_send) next_state = DECODE;
            end

            OFF: begin
                if (~rst) next_state = BUTTON_ON;
            end
            
            INIT: begin
                if (LCD_done) 
                    next_state = IDLE;
            end

            IDLE: begin
                if (~send) next_state = BUTTON_SEND;
                else if (~rst) next_state = BUTTON_OFF;
            end

            DECODE: begin
                // Defaults
                DEST           = `ZERO;
                SRC1           = `ZERO;
                SRC2           = `ZERO;
                IMM_SIGN       = `POSITIVE;
                IMM_MAGNETUDE  = `ZERO;
                alu_func       = LOAD; // Default safe
                
                if (switches[17:15] == ADDI || switches[17:15] == SUBI || switches[17:15] == MUL) begin
                    DEST           = switches[14:11]; 
                    SRC1           = switches[10:7];  
                    IMM_SIGN       = switches[6];     
                    IMM_MAGNETUDE  = switches[5:0];
                    alu_func       = switches[17:15];
                end 
                else if (switches[17:15] == ADD || switches[17:15] == SUB) begin
                    DEST = switches[11:8]; 
                    SRC1 = switches[7:4];
                    SRC2 = switches[3:0];
                    alu_func = switches[17:15];
                end
                else if (switches[17:15] == LOAD) begin
                    DEST          = switches[10:7];
                    IMM_SIGN      = switches[6];
                    IMM_MAGNETUDE = switches[5:0];
                    alu_func      = LOAD;
                end
                else if (switches[17:15] == CLEAR || switches[17:15] == DISPLAY) begin
                    SRC1 = switches[3:0];
                    alu_func = switches[17:15];
                end
                next_state = EXECUTE;
            end

            EXECUTE: begin
                alu_enable   = `DISABLE;
                read_enable  = `DISABLE;
                write_enable = `DISABLE;
                clear_mem    = `DISABLE;

                if (alu_func == ADD  || alu_func == SUB || alu_func == MUL || 
                    alu_func == ADDI || alu_func == SUBI) begin
                        alu_enable   = `ENABLE;
                        read_enable  = `ENABLE;
                        write_enable = `ENABLE;                
                end
                else if (alu_func == LOAD) begin
                    write_enable = `ENABLE;
                end
                else if (alu_func == CLEAR) begin
                    clear_mem = `ENABLE;
                end
                else if (alu_func == DISPLAY) begin
                    read_enable = `ENABLE;
                end
                next_state = STORE;
            end

            STORE: begin
                // --- CORREÇÃO DE FLICKER ---
                // Forçamos os enables para 0. O pulso foi dado no EXECUTE.
                // Agora só esperamos o handshake terminar.
                alu_enable   = `DISABLE;
                read_enable  = `DISABLE;
                write_enable = `DISABLE;
                clear_mem    = `DISABLE;

                if (store_done) 
                    next_state = IDLE;
            end

            default: next_state = OFF;
        endcase
    end
endmodule

module debounce (
    input wire clk,
    input wire button_in,
    output wire button_pulse
);
    parameter COUNTER_MAX = 50000;

    reg [15:0] count;
    reg button_synced;

    // CORRIGIDO: posedge clk (minúsculo)
    always @(posedge clk) begin 
        if (button_in != button_synced) begin 
            if (count == COUNTER_MAX - 1) begin 
                button_synced <= button_in;
                count <= 0;
            end
            else begin
                count <= count + 1;
            end
        end
        else begin
            count <= 0;
        end
    end

    reg button_synced_prev;
    
    // CORRIGIDO: posedge clk (minúsculo)
    always @(posedge clk) begin 
        button_synced_prev <= button_synced;
    end
    
    assign button_pulse = (button_synced == 1'b1) && (button_synced_prev == 1'b0);
endmodule