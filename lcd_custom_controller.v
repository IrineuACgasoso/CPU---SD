module lcd_custom_controller (
    input  wire        clk,
    input  wire        rst,
    
    // Interface com a CPU
    input  wire        update_req,    
    input  wire [2:0]  opcode_in,     
    input  wire [3:0]  reg_idx_in,    
    input  wire signed [15:0] value_in, 
    output reg         busy,          

    // Pinos físicos do LCD
    output wire [7:0] lcd_data,
    output wire       lcd_rs,
    output wire       lcd_rw,
    output wire       lcd_e
);

    // --- Inicialização ---
    wire init_done;
    reg  start_init;
    wire [7:0] init_data;
    wire init_rs, init_rw, init_e;

    lcd_init_hd44780 lcd_init_inst (
        .clk(clk), .rst(rst), .start(start_init), .done(init_done),
        .lcd_data(init_data), .lcd_rs(init_rs), .lcd_rw(init_rw), .lcd_e(init_e)
    );

    // --- Mux de Saída ---
    reg [7:0] wr_data;
    reg wr_rs, wr_e;
    
    assign lcd_data = (init_done) ? wr_data : init_data;
    assign lcd_rs   = (init_done) ? wr_rs   : init_rs;
    assign lcd_rw   = 1'b0; 
    assign lcd_e    = (init_done) ? wr_e    : init_e;

    // --- Buffer de Linha (32 caracteres) ---
    reg [7:0] line_buffer [0:31]; 
    reg [15:0] abs_val;
    reg [3:0]  thou, hund, tens, ones, ten_thou; 
    integer i;

    // Função Opcode String
    function [39:0] get_op_str; 
        input [2:0] op;
        case(op)
            3'b000: get_op_str = "LOAD ";
            3'b001: get_op_str = "ADD  ";
            3'b010: get_op_str = "ADDI ";
            3'b011: get_op_str = "SUB  ";
            3'b100: get_op_str = "SUBI ";
            3'b101: get_op_str = "MUL  ";
            3'b110: get_op_str = "CLEAR"; 
            3'b111: get_op_str = "DSPLY"; 
            default: get_op_str = "UNK  ";
        endcase
    endfunction
    reg [39:0] op_string;

    // --- FSM ---
    // Novos estados separados para garantir a quebra de linha
    localparam S_IDLE        = 0, 
               S_FORMAT      = 1, 
               S_CMD_CLEAR   = 2, 
               S_WAIT_CLEAR  = 3, 
               S_WRITE_L1    = 4, // Escreve linha 1
               S_CMD_NEWLINE = 5, // Pula linha
               S_WAIT_NEWLINE= 6,
               S_WRITE_L2    = 7, // Escreve linha 2
               S_PULSE       = 8; // Pulso genérico

    reg [3:0] state;
    reg [3:0] return_state; // Para saber pra onde voltar depois do pulso
    reg [31:0] delay_cnt;
    reg [5:0] char_ptr;

    // Delays
    localparam D_PULSE = 32'd50;     // 1us
    localparam D_CHAR  = 32'd2500;   // 50us
    localparam D_CMD   = 32'd80000;  // 1.6ms (Clear e NewLine precisam de tempo)

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            start_init <= 0;
            busy <= 1;
            wr_e <= 0;
            char_ptr <= 0;
        end else begin
            if (!start_init && !init_done) start_init <= 1;

            case (state)
                S_IDLE: begin
                    wr_e <= 0;
                    if (init_done) begin
                        busy <= 0;
                        if (update_req) begin
                            busy <= 1;
                            state <= S_FORMAT;
                        end
                    end
                end

                // --- 1. Formata os dados no Buffer ---
                S_FORMAT: begin
                    // Linha 1: "OPCOD       [REG_]"
                    op_string = get_op_str(opcode_in);
                    {line_buffer[0], line_buffer[1], line_buffer[2], line_buffer[3], line_buffer[4]} = op_string;
                    for(i=5; i<10; i=i+1) line_buffer[i] = " ";
                    
                    line_buffer[10] = "[";
                    line_buffer[11] = (reg_idx_in[3]) ? "1" : "0";
                    line_buffer[12] = (reg_idx_in[2]) ? "1" : "0";
                    line_buffer[13] = (reg_idx_in[1]) ? "1" : "0";
                    line_buffer[14] = (reg_idx_in[0]) ? "1" : "0";
                    line_buffer[15] = "]";

                    // Linha 2: "          +DDDDD"
                    for(i=16; i<26; i=i+1) line_buffer[i] = " ";
                    
                    if (value_in[15] == 1'b1) begin
                        line_buffer[26] = "-"; abs_val = -value_in;
                    end else begin
                        line_buffer[26] = "+"; abs_val = value_in;
                    end

                    ten_thou = (abs_val/10000)%10; thou = (abs_val/1000)%10;
                    hund = (abs_val/100)%10; tens = (abs_val/10)%10; ones = abs_val%10;

                    line_buffer[27] = {4'b0011, ten_thou}; line_buffer[28] = {4'b0011, thou};
                    line_buffer[29] = {4'b0011, hund}; line_buffer[30] = {4'b0011, tens};
                    line_buffer[31] = {4'b0011, ones};
                    
                    state <= S_CMD_CLEAR;
                end

                // --- 2. Limpa a tela ---
                S_CMD_CLEAR: begin
                    wr_rs <= 0; wr_data <= 8'h01; wr_e <= 1;
                    delay_cnt <= D_PULSE;
                    state <= S_WAIT_CLEAR;
                end

                S_WAIT_CLEAR: begin
                    if (delay_cnt > 0) begin delay_cnt <= delay_cnt - 1; if(delay_cnt==D_PULSE/2) wr_e<=0; end
                    else begin 
                        delay_cnt <= D_CMD; // Espera LCD limpar
                        char_ptr <= 0; 
                        state <= S_WRITE_L1; // Vai para Linha 1
                    end
                end

                // --- 3. Escreve Linha 1 (Chars 0 a 15) ---
                S_WRITE_L1: begin
                    if (delay_cnt > 0) delay_cnt <= delay_cnt - 1;
                    else begin
                        if (char_ptr < 16) begin
                            wr_rs <= 1; wr_data <= line_buffer[char_ptr];
                            wr_e <= 1; delay_cnt <= D_PULSE;
                            char_ptr <= char_ptr + 1;
                            return_state <= S_WRITE_L1; // Volta pra cá
                            state <= S_PULSE;
                        end else begin
                            // Terminou linha 1, manda pular linha
                            state <= S_CMD_NEWLINE;
                        end
                    end
                end

                // --- 4. Comando Pular Linha (0xC0) ---
                S_CMD_NEWLINE: begin
                    wr_rs <= 0; wr_data <= 8'hC0; wr_e <= 1; // Endereço 0x40 (Linha 2)
                    delay_cnt <= D_PULSE;
                    state <= S_WAIT_NEWLINE;
                end

                S_WAIT_NEWLINE: begin
                    if (delay_cnt > 0) begin delay_cnt <= delay_cnt - 1; if(delay_cnt==D_PULSE/2) wr_e<=0; end
                    else begin 
                        delay_cnt <= D_PULSE; // Pequeno delay extra
                        state <= S_WRITE_L2; 
                        // char_ptr já está em 16 vindo do loop anterior
                    end
                end

                // --- 5. Escreve Linha 2 (Chars 16 a 31) ---
                S_WRITE_L2: begin
                    if (delay_cnt > 0) delay_cnt <= delay_cnt - 1;
                    else begin
                        if (char_ptr < 32) begin
                            wr_rs <= 1; wr_data <= line_buffer[char_ptr];
                            wr_e <= 1; delay_cnt <= D_PULSE;
                            char_ptr <= char_ptr + 1;
                            return_state <= S_WRITE_L2; // Volta pra cá
                            state <= S_PULSE;
                        end else begin
                            state <= S_IDLE; // Terminou tudo
                        end
                    end
                end

                // --- Estado Genérico de Pulso ---
                S_PULSE: begin
                    if (delay_cnt > 0) begin 
                        delay_cnt <= delay_cnt - 1; 
                        if(delay_cnt == D_PULSE/2) wr_e <= 0; // Borda de descida do Enable
                    end else begin 
                        delay_cnt <= D_CHAR; // Espera char ser processado
                        state <= return_state; // Volta para o loop que chamou (L1 ou L2)
                    end
                end

            endcase
        end
    end
endmodule