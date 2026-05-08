// True dual-port, dual_clock bram with write byte masking

module dpdc_bram_be #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    // Port A
    input  logic                      clk_a,
    input  logic [ADDR_WIDTH-1:0]     addr_a,
    input  logic [(DATA_WIDTH/8)-1:0] wr_en_a,
    input  logic [DATA_WIDTH-1:0]     wr_data_a,
    output logic [DATA_WIDTH-1:0]     rd_data_a,

    // Port B
    input  logic                      clk_b,
    input  logic [ADDR_WIDTH-1:0]     addr_b,
    input  logic [(DATA_WIDTH/8)-1:0] wr_en_b,
    input  logic [DATA_WIDTH-1:0]     wr_data_b,
    output logic [DATA_WIDTH-1:0]     rd_data_b
);

    /* verilator lint_off MULTIDRIVEN */
    logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];
    /* verilator lint_on MULTIDRIVEN */

    // Port A Logic
    always_ff @(posedge clk_a) begin
        for (int i = 0; i < (DATA_WIDTH/8); i=i+1) begin
            if (wr_en_a[i])
                ram[addr_a][i*8+:8] <= wr_data_a[i*8+:8];    
            
            rd_data_a[i*8+:8] <= wr_en_a[i] ? wr_data_a[i*8+:8] : ram[addr_a][i*8+:8];
        end
    end

    // Port B Logic
    always_ff @(posedge clk_b) begin
        for (int i = 0; i < (DATA_WIDTH/8); i=i+1) begin
            if (wr_en_b[i])
                ram[addr_b][i*8+:8] <= wr_data_b[i*8+:8];

            rd_data_b[i*8+:8] <= wr_en_b[i] ? wr_data_b[i*8+:8] : ram[addr_b][i*8+:8];
        end
    end

endmodule : dpdc_bram_be
