module lcd_controller (
    input  wire        clk,
    input  wire        rst,
    
    // Comandos da CPU
    input  wire        start_update,    
    input  wire        mode_splash,   // Modo: Tela Inicial
    input  wire        mode_blank,    // Modo: Tela em Branco
    input  wire [2:0]  instruction_opcode,     
    input  wire [3:0]  register_index,    
    input  wire signed [15:0] register_value, 
    
    // Status
    output reg         busy_flag,          

    // Pinos Físicos
    output wire [7:0] lcd_data,
    output wire       lcd_rs,
    output wire       lcd_rw,
    output wire       lcd_e
);

    // --- Inicialização do Hardware HD44780 ---
    wire init_done;
    reg  trigger_init;
    wire [7:0] init_data_bus;
    wire init_rs, init_rw, init_e;

    lcd_init_hd44780 lcd_init_inst (
        .clk(clk), .rst(rst), .start(trigger_init), .done(init_done),
        .lcd_data(init_data_bus), .lcd_rs(init_rs), .lcd_rw(init_rw), .lcd_e(init_e)
    );

    // --- Multiplexador de Saída (Init vs Escrita) ---
    // CORREÇÃO: Declaramos como write_data_bus
    reg [7:0] write_data_bus;
    reg write_rs, write_e;
    
    assign lcd_data = (init_done) ? write_data_bus : init_data_bus;
    assign lcd_rs   = (init_done) ? write_rs       : init_rs;
    assign lcd_rw   = 1'b0; // Sempre escrita
    assign lcd_e    = (init_done) ? write_e        : init_e;

    // --- Buffer de Linha e Variáveis de Texto ---
    reg [7:0] lcd_buffer [0:31]; // 32 Caracteres (16x2)
    reg [15:0] absolute_value;
    reg [3:0]  digit_thou, digit_hund, digit_tens, digit_ones, digit_ten_thou; 
    integer i;

    // Função para converter Opcode em Texto
    function [39:0] get_opcode_string; 
        input [2:0] op;
        case(op)
            3'b000: get_opcode_string = "LOAD ";
            3'b001: get_opcode_string = "ADD  ";
            3'b010: get_opcode_string = "ADDI ";
            3'b011: get_opcode_string = "SUB  ";
            3'b100: get_opcode_string = "SUBI ";
            3'b101: get_opcode_string = "MUL  ";
            3'b110: get_opcode_string = "CLEAR"; 
            3'b111: get_opcode_string = "DPL  "; 
            default: get_opcode_string = "UNK  ";
        endcase
    endfunction
    reg [39:0] current_op_str;

    // --- Máquina de Estados ---
    localparam S_IDLE        = 0, 
               S_FORMAT_TEXT = 1, 
               S_CMD_CLEAR   = 2, S_WAIT_CLEAR   = 3, 
               S_WRITE_LINE1 = 4, 
               S_CMD_NEWLINE = 5, S_WAIT_NEWLINE = 6, 
               S_WRITE_LINE2 = 7, 
               S_PULSE_EN    = 8; 

    reg [3:0] state;
    reg [3:0] return_state; 
    reg [31:0] delay_counter;
    reg [5:0] char_pointer;

    // Tempos de Espera (Base clock 50MHz)
    localparam DELAY_PULSE = 32'd50;     
    localparam DELAY_CHAR  = 32'd2500;   
    localparam DELAY_CMD   = 32'd80000;  

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            trigger_init <= 0;
            busy_flag <= 1;
            write_e <= 0;
            char_pointer <= 0;
        end else begin
            if (!trigger_init && !init_done) trigger_init <= 1;

            case (state)
                S_IDLE: begin
                    write_e <= 0;
                    if (init_done) begin
                        busy_flag <= 0;
                        if (start_update) begin
                            busy_flag <= 1;
                            state <= S_FORMAT_TEXT;
                        end
                    end
                end

                // Formatação do Buffer de Texto (32 chars)
                S_FORMAT_TEXT: begin
                    // CASO 1: Tela em Branco
                    if (mode_blank) begin
                        for(i=0; i<32; i=i+1) lcd_buffer[i] = " "; 
                    end
                    
                    // CASO 2: Splash Screen
                    else if (mode_splash) begin
                        // L1: "----      [0000]"
                        lcd_buffer[0] = "-"; lcd_buffer[1] = "-"; 
                        lcd_buffer[2] = "-"; lcd_buffer[3] = "-";
                        for(i=4; i<10; i=i+1) lcd_buffer[i] = " ";
                        lcd_buffer[10] = "[";
                        lcd_buffer[11] = "0"; lcd_buffer[12] = "0";
                        lcd_buffer[13] = "0"; lcd_buffer[14] = "0";
                        lcd_buffer[15] = "]";
                        // L2: "          +00000"
                        for(i=16; i<26; i=i+1) lcd_buffer[i] = " "; 
                        lcd_buffer[26] = "+";
                        for(i=27; i<32; i=i+1) lcd_buffer[i] = "0";
                    end 
                    
                    // CASO 3: Instrução CLEAR (Só Texto)
                    else if (instruction_opcode == 3'b110) begin 
                        current_op_str = get_opcode_string(instruction_opcode); 
                        {lcd_buffer[0], lcd_buffer[1], lcd_buffer[2], lcd_buffer[3], lcd_buffer[4]} = current_op_str;
                        for(i=5; i<32; i=i+1) lcd_buffer[i] = " ";
                    end
                    
                    // CASO 4: Instrução Normal (Texto + Reg + Valor)
                    else begin 
                        current_op_str = get_opcode_string(instruction_opcode);
                        {lcd_buffer[0], lcd_buffer[1], lcd_buffer[2], lcd_buffer[3], lcd_buffer[4]} = current_op_str;
                        for(i=5; i<10; i=i+1) lcd_buffer[i] = " ";
                        
                        // Formata Registrador: [xxxx]
                        lcd_buffer[10] = "[";
                        lcd_buffer[11] = (register_index[3]) ? "1" : "0";
                        lcd_buffer[12] = (register_index[2]) ? "1" : "0";
                        lcd_buffer[13] = (register_index[1]) ? "1" : "0";
                        lcd_buffer[14] = (register_index[0]) ? "1" : "0";
                        lcd_buffer[15] = "]";

                        // Formata Valor: +00000
                        for(i=16; i<26; i=i+1) lcd_buffer[i] = " ";
                        
                        if (register_value[15] == 1'b1) begin
                            lcd_buffer[26] = "-"; absolute_value = -register_value;
                        end else begin
                            lcd_buffer[26] = "+"; absolute_value = register_value;
                        end
                        
                        // Conversão Binário -> Digitos ASCII
                        digit_ten_thou = (absolute_value/10000)%10; 
                        digit_thou     = (absolute_value/1000)%10;
                        digit_hund     = (absolute_value/100)%10; 
                        digit_tens     = (absolute_value/10)%10; 
                        digit_ones     = absolute_value%10;
                        
                        lcd_buffer[27] = {4'b0011, digit_ten_thou}; 
                        lcd_buffer[28] = {4'b0011, digit_thou};
                        lcd_buffer[29] = {4'b0011, digit_hund}; 
                        lcd_buffer[30] = {4'b0011, digit_tens};
                        lcd_buffer[31] = {4'b0011, digit_ones};
                    end
                    state <= S_CMD_CLEAR;
                end
                
                // --- Sequência de Escrita no LCD ---
                S_CMD_CLEAR: begin 
                    write_rs <= 0; write_data_bus <= 8'h01; write_e <= 1; // CORRIGIDO PARA write_data_bus
                    delay_counter <= DELAY_PULSE; state <= S_WAIT_CLEAR; 
                end
                
                S_WAIT_CLEAR: begin 
                    if (delay_counter > 0) begin delay_counter <= delay_counter - 1; if(delay_counter==DELAY_PULSE/2) write_e<=0; end 
                    else begin delay_counter <= DELAY_CMD; char_pointer <= 0; state <= S_WRITE_LINE1; end 
                end
                
                S_WRITE_LINE1: begin 
                    if (delay_counter > 0) delay_counter <= delay_counter - 1; 
                    else begin 
                        if (char_pointer < 16) begin 
                            write_rs <= 1; write_data_bus <= lcd_buffer[char_pointer]; // CORRIGIDO PARA write_data_bus
                            write_e <= 1; delay_counter <= DELAY_CHAR; 
                            char_pointer <= char_pointer + 1; 
                            return_state <= S_WRITE_LINE1; state <= S_PULSE_EN; 
                        end else state <= S_CMD_NEWLINE; 
                    end 
                end
                
                S_CMD_NEWLINE: begin 
                    write_rs <= 0; write_data_bus <= 8'hC0; write_e <= 1; // CORRIGIDO PARA write_data_bus
                    delay_counter <= DELAY_PULSE; state <= S_WAIT_NEWLINE; 
                end
                
                S_WAIT_NEWLINE: begin 
                    if (delay_counter > 0) begin delay_counter <= delay_counter - 1; if(delay_counter==DELAY_PULSE/2) write_e<=0; end 
                    else begin delay_counter <= DELAY_CHAR; state <= S_WRITE_LINE2; end 
                end
                
                S_WRITE_LINE2: begin 
                    if (delay_counter > 0) delay_counter <= delay_counter - 1; 
                    else begin 
                        if (char_pointer < 32) begin 
                            write_rs <= 1; write_data_bus <= lcd_buffer[char_pointer]; // CORRIGIDO PARA write_data_bus
                            write_e <= 1; delay_counter <= DELAY_CHAR; 
                            char_pointer <= char_pointer + 1; 
                            return_state <= S_WRITE_LINE2; state <= S_PULSE_EN; 
                        end else state <= S_IDLE; 
                    end 
                end
                
                S_PULSE_EN: begin 
                    if (delay_counter > 0) begin 
                        delay_counter <= delay_counter - 1; 
                        if(delay_counter == DELAY_PULSE/2) write_e <= 0; 
                    end else begin 
                        delay_counter <= DELAY_CHAR; state <= return_state; 
                    end 
                end
            endcase
        end
    end
endmodule