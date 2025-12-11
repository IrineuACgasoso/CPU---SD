module lcd_init_hd44780 (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    output reg         done,
    output reg  [7:0]  lcd_data,
    output reg         lcd_rs,
    output reg         lcd_rw,
    output reg         lcd_e
);
    // Comandos HD44780
    localparam [7:0] CMD_FUNCTION_SET  = 8'h38;
    localparam [7:0] CMD_DISPLAY_ON    = 8'h0C;
    localparam [7:0] CMD_DISPLAY_CLEAR = 8'h01;
    localparam [7:0] CMD_ENTRY_MODE    = 8'h06;
    localparam integer NUM_CMDS = 4;

    // Delays de Inicialização
    localparam [31:0] DELAY_POWER_ON  = 32'd750_000;
    localparam [31:0] DELAY_STD_CMD   = 32'd2_000;
    localparam [31:0] DELAY_CLEAR_CMD = 32'd90_000;
    localparam [31:0] DELAY_PULSE_E   = 32'd50;

    localparam [2:0] S_IDLE=0, S_POWER_WAIT=1, S_SETUP=2, S_PULSE=3, S_WAIT=4, S_DONE=5;
    
    reg [2:0]  state, next_state;
    reg [31:0] delay_cnt, next_delay_cnt;
    reg [2:0]  cmd_idx, next_cmd_idx;
    reg [7:0] current_cmd;

    reg [7:0]  command_rom      [0:NUM_CMDS-1];
    reg [31:0] cmd_delay_rom    [0:NUM_CMDS-1];

    initial begin
        command_rom[0] = CMD_FUNCTION_SET;
        command_rom[1] = CMD_DISPLAY_ON;
        command_rom[2] = CMD_DISPLAY_CLEAR;
        command_rom[3] = CMD_ENTRY_MODE;
        cmd_delay_rom[0] = DELAY_STD_CMD;
        cmd_delay_rom[1] = DELAY_STD_CMD;
        cmd_delay_rom[2] = DELAY_CLEAR_CMD;
        cmd_delay_rom[3] = DELAY_STD_CMD;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE; delay_cnt <= 0; cmd_idx <= 0;
        end else begin
            state <= next_state; delay_cnt <= next_delay_cnt; cmd_idx <= next_cmd_idx;
        end
    end

    always @(*) begin
        next_state = state; next_delay_cnt = delay_cnt; next_cmd_idx = cmd_idx;
        case (state)
            S_IDLE: if (start) begin next_state = S_POWER_WAIT; next_delay_cnt = DELAY_POWER_ON; next_cmd_idx = 0; end
            S_POWER_WAIT: if (delay_cnt > 0) next_delay_cnt = delay_cnt - 1; else next_state = S_SETUP;
            S_SETUP: if (cmd_idx < NUM_CMDS) begin next_state = S_PULSE; next_delay_cnt = DELAY_PULSE_E; end else next_state = S_DONE;
            S_PULSE: if (delay_cnt > 0) next_delay_cnt = delay_cnt - 1; else begin next_state = S_WAIT; next_delay_cnt = cmd_delay_rom[cmd_idx]; end
            S_WAIT: if (delay_cnt > 0) next_delay_cnt = delay_cnt - 1; else begin next_cmd_idx = cmd_idx + 1; next_state = S_SETUP; end
            S_DONE: next_state = S_DONE;
            default: next_state = S_IDLE;
        endcase
    end

    always @(*) begin
        lcd_data = 0; lcd_rs = 0; lcd_rw = 0; lcd_e = 0; done = 0;
        current_cmd = (cmd_idx < NUM_CMDS) ? command_rom[cmd_idx] : 8'h00;
        case (state)
            S_SETUP: begin lcd_data = current_cmd; end
            S_PULSE: begin lcd_data = current_cmd; lcd_e = 1; end
            S_WAIT:  begin lcd_data = current_cmd; end
            S_DONE:  begin done = 1; end
        endcase
    end
endmodule