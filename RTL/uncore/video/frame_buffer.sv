module frame_buffer (
    input  logic        clk,
    input  logic        reset,

    input  logic [15:0] read_addr,
    output logic [7:0]  read_data
);

    // static image for now

    logic [7:0] rom [0:65535];

    initial begin
        $readmemh("frame_buffer.hex", rom);
    end

    always_ff @(posedge clk) begin
        read_data <= rom[read_addr];
    end

endmodule : frame_buffer
