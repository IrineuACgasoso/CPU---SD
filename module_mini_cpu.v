module module_mini_cpu (
    input  wire        clk,
    input  wire        power_btn,    // 1 = Pressionado, 0 = Solto
    input  wire        send_btn,     // 1 = Pressionado, 0 = Solto
    input  wire [17:0] switches,     
    
    output reg         sys_rst_out,     
    output reg         lcd_show_splash, 
    output reg         lcd_force_blank, 
    
    output reg         lcd_update,
    output reg [2:0]   lcd_opcode,
    output reg [3:0]   lcd_reg_idx,
    output reg [15:0]  lcd_value,
    input  wire        lcd_busy
);

    // --- Decodificação ---
    wire [2:0] opcode = switches[17:15];
    wire [3:0] r_dest = switches[14:11]; 
    wire [3:0] r_src1 = switches[10:7];  
    wire [3:0] r_src2 = switches[6:3];   
    wire [6:0] imm7   = switches[6:0];  
    wire [10:0] imm11 = switches[10:0]; 

    // --- Sinais Internos ---
    reg mem_we;
    reg [15:0] mem_data_wr;
    wire [15:0] mem_out1, mem_out2;
    reg [15:0] alu_in_a, alu_in_b;
    wire signed [15:0] alu_result;
    
    reg instr_clear_rst; 
    wire memory_reset = sys_rst_out || instr_clear_rst;

    // Lógica de Leitura (Display vs Normal)
    wire [3:0] addr_read_src1;
    assign addr_read_src1 = (opcode == 3'b111) ? r_dest : r_src1;

    // --- DETECTOR DE BORDA (SOLTAR O BOTÃO) ---
    reg btn_send_prev, btn_power_prev;
    
    always @(posedge clk) begin
        btn_send_prev <= send_btn;
        btn_power_prev <= power_btn;
    end

    // A mágica acontece aqui:
    // O botão foi solto SE: No ciclo anterior estava apertado (1) E agora está solto (0)
    wire send_released_event = (btn_send_prev == 1'b1 && send_btn == 1'b0);
    wire power_released_event = (btn_power_prev == 1'b1 && power_btn == 1'b0);

    // --- Instâncias ---
    memory mem_inst (
        .clk(clk), .rst(memory_reset), .we(mem_we), 
        .addr_wr(r_dest), .data_in(mem_data_wr),
        .addr_rd1(addr_read_src1),
        .addr_rd2(r_src2),
        .data_out1(mem_out1), .data_out2(mem_out2)
    );

    module_alu alu_inst (
        .opcode(opcode), .A(alu_in_a), .B(alu_in_b), .result(alu_result)
    );

    // --- FSM ---
    localparam S_OFF=0, S_WAIT_INIT=1, S_STARTUP=2, S_IDLE=3, 
               S_EXECUTE=4, S_LATCH=5, S_SHUTDOWN=6, S_UPDATE_LCD=7, S_WAIT_LCD=8;
               
    reg [3:0] state = S_OFF;
    reg [15:0] busy_wait_cnt; 

    always @(posedge clk) begin
        instr_clear_rst <= 0; 
        case (state)
            // 1. DESLIGADO
            S_OFF: begin
                sys_rst_out <= 1; mem_we <= 0; lcd_update <= 0; 
                lcd_show_splash <= 0; lcd_force_blank <= 0; busy_wait_cnt <= 0;
                
                // Só liga quando SOLTAR o botão de power
                if (power_released_event) begin 
                    sys_rst_out <= 0; 
                    state <= S_WAIT_INIT; 
                end
            end

            // 2. WAIT INIT
            S_WAIT_INIT: begin
                if (busy_wait_cnt < 1000) busy_wait_cnt <= busy_wait_cnt + 1;
                else if (!lcd_busy) state <= S_STARTUP;
            end

            // 3. STARTUP
            S_STARTUP: begin lcd_show_splash <= 1; state <= S_UPDATE_LCD; end

            // 4. IDLE
            S_IDLE: begin
                mem_we <= 0; lcd_update <= 0; lcd_show_splash <= 0; lcd_force_blank <= 0;
                
                // Só desliga quando SOLTAR o botão 
                if (power_released_event) begin
                    state <= S_SHUTDOWN;
                end
               // Só envia instrução quando SOLTAR o botão 
                else if (send_released_event) begin
                    state <= S_EXECUTE;
                end
            end
            
            // 5. SHUTDOWN
            S_SHUTDOWN: begin lcd_force_blank <= 1; state <= S_UPDATE_LCD; end
            
            // 6. EXECUTE
            S_EXECUTE: begin
                case (opcode)
                    3'b000: begin alu_in_a <= 0; alu_in_b <= {{5{imm11[10]}}, imm11}; end 
                    3'b001, 3'b011, 3'b101: begin alu_in_a <= mem_out1; alu_in_b <= mem_out2; end 
                    3'b010, 3'b100: begin alu_in_a <= mem_out1; alu_in_b <= {{9{imm7[6]}}, imm7}; end 
                    3'b110: begin alu_in_a <= 0; alu_in_b <= 0; instr_clear_rst <= 1; end 
                    3'b111: begin alu_in_a <= mem_out1; alu_in_b <= 0; end 
                    default: begin alu_in_a <= 0; alu_in_b <= 0; end
                endcase
                state <= S_LATCH;
            end

            // 7. LATCH
            S_LATCH: begin
                if (opcode != 3'b111 && opcode != 3'b110) begin 
                    mem_we <= 1; mem_data_wr <= alu_result;
                end
                lcd_opcode <= opcode; lcd_reg_idx <= r_dest; lcd_value <= alu_result;
                state <= S_UPDATE_LCD;
            end

            // 8. UPDATE LCD
            S_UPDATE_LCD: begin mem_we <= 0; lcd_update <= 1; busy_wait_cnt <= 0; state <= S_WAIT_LCD; end

            // 9. WAIT LCD
            S_WAIT_LCD: begin
                lcd_update <= 0; 
                if (busy_wait_cnt < 15) busy_wait_cnt <= busy_wait_cnt + 1;
                else if (!lcd_busy) begin
                    if (lcd_force_blank) state <= S_OFF;
                    else state <= S_IDLE;
                end
            end
        endcase
    end
endmodule