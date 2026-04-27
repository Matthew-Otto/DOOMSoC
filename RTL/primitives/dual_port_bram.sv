// Simple dual-port BRAM with write bypassing

module dual_port_bram #(
    ADDR_WIDTH=8,
    DATA_WIDTH=32
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  wr_en,
    input  logic [ADDR_WIDTH-1:0] write_addr,
    input  logic [DATA_WIDTH-1:0] write_data,
    input  logic [ADDR_WIDTH-1:0] read_addr,
    output logic [DATA_WIDTH-1:0] read_data
);

    localparam MEM_DEPTH = 1 << ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem [MEM_DEPTH-1:0];

    always_ff @(posedge clk) begin
        if (wr_en)
            mem[write_addr] <= write_data;
        
        if (rst)
            read_data <= '0;
        else
            read_data <= (wr_en && (read_addr == write_addr)) ? write_data : mem[read_addr];
    end

endmodule : dual_port_bram