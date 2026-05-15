// Simple dual-port, dual-clock BRAM with write byte masking

module sdp_bram_be #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    // Write Port
    input  logic                      wr_clk,
    input  logic [(DATA_WIDTH/8)-1:0] wr_en,
    input  logic [ADDR_WIDTH-1:0]     wr_addr,
    input  logic [DATA_WIDTH-1:0]     wr_data,

    // Read Port
    input  logic                      rd_clk,
    input  logic [ADDR_WIDTH-1:0]     rd_addr,
    output logic [DATA_WIDTH-1:0]     rd_data
);

    logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    always_ff @(posedge wr_clk) begin
        for (int i = 0; i < (DATA_WIDTH/8); i=i+1) begin
            if (wr_en[i]) begin
                ram[wr_addr][i*8+:8] <= wr_data[i*8+:8];
            end
        end
    end

    always_ff @(posedge rd_clk) begin
        rd_data <= ram[rd_addr];
    end

endmodule : sdp_bram_be
