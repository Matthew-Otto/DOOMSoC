module sdcard_axi_interface #(
    parameter BUS_CLK_FREQ,
    parameter SD_CLK_FREQ,
    parameter AXI_ADDR_WIDTH,
    parameter AXI_DATA_WIDTH,
    parameter AXI_ID_WIDTH,
    parameter AXI_USER_WIDTH
) (
    input  logic bus_clk,
    input  logic bus_clk_rst,
    input  logic sdcard_clk,
    input  logic sdcard_clk_rst,

    output logic       sd_clk,
    output logic       sd_clk_en,
    inout  logic       sd_cmd,
    inout  logic [3:0] sd_dat,

    AXI_BUS.Slave s_axi
);

    ////////////////////////////////////////////////////////////////////////
    //// Clocks ////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic sel_init_clk;
    logic init_clk;

    // very slow (400khz-100khz) SD card init clock generator
    clk_gen #(
        .INPUT_FREQ(SD_CLK_FREQ),
        .OUTPUT_FREQ(400_000)
    ) clk_gen_i (
        .clk_in(sdcard_clk),
        .rst(sdcard_clk_rst),
        .clk_out(init_clk)
    );


    assign sd_clk_gen = sel_init_clk ? init_clk : sdcard_clk;

    BUFG sd_clk_buf (
        .I(sd_clk_gen),
        .O(sd_clk)
    );

    logic sd_clk_rst;

    reset_sync sys_reset_gen (
        .async_reset(sdcard_clk_rst),
        .sync_clk(sd_clk),
        .sync_reset(sd_clk_rst)
    );


    ////////////////////////////////////////////////////////////////////////
    //// AXI Bus ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    AXI_BUS #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_USER_WIDTH (AXI_USER_WIDTH)
    ) axi_demux_ports [1:0] ();

    AXI_LITE #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) axi_lite_csr ();
    
    AXI_LITE #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) axi_lite_csr_cdc ();


    //// Route to Buffer or CSRs based on address
    logic aw_select;
    logic ar_select;

    // Address Decoder: 
    assign aw_select = (s_axi.aw_addr[11:0] >= 12'h400) ? 1'b1 : 1'b0;
    assign ar_select = (s_axi.ar_addr[11:0] >= 12'h400) ? 1'b1 : 1'b0;

    axi_demux_intf #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_USER_WIDTH (AXI_USER_WIDTH),
        .NO_MST_PORTS   (32'd2),
        .MAX_TRANS      (32'd1),
        .AXI_LOOK_BITS  (AXI_ID_WIDTH),
        .UNIQUE_IDS     (1'b1),
        .ATOP_SUPPORT   (1'b0)
    ) i_axi_demux (
        .clk_i           (bus_clk),
        .rst_ni          (~bus_clk_rst),
        .test_i          (1'b0),
        .slv_aw_select_i (aw_select),
        .slv_ar_select_i (ar_select),
        .slv             (s_axi),
        .mst             (axi_demux_ports)
    );

    //// Convert AXI4 full to AXI4-lite for CSRs
    axi_to_axi_lite_intf #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .AXI_MAX_WRITE_TXNS(32'd1),
        .AXI_MAX_READ_TXNS(32'd1),
        .FALL_THROUGH(1'b1),
        .FULL_BW(1'b1)
    ) axi_to_axilite (
        .clk_i(bus_clk),
        .rst_ni(~bus_clk_rst),
        .testmode_i(1'b0),
        .slv(axi_demux_ports[0]),
        .mst(axi_lite_csr)
    );

    // Move AXI lite bus to SD clock domain
    axi_lite_cdc_intf #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) csr_cdc (
        .src_clk_i(bus_clk),
        .src_rst_ni(~bus_clk_rst),
        .src(axi_lite_csr),
        .dst_clk_i(sd_clk),
        .dst_rst_ni(~sd_clk_rst),
        .dst(axi_lite_csr_cdc)
    );


    ////////////////////////////////////////////////////////////////////////
    //// Control / Status Registers ////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic        set_cs;
    logic        clear_cs;
    logic        write_block;
    logic        read_block;
    logic        busy;
    logic        success;
    logic        error;
    logic        spi_write;
    logic [7:0]  spi_data_wr;
    logic        spi_read;
    logic [7:0]  spi_data_rd;
    logic [31:0] block_addr;

    sd_csr sd_csr_i (
        .clk(sd_clk),
        .rst(sd_clk_rst),
        .s_axi(axi_lite_csr_cdc),
        .init_clk(sel_init_clk),
        .set_cs,
        .clear_cs,
        .block_write(write_block),
        .block_read(read_block),
        .busy,
        .success,
        .error,
        .spi_write,
        .spi_data_wr,
        .spi_read,
        .spi_data_rd,
        .sd_block_addr(block_addr)
    );


    ////////////////////////////////////////////////////////////////////////
    //// Block Buffer //////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    localparam BUFFER_ADDR_WIDTH = 8;

    logic [3:0]                   axi_wr_en;
    logic [BUFFER_ADDR_WIDTH-1:0] axi_buffer_addr;
    logic [AXI_DATA_WIDTH-1:0]    axi_wr_data, axi_rd_data;

    logic [3:0]                   sd_wr_en;
    logic [BUFFER_ADDR_WIDTH-1:0] sd_buffer_addr;
    logic [AXI_DATA_WIDTH-1:0]    sd_wr_data, sd_rd_data;

    axi_bram_intf #(
        .LOG_SIZE(BUFFER_ADDR_WIDTH),
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .ID_WIDTH(AXI_ID_WIDTH)
    ) axi_buffer_intf (
        .clk(bus_clk),
        .rst(bus_clk_rst),
        .s_axi(axi_demux_ports[1]),
        .rd_en(),
        .wr_en(axi_wr_en),
        .addr(axi_buffer_addr),
        .wr_data(axi_wr_data),
        .rd_data(axi_rd_data)
    );

    tdp_bram_be #(
        .ADDR_WIDTH(BUFFER_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) data_buffer (
        .clk_a(bus_clk),
        .addr_a(axi_buffer_addr),
        .wr_en_a(axi_wr_en),
        .wr_data_a(axi_wr_data),
        .rd_data_a(axi_rd_data),
        .clk_b(sd_clk),
        .addr_b(sd_buffer_addr),
        .wr_en_b(sd_wr_en),
        .wr_data_b(sd_wr_data),
        .rd_data_b(sd_rd_data)
    );


    ////////////////////////////////////////////////////////////////////////
    //// SD Card PHY ///////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic [9:0]  read_addr;
    logic [31:0] read_data;
    logic [9:0]  write_addr;
    logic [31:0] write_data;

    sdcard_spi_phy #(
        .ADDR_WIDTH(BUFFER_ADDR_WIDTH)
    ) sdcard_spi_phy_i (
        .clk(sd_clk),
        .rst(sd_clk_rst),
        .core_set_cs(set_cs),
        .core_clear_cs(clear_cs),
        .busy,
        .success,
        .error,
        .spi_send_byte(spi_write),
        .spi_wr_byte(spi_data_wr),
        .spi_byte_return(spi_read),
        .spi_rd_byte(spi_data_rd),

        .write_block,
        .read_block,
        .block_addr,

        .addr(sd_buffer_addr),
        .read_data(sd_rd_data),
        .write_en(sd_wr_en),
        .write_data(sd_wr_data),
        .sd_clk_en,
        .mosi(sd_cmd),
        .miso(sd_dat[0]),
        .cs(sd_dat[3])
    );

    assign sd_dat[2:1] = '0;

endmodule : sdcard_axi_interface

// decode address into two sections, one for CSR, one for buffer

/*
is_csr_access = (ADDR[11:8] == 4'h0)
is_bram_access = (ADDR[11:8] == 4'h8)
*/

// CTRL Registers
// 0x00,CTRL,W
// [0]: read (autoclear)
// [1]: write (autoclear)
// 0x04,STATUS,R
// [0]: read in progress
// [1]: write in progress
// [2]: block transfer complete
// [3]: error
// 0x08,SD_ADDR,R/W,The 32-bit block address to read/write on the SD Card.
// 0x0C,SPI_RAW,R/W,"Direct 8-bit TX/RX register for sending individual commands (CMD0, CMD8, etc.) during initialization."

// implement true dual port bram to buffer 512B blocks and cross clock domains


// act as axi interface
// CDC from bus_clk_freq to sdcard_freq
// FSM to init the sdcard