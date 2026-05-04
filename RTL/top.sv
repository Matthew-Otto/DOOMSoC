// Top module for doomcore project

module top (
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

    logic core_clk;   // main system clock
    logic bus_clk; // sdram clock
    logic p_clk;     // HDMI pixel clock
    logic s_clk;     // HDMI serializer clock (10 bit / p_clk) (DDR)

    localparam CORE_CLK_FREQ = 329_400_000;
    localparam BUS_CLK_FREQ = 164_700_000;

`ifndef VERILATOR
    //// System Clock Generator
    rPLL #(
        .FCLKIN("27.0"),
        .IDIV_SEL(4),   // -> PFD = 5.4 MHz (range: 3-500 MHz)
        .FBDIV_SEL(60), // -> CLKOUT = 329.4 MHz (range: 3.90625-625 MHz)
        .ODIV_SEL(2)    // -> VCO = 658.8 MHz (range: 500-1250 MHz)
    ) sysclk_pll_i (
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
        .CLKIN(clk),      // 27.0 MHz
        .CLKOUT(core_clk), // 329.4 MHz
        .LOCK()
    );

    //// SDRAM Clock Generator
    CLKDIV #(
        .DIV_MODE("2")
    ) bus_clk_div_i (
        .HCLKIN(core_clk),
        .RESETN(1'b1),
        .CALIB(1'b0),
        .CLKOUT(bus_clk) // 164.7 MHz
    );

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
        .LOCK()
    );

    //// Pixel Clock Generator
    CLKDIV #(
        .DIV_MODE("5")
    ) pclk_div_i (
        .HCLKIN(s_clk),
        .RESETN(1'b1),
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
        .CLK_FREQ(CORE_CLK_FREQ),
        .PULSE(1)
    ) db_1 (
        .clk(core_clk),
        .db_in(btn1),
        .db_out(btn1_db)
    );
`endif



    ////////////////////////////////////////////////////////////////////////
    //// Reset /////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic reset_i;
    logic reset_agg;
    logic reset;

    init_rst init_rst_i (
        .clk(core_clk),
        .reset(reset_i)
    );

    assign reset_agg = reset_i | btn1_db;

    pulse_stretcher #(
        .FACTOR(2)
    ) reset_smear (
        .clk(core_clk),
        .pulse_in(reset_agg),
        .pulse_out(reset)
    );



    ////////////////////////////////////////////////////////////////////////
    //// Memory Bus ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    `include "uncore/memory_bus/typedef.svh"
    `include "uncore/memory_bus/assign.svh"

    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 32;
    localparam int AXI_ID_WIDTH   = 4;
    localparam int AXI_USER_WIDTH = 1;

    // Generate AXI types using PULP macros
    `AXI_TYPEDEF_ALL(axi_bus, logic [AXI_ADDR_WIDTH-1:0], logic [AXI_ID_WIDTH-1:0], logic [AXI_DATA_WIDTH-1:0], logic [(AXI_DATA_WIDTH/8)-1:0], logic [AXI_USER_WIDTH-1:0])

    localparam axi_pkg::xbar_cfg_t XbarCfg = '{
        NoSlvPorts:         2, // 2 Masters
        NoMstPorts:         2, // 4 Slaves // BOZO 4
        MaxMstTrans:        1, // Max outstanding transactions
        MaxSlvTrans:        1,
        FallThrough:        1'b0,
        LatencyMode:        axi_pkg::CUT_ALL_AX,
        PipelineStages:     32'd1,
        AxiIdWidthSlvPorts: AXI_ID_WIDTH,
        AxiIdUsedSlvPorts:  AXI_ID_WIDTH,
        UniqueIds:          1'b0,
        AxiAddrWidth:       AXI_ADDR_WIDTH,
        AxiDataWidth:       AXI_DATA_WIDTH,
        NoAddrRules:        2  // One rule per slave // BOZO 4
    };

    localparam int AXI_MST_ID_WIDTH = AXI_ID_WIDTH + $clog2(XbarCfg.NoSlvPorts);

    // Define Address Routing Map
    typedef axi_pkg::xbar_rule_32_t rule_t; // 32-bit address rules

    // Define the base memory map
    localparam rule_t [XbarCfg.NoAddrRules-1:0] ADDR_MAP = '{
        '{idx: 1, start_addr: 32'h8000_0000, end_addr: 32'h8000_FFFF}, // Slave 0 (Boot ROM)
        '{idx: 0, start_addr: 32'h0000_0000, end_addr: 32'h007F_FFFF} // Slave 1 (SDRAM Controller)
        //'{idx: 3'd2, start_addr: 32'h1000_0000, end_addr: 32'h1000_FFFF}, // Slave 2 (Frame Buffer)
        //'{idx: 3'd3, start_addr: 32'h2000_0000, end_addr: 32'h2000_FFFF}  // Slave 3 (SD Card Interface)
    };


    AXI_BUS #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_USER_WIDTH (AXI_USER_WIDTH)
    ) axi_slv_ports [XbarCfg.NoSlvPorts] ();

    AXI_BUS #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH   (AXI_MST_ID_WIDTH),
        .AXI_USER_WIDTH (AXI_USER_WIDTH)
    ) axi_mst_ports [XbarCfg.NoMstPorts] ();

    axi_xbar_intf #(
        .AXI_USER_WIDTH (AXI_USER_WIDTH),
        .Cfg            (XbarCfg),
        .rule_t         (rule_t)
    ) i_axi_xbar (
        .clk_i                 (bus_clk),
        .rst_ni                (~reset),
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

    core cpu (
        .core_clk,
        .bus_clk,
        .rst(reset),
        .icache_port(axi_slv_ports[0]),
        .dcache_port(axi_slv_ports[1])
    );


    ////////////////////////////////////////////////////////////////////////
    //// Bootloader ROM ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    axi4_boot_rom #(
        .LOG_SIZE(12),
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .ID_WIDTH(AXI_MST_ID_WIDTH)
    ) bootrom_i (
        .clk(bus_clk),
        .reset,
        .s_axi(axi_mst_ports[0])
    );


    ////////////////////////////////////////////////////////////////////////
    //// RAM ///////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    sdram_axi_interface #(
        .MEM_CLK_FREQ(BUS_CLK_FREQ),
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .ID_WIDTH(AXI_MST_ID_WIDTH)
    ) sdram_i (
        .mem_clk(bus_clk),
        .reset,
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

    // display_driver display_driver_i (
    //     .p_clk,
    //     .s_clk,
    //     .reset(reset),
    //     .serial_pclk(tmds_clk_p),
    //     .serial_blue(tmds_d0_p),
    //     .serial_green(tmds_d1_p),
    //     .serial_red(tmds_d2_p)
    // );
    // axi_mst_ports[2]


    ////////////////////////////////////////////////////////////////////////
    //// SD Card Reader ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    // axi_mst_ports[3]








endmodule : top
