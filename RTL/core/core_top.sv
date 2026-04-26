// just for verification:

module core_top ();
    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 32;
    localparam int AXI_ID_WIDTH   = 4;
    localparam int AXI_USER_WIDTH = 1;

    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH ),
        .AXI_DATA_WIDTH ( AXI_DATA_WIDTH ),
        .AXI_ID_WIDTH   ( AXI_ID_WIDTH   ),
        .AXI_USER_WIDTH ( AXI_USER_WIDTH )
    ) axi_slv_ports ();

    logic core_clk;
    logic bus_clk;
    logic reset;

    logic [31:0] d_addr;
    logic [3:0]  d_we;
    logic [31:0] d_wr_data;
    logic [31:0] d_rd_data;

    core cpu (
        .core_clk,
        .bus_clk,
        .rst(reset),
        .icache_port(axi_slv_ports),
        .d_addr,
        .d_we,
        .d_wr_data,
        .d_rd_data
    );

endmodule