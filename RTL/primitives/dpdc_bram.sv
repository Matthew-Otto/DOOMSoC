// True dual-port, dual_clock bram

module dpdc_bram #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    // Port A
    input  logic                  clk_a,
    input  logic [ADDR_WIDTH-1:0] addr_a,
    input  logic                  wr_en_a,
    input  logic [DATA_WIDTH-1:0] wr_data_a,
    output logic [DATA_WIDTH-1:0] rd_data_a,

    // Port B
    input  logic                  clk_b,
    input  logic [ADDR_WIDTH-1:0] addr_b,
    input  logic                  wr_en_b,
    input  logic [DATA_WIDTH-1:0] wr_data_b,
    output logic [DATA_WIDTH-1:0] rd_data_b
);

    /* verilator lint_off MULTIDRIVEN */
    logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];
    /* verilator lint_on MULTIDRIVEN */

    // Port A Logic
    always_ff @(posedge clk_a) begin
        if (wr_en_a)
            ram[addr_a] <= wr_data_a;

        rd_data_a <= wr_en_a ? wr_data_a : ram[addr_a];
    end

    // Port B Logic
    always_ff @(posedge clk_b) begin
        if (wr_en_b)
            ram[addr_b] <= wr_data_b;

        rd_data_b <= wr_en_b ? wr_data_b : ram[addr_b];
    end

endmodule : dpdc_bram
