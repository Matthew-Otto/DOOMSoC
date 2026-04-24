module palette (
    input  logic        clk,
    input  logic [7:0]  read_addr,
    output logic [23:0] read_data
);

    // TODO write port for palette changes

    logic [23:0] rom [0:255];

    initial begin
        $readmemh("default_palette.txt", rom);
    end

    assign read_data = rom[read_addr];


endmodule : palette
