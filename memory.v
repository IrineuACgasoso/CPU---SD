module memory (
    input  wire        clk,
    input  wire        rst,       // Reset (zera a memória)
    input  wire        we,        // Write Enable
    input  wire [3:0]  addr_wr,   // Endereço de escrita
    input  wire [3:0]  addr_rd1,  // Endereço de leitura 1
    input  wire [3:0]  addr_rd2,  // Endereço de leitura 2
    input  wire [15:0] data_in,   // Dado a escrever
    output wire [15:0] data_out1, // Dado lido 1
    output wire [15:0] data_out2  // Dado lido 2
);

    reg [15:0] RAM [0:15];
    integer i;

    // Leitura Assíncrona (dados disponíveis imediatamente)
    assign data_out1 = RAM[addr_rd1];
    assign data_out2 = RAM[addr_rd2];

    // Escrita Síncrona com Reset
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) begin
                RAM[i] <= 16'd0;
            end
        end else if (we) begin
            RAM[addr_wr] <= data_in;
        end
    end

endmodule