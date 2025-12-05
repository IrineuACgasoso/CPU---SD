module memory (
    input wire clk,
    input wire reset_n,
    input wire we,                     // Habilita escrita
    input wire [3:0] addr_write,
    input wire [3:0] addr_read1,       // Leitura 1
    input wire [3:0] addr_read2,       // Leitura 2
    input wire [15:0] data_in,         // Dados de escrita
    output reg [15:0] data_out1,       // Saída leitura 1
    output reg [15:0] data_out2        // Saída leitura 2
);

    reg [15:0] mem [15:0]; // 16 registradores de 16 bits
    integer i;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 16; i = i + 1)
                mem[i] <= 16'd0;
        end else if (we) begin
            mem[addr_write] <= data_in;
        end
    end

    always @(posedge clk) begin
        data_out1 <= mem[addr_read1];
        data_out2 <= mem[addr_read2];
    end

endmodule
