module DE2_115_Project_Top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,      // KEY[0]=Reset, KEY[1]=Send
    input  wire [17:0] SW,       // Instruções
    // LCD Interface
    output wire [7:0]  LCD_DATA,
    output wire        LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_EN,
    output wire        LCD_ON,   // Liga backlight/power
    output wire        LCD_BLON
);

    // Configurações fixas DE2-115
    assign LCD_ON   = 1'b1;
    assign LCD_BLON = 1'b1;

    // Sinais de Conexão
    wire lcd_update_sig;
    wire [2:0] lcd_op;
    wire [3:0] lcd_reg;
    wire [15:0] lcd_val;
    wire lcd_is_busy;
    
    // Inversão do Reset (Botão pressionado = 0, Lógica = 1)
    wire sys_rst = !KEY[0];

    // Instância da CPU
    module_mini_cpu cpu (
        .clk(CLOCK_50),
        .rst(sys_rst),
        .send_btn(KEY[1]), // Passamos direto, borda tratada dentro
        .switches(SW),
        .lcd_update(lcd_update_sig),
        .lcd_opcode(lcd_op),
        .lcd_reg_idx(lcd_reg),
        .lcd_value(lcd_val),
        .lcd_busy(lcd_is_busy)
    );

    // Instância do Controlador LCD
    lcd_custom_controller lcd_ctrl (
        .clk(CLOCK_50),
        .rst(sys_rst),
        .update_req(lcd_update_sig),
        .opcode_in(lcd_op),
        .reg_idx_in(lcd_reg),
        .value_in(lcd_val),
        .busy(lcd_is_busy),
        .lcd_data(LCD_DATA),
        .lcd_rs(LCD_RS),
        .lcd_rw(LCD_RW),
        .lcd_e(LCD_EN)
    );

endmodule