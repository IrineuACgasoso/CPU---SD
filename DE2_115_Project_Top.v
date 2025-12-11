module DE2_115_Project_Top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,      // KEY[0]=Power, KEY[1]=Send
    input  wire [17:0] SW,       // Instruções
    output wire [7:0]  LCD_DATA,
    output wire        LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_EN,
    output wire        LCD_ON,   
    output wire        LCD_BLON
);

    assign LCD_ON   = 1'b1;
    assign LCD_BLON = 1'b1;

    wire lcd_update_sig;
    wire [2:0] lcd_op;
    wire [3:0] lcd_reg;
    wire [15:0] lcd_val;
    wire lcd_is_busy;
    
    wire sys_rst;          
    wire show_splash_sig;  
    wire force_blank_sig;  
    
    // Invertemos aqui: 
    // Se apertar a tecla física (nível 0), btn torna-se 1.
    // Se soltar a tecla física (nível 1), btn torna-se 0.
    wire btn_power = !KEY[0];
    wire btn_send  = !KEY[1];

    module_mini_cpu cpu (
        .clk(CLOCK_50),
        .power_btn(btn_power),
        .send_btn(btn_send),
        .switches(SW),
        
        .sys_rst_out(sys_rst),
        .lcd_show_splash(show_splash_sig),
        .lcd_force_blank(force_blank_sig),
        
        .lcd_update(lcd_update_sig),
        .lcd_opcode(lcd_op),
        .lcd_reg_idx(lcd_reg),
        .lcd_value(lcd_val),
        .lcd_busy(lcd_is_busy)
    );

    lcd_custom_controller lcd_ctrl (
        .clk(CLOCK_50),
        .rst(sys_rst),         
        .update_req(lcd_update_sig),
        .show_splash(show_splash_sig),
        .force_blank(force_blank_sig),
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