module memory (
    input  wire        clk,
    input  wire        rst,         // Reset global (Power Off/Clear)
    input  wire        we,          // Write Enable
    input  wire [3:0]  write_addr,  // Endereço de Escrita
    input  wire [3:0]  read_addr_1, // Endereço de Leitura 1
    input  wire [3:0]  read_addr_2, // Endereço de Leitura 2
    input  wire [15:0] write_data,  // Dado para Escrita
    output wire [15:0] read_data_1, // Saída 1
    output wire [15:0] read_data_2  // Saída 2
);

    reg [15:0] RAM [0:15];
    integer i;

    // Leitura Assíncrona
    assign read_data_1 = RAM[read_addr_1];
    assign read_data_2 = RAM[read_addr_2];

    // Escrita Síncrona com Reset
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) begin
                RAM[i] <= 16'd0;
            end
        end else if (we) begin
            RAM[write_addr] <= write_data;
        end
    end
endmodule