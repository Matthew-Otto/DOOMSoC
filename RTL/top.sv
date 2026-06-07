// Top module for doomcore project

module top #(
    parameter string BOOT_ROM_FILE = "firmware/bin/bootloader.hex"
) (
    input  logic       clk,
    //input  logic       clk0,
    //input  logic       clk1,
    //input  logic       clk2,
    input  logic       btn1,
    input  logic       btn2,

    //input  logic       uart_rx,
    //output logic       uart_tx,

    // HDMI
    output logic tmds_clk_p, // pixel clock
    output logic tmds_d0_p,  // blue channel
    output logic tmds_d1_p,  // green channel
    output logic tmds_d2_p,  // red channel

    // SD Card
    output logic       sd_clk,
    inout  logic       sd_cmd,
    inout  logic [3:0] sd_dat,

    // Embedded SDRAM port names
    output logic        O_sdram_clk,
    output logic        O_sdram_cke,
    output logic        O_sdram_cs_n,     // chip select
    output logic        O_sdram_cas_n,    // columns address select
    output logic        O_sdram_ras_n,    // row address select
    output logic        O_sdram_wen_n,    // write enable
    inout  logic [31:0] IO_sdram_dq,      // 32 bit bidirectional data bus
    output logic [10:0] O_sdram_addr,     // 11 bit multiplexed address bus
    output logic [1:0]  O_sdram_ba,       // two banks
    output logic [3:0]  O_sdram_dqm,      // 32/4
    
    output logic [5:0] led
);

    ////////////////////////////////////////////////////////////////////////
    //// Clocks ////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic sys_clk;  // Main system clock
    logic sys_clk_gen;
    logic sdcard_clk;
    logic p_clk;    // HDMI pixel clock
    logic s_clk;    // HDMI serializer clock (10 bit / p_clk) (DDR)
    logic s_clk_gen;

    logic sys_pll_lock;
    logic sclk_pll_lock;

    localparam SYS_CLK_FREQ = 81_000_000;
    localparam SD_CLK_DIV = 4;
    localparam SD_CLK_FREQ = SYS_CLK_FREQ / SD_CLK_DIV;

`ifndef VERILATOR
    //// System Clock Generator
    rPLL #(
        .FCLKIN("27.0"),
        .DYN_SDIV_SEL(SD_CLK_DIV),
        .IDIV_SEL(0), // -> PFD = 27.0 MHz (range: 3-500 MHz)
        .FBDIV_SEL(2), // -> CLKOUT = 81.0 MHz (range: 3.90625-625 MHz)
        .ODIV_SEL(8) // -> VCO = 648.0 MHz (range: 500-1250 MHz)
    ) sysclk_pll (
        .CLKOUTP(),
        .CLKOUTD(sdcard_clk),
        .CLKOUTD3(),
        .RESET(1'b0),
        .RESET_P(1'b0),
        .CLKFB(1'b0),
        .FBDSEL(6'b0),
        .IDSEL(6'b0),
        .ODSEL(6'b0),
        .PSDA(4'b0),
        .DUTYDA(4'b0),
        .FDLY(4'b0),
        .CLKIN(clk),
        .CLKOUT(sys_clk_gen),
        .LOCK(sys_pll_lock)
    );

    BUFG sys_clk_buf (.I(sys_clk_gen), .O(sys_clk));

    //// Serial Clock Generator
    rPLL #(
        .FCLKIN("27.0"),
        .IDIV_SEL(2),   // -> PFD = 9.0 MHz (range: 3-500 MHz)
        .FBDIV_SEL(13), // -> CLKOUT = 126.0 MHz (range: 3.90625-625 MHz)
        .ODIV_SEL(4)    // -> VCO = 504.0 MHz (range: 500-1250 MHz)
    ) sclk_pll_i (
        .CLKOUTP(),
        .CLKOUTD(),
        .CLKOUTD3(),
        .RESET(1'b0),
        .RESET_P(1'b0),
        .CLKFB(1'b0),
        .FBDSEL(6'b0),
        .IDSEL(6'b0),
        .ODSEL(6'b0),
        .PSDA(4'b0),
        .DUTYDA(4'b0),
        .FDLY(4'b0),
        .CLKIN(clk),    // 27.0 MHz
        .CLKOUT(s_clk), // 126.0 MHz
        .LOCK(sclk_pll_lock)
    );

    //BUFG s_clk_buf (.I(s_clk_gen), .O(s_clk));

    //// Pixel Clock Generator
    CLKDIV #(
        .DIV_MODE("5")
    ) pclk_div_i (
        .HCLKIN(s_clk),
        .RESETN(sclk_pll_lock),
        .CALIB(1'b0),
        .CLKOUT(p_clk) // 25.2 MHz
    );
`endif



    ////////////////////////////////////////////////////////////////////////
    //// User IO ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic btn1_db;

`ifndef VERILATOR
    debounce #(
        .CLK_FREQ(SYS_CLK_FREQ),
        .PULSE(0)
    ) db_1 (
        .clk(sys_clk),
        .db_in(btn1),
        .db_out(btn1_db)
    );
`endif



    ////////////////////////////////////////////////////////////////////////
    //// Resets ////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic async_reset;
    logic sys_clk_rst;
    logic p_clk_rst;
    logic sdcard_clk_rst;

    logic reset_i;

    init_rst #(
        .DELAY(100)
    ) init_rst_i (
        .clk(sys_clk),
        .pll_lock(sys_pll_lock && sclk_pll_lock),
        .rst_out(reset_i)
    );

    assign async_reset = reset_i | btn1_db; 

    assign led[0] = ~sys_clk_rst;

    reset_sync sys_reset_gen (
        .async_reset(async_reset),
        .sync_clk(sys_clk),
        .sync_reset(sys_clk_rst)
    );

    reset_sync display_reset_gen (
        .async_reset(async_reset),
        .sync_clk(p_clk),
        .sync_reset(p_clk_rst)
    );

    reset_sync sdclk_reset_gen (
        .async_reset(async_reset),
        .sync_clk(sdcard_clk),
        .sync_reset(sdcard_clk_rst)
    );


    //// Manual Reset Duplication
    (* keep = "true" *) logic sys_clk_rst_core;
    (* keep = "true" *) logic sys_clk_rst_xbar_n;
    (* keep = "true" *) logic sys_clk_rst_sdram;
    (* keep = "true" *) logic sys_clk_rst_rom;
    (* keep = "true" *) logic sys_clk_rst_display;

    always_ff @(posedge sys_clk) begin
        sys_clk_rst_core <= sys_clk_rst;
        sys_clk_rst_xbar_n <= ~sys_clk_rst;
        sys_clk_rst_sdram <= sys_clk_rst;
        sys_clk_rst_rom <= sys_clk_rst;
        sys_clk_rst_display <= sys_clk_rst;
    end



    ////////////////////////////////////////////////////////////////////////
    //// Memory Bus ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    // Suppress assertions caused by random initialization until reset has deasserted
`ifdef VERILATOR
    initial begin
        $assertoff(0);
        @(posedge sys_clk_rst_xbar_n);
        $asserton(0);
    end
`endif
    
    `include "uncore/memory_bus/typedef.svh"
    `include "uncore/memory_bus/assign.svh"

    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 32;
    localparam int AXI_ID_WIDTH   = 1;
    localparam int AXI_USER_WIDTH = 1;

    // Generate AXI types using PULP macros
    `AXI_TYPEDEF_ALL(axi_bus, logic [AXI_ADDR_WIDTH-1:0], logic [AXI_ID_WIDTH-1:0], logic [AXI_DATA_WIDTH-1:0], logic [(AXI_DATA_WIDTH/8)-1:0], logic [AXI_USER_WIDTH-1:0])

    localparam axi_pkg::xbar_cfg_t XbarCfg = '{
        NoSlvPorts:         2, // 2 Masters
        NoMstPorts:         4, // 4 Slaves
        MaxMstTrans:        0, // Max outstanding transactions
        MaxSlvTrans:        1,
        FallThrough:        1'b1,
        LatencyMode:        axi_pkg::CUT_ALL_PORTS, // CUT_MST_PORTS
        PipelineStages:     32'd0,
        AxiIdWidthSlvPorts: AXI_ID_WIDTH,
        AxiIdUsedSlvPorts:  AXI_ID_WIDTH,
        UniqueIds:          1'b1,
        AxiAddrWidth:       AXI_ADDR_WIDTH,
        AxiDataWidth:       AXI_DATA_WIDTH,
        NoAddrRules:        4  // One rule per slave
    };

    localparam int AXI_MST_ID_WIDTH = AXI_ID_WIDTH + $clog2(XbarCfg.NoSlvPorts);

    // Define Address Routing Map
    typedef axi_pkg::xbar_rule_32_t rule_t; // 32-bit address rules

    // Define the base memory map
    localparam rule_t [XbarCfg.NoAddrRules-1:0] ADDR_MAP = '{
        '{idx: 0, start_addr: 32'h2000_0000, end_addr: 32'h2000_0FFF}, // Slave 0 (Boot ROM)
        '{idx: 1, start_addr: 32'h8000_0000, end_addr: 32'h807F_FFFF}, // Slave 1 (SDRAM Controller)
        '{idx: 2, start_addr: 32'h3000_0000, end_addr: 32'h3000_FFFF}, // Slave 2 (Frame Buffer)
        '{idx: 3, start_addr: 32'h4000_0000, end_addr: 32'h4000_07FF}  // Slave 3 (SD Card Interface)
    };


    AXI_BUS #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_USER_WIDTH (AXI_USER_WIDTH)
    ) axi_slv_ports [XbarCfg.NoSlvPorts-1:0] ();

    AXI_BUS #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH   (AXI_MST_ID_WIDTH),
        .AXI_USER_WIDTH (AXI_USER_WIDTH)
    ) axi_mst_ports [XbarCfg.NoMstPorts-1:0] ();

    axi_xbar_intf #(
        .AXI_USER_WIDTH (AXI_USER_WIDTH),
        .Cfg            (XbarCfg),
        .rule_t         (rule_t)
    ) i_axi_xbar (
        .clk_i                 (sys_clk),
        .rst_ni                (sys_clk_rst_xbar_n),
        .test_i                (1'b0),
        .slv_ports             (axi_slv_ports),
        .mst_ports             (axi_mst_ports),
        .addr_map_i            (ADDR_MAP),
        .en_default_mst_port_i (1'b0),
        .default_mst_port_i    ('0)
    );


    ////////////////////////////////////////////////////////////////////////
    //// CPU ///////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic vsync, vsync_core;

    core #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .ID_WIDTH(AXI_ID_WIDTH)
    ) cpu (
        .clk(sys_clk),
        .rst(sys_clk_rst_core),
        .timer_int(vsync_core),
        .icache_port(axi_slv_ports[0]),
        .dcache_port(axi_slv_ports[1])
    );

    slow_to_fast_cdc vsync_cdc (
        .clk(sys_clk),
        .data_in(vsync),
        .data_out(vsync_core)
    );


    ////////////////////////////////////////////////////////////////////////
    //// Bootloader ROM ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    axi4_boot_rom #(
        .LOG_SIZE(10),
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .ID_WIDTH(AXI_MST_ID_WIDTH),
        .BOOT_ROM_FILE(BOOT_ROM_FILE)
    ) bootrom_i (
        .clk(sys_clk),
        .reset(sys_clk_rst_rom),
        .s_axi(axi_mst_ports[0])
    );


    ////////////////////////////////////////////////////////////////////////
    //// RAM ///////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    sdram_axi_interface #(
        .CLK_FREQ(SYS_CLK_FREQ),
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .ID_WIDTH(AXI_MST_ID_WIDTH)
    ) sdram_i (
        .clk(sys_clk),
        .reset(sys_clk_rst_sdram),
        .s_axi(axi_mst_ports[1]),
        .O_sdram_clk,
        .O_sdram_cke,
        .O_sdram_ba,
        .O_sdram_addr,
        .O_sdram_cs_n,
        .O_sdram_ras_n,
        .O_sdram_cas_n,
        .O_sdram_wen_n,
        .IO_sdram_dq,
        .O_sdram_dqm
    );


    ////////////////////////////////////////////////////////////////////////
    //// Display ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    display_driver #(
        .ID_WIDTH(AXI_MST_ID_WIDTH)
    ) display_driver_i (
        .bus_clk(sys_clk),
        .bus_clk_rst(sys_clk_rst_display),
        .p_clk,
        .p_clk_rst,
        .s_clk,
        .vsync,
        .serial_pclk(tmds_clk_p),
        .serial_blue(tmds_d0_p),
        .serial_green(tmds_d1_p),
        .serial_red(tmds_d2_p),
        .s_axi(axi_mst_ports[2])
    );


    ////////////////////////////////////////////////////////////////////////
    //// SD Card Reader ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic sd_clk_prebuf;

    sdcard_axi_interface #(
        .BUS_CLK_FREQ(SYS_CLK_FREQ),
        .SD_CLK_FREQ(SD_CLK_FREQ),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_MST_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) sdcard_i (
        .bus_clk(sys_clk),
        .bus_clk_rst(sys_clk_rst_rom),
        .sdcard_clk,
        .sdcard_clk_rst,
        .sd_clk(sd_clk_prebuf),
        .sd_cmd,
        .sd_dat,
        .s_axi(axi_mst_ports[3])
    );

    ODDR sd_clk_io_driver (
        .D0(1'b1),
        .D1(1'b0),
        .TX(1'b0),
        .CLK(sd_clk_prebuf),
        .Q0(sd_clk),
        .Q1()
    );


    ////////////////////////////////////////////////////////////////////////
    //// Timer /////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    // interrupt_timer #(
    //     .CLK_FREQ(SYS_CLK_FREQ),
    //     .TIMER_US(28571)
    // ) interrupt_timer_i (
    //     .clk(sys_clk),
    //     .rst(sys_clk_rst_core),
    //     .interrupt(timer_int)
    // );


endmodule : top
