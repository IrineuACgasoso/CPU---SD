module DE2_115_Project_Top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,      // KEY[0]: Power, KEY[1]: Enviar
    input  wire [17:0] SW,       // Switches de configuração
    
    // Interface Física do LCD
    output wire [7:0]  LCD_DATA,
    output wire        LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_EN,
    output wire        LCD_ON,   
    output wire        LCD_BLON
);

    // Configuração de energia do LCD (Sempre ligado na placa)
    assign LCD_ON   = 1'b1;
    assign LCD_BLON = 1'b1;

    // Sinais de Controle entre CPU e LCD
    wire        cpu_lcd_start;
    wire [2:0]  cpu_lcd_opcode;
    wire [3:0]  cpu_lcd_reg_idx;
    wire [15:0] cpu_lcd_value;
    wire        lcd_is_busy;
    
    // Flags de Estado do Sistema
    wire system_reset;          
    wire is_splash_screen;  
    wire is_shutdown_screen;  
    
    // Inversão dos Botões (A placa envia 0 quando pressionado)
    // Convertemos para lógica positiva: 1 = Pressionado, 0 = Solto
    wire button_power = !KEY[0];
    wire button_send  = !KEY[1];

    // --- Instância da CPU ---
    module_mini_cpu cpu (
        .clk(CLOCK_50),
        .button_power(button_power),
        .button_send(button_send),
        .switches(SW),
        
        // Saídas de Controle
        .system_reset_out(system_reset),
        .show_splash_req(is_splash_screen),
        .force_blank_req(is_shutdown_screen),
        
        // Interface LCD
        .lcd_start(cpu_lcd_start),
        .lcd_opcode(cpu_lcd_opcode),
        .lcd_reg_index(cpu_lcd_reg_idx),
        .lcd_value(cpu_lcd_value),
        .lcd_busy(lcd_is_busy)
    );

    // --- Instância do Controlador de Display ---
    lcd_controller display_ctrl (
        .clk(CLOCK_50),
        .rst(system_reset),         
        
        // Comandos
        .start_update(cpu_lcd_start),
        .mode_splash(is_splash_screen),
        .mode_blank(is_shutdown_screen),
        
        // Dados
        .instruction_opcode(cpu_lcd_opcode),
        .register_index(cpu_lcd_reg_idx),
        .register_value(cpu_lcd_value),
        
        // Status e Saídas Físicas
        .busy_flag(lcd_is_busy),
        .lcd_data(LCD_DATA),
        .lcd_rs(LCD_RS),
        .lcd_rw(LCD_RW),
        .lcd_e(LCD_EN)
    );

endmodule