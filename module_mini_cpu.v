module module_mini_cpu (
    input wire clk,
    input wire reset_n,
    input wire power_on,           // Sinal de ligar/desligar
    input wire btn_enviar,         // Sinal de envio de instrução
    input wire [17:0] instrucao,   // Entrada dos switches
    // Interfaces para memória (RAM 16x16)
    output wire [3:0] mem_addr_write,
    output wire [3:0] mem_addr_read1,
    output wire [3:0] mem_addr_read2,
    output wire [15:0] mem_data_in,
    input  wire [15:0] mem_data_out1,
    input  wire [15:0] mem_data_out2,
    output wire mem_we,            // Habilita escrita
    // Interfaces para a ULA
    output wire [3:0] alu_op,
    output wire [15:0] alu_in1,
    output wire [15:0] alu_in2,
    input  wire [15:0] alu_result,
    // Sinal para LCD (para repasse de resultado/código ASCII)
    output reg [15:0] reg_result,     // Valor de saida para LCD
    output reg [3:0] reg_dest_addr,   // Endereço do destaque
    output reg [3:0] reg_opcode       // Opcode da última instrução processada
);

    // Aqui virá a implementação da FSM e decodificação das instruções
    // Para início, apenas a estrutura.

endmodule
