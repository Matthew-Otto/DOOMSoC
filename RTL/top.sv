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
    //// clocks ////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic sys_clk;   // main system clock
    logic sdram_clk; // sdram clock
    logic p_clk;     // HDMI pixel clock
    logic s_clk;     // HDMI serializer clock (10 bit / p_clk) (DDR)

    localparam SYS_CLOCK_FREQ = 329_400_000;
    localparam MEM_CLK_FREQ = 164_700_000;

    //// System Clock
`ifndef VERILATOR
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
        .CLKOUT(sys_clk), // 329.4 MHz
        .LOCK()
    );

    //// SDRAM clock generator
    CLKDIV #(
        .DIV_MODE("2")
    ) sdram_clk_div_i (
        .HCLKIN(sys_clk),
        .RESETN(1'b1),
        .CALIB(1'b0),
        .CLKOUT(sdram_clk) // 164.7 MHz
    );

    //// Serial clock generator
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

    //// Pixel clock generator
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
    //// user IO ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic btn1_db;

`ifndef VERILATOR
    debounce #(
        .CLK_FREQ(SYS_CLOCK_FREQ),
        .PULSE(1)
    ) db_1 (
        .clk(sys_clk),
        .db_in(btn1),
        .db_out(btn1_db)
    );
`endif

    ////////////////////////////////////////////////////////////////////////
    //// reset /////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic reset_i;
    logic main_reset;
    logic main_reset_long;
    logic sys_reset;
    logic sdram_reset;

    init_rst init_rst_i (
        .clk(sys_clk),
        .reset(reset_i)
    );

    assign main_reset = reset_i | btn1_db;

    pulse_stretcher #(
        .FACTOR(2)
    ) reset_smear (
        .clk(sys_clk),
        .pulse_in(main_reset),
        .pulse_out(main_reset_long)
    );


    assign sys_reset = main_reset_long;


    reset_sync sdram_reset_sync (
        .clk(sdram_clk),
        .async_reset(main_reset_long),
        .sync_reset(sdram_reset)
    );

    // one_bit_synchro sdram_reset_sync (
    //     .clk(sdram_clk),
    //     .data_in(sys_reset),
    //     .data_out(sdram_reset)
    // );


    // BOZO DEBUG
    logic test1;
    logic test2;
    always_ff @(posedge sys_clk)
        if (sys_reset)
            test1 <= ~test1;
    assign led[2] = test1;

    always_ff @(posedge sdram_clk)
        if (sdram_reset)
            test2 <= ~test2;
    assign led[4] = test2;


    ////////////////////////////////////////////////////////////////////////
    //// display ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    display_driver display_driver_i (
        .p_clk,
        .s_clk,
        .reset(sys_reset),
        .serial_pclk(tmds_clk_p),
        .serial_blue(tmds_d0_p),
        .serial_green(tmds_d1_p),
        .serial_red(tmds_d2_p)
    );



    ////////////////////////////////////////////////////////////////////////
    //// RAM ///////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic        cmd_ready;
    logic        stop;
    logic        read;
    logic        write;
    logic [3:0]  write_strb;
    logic [22:0] addr;
    logic [31:0] write_data;
    logic [31:0] read_data;
    logic        read_data_val;



    sdram_controller #(
        .MEM_CLK_FREQ(MEM_CLK_FREQ)
    ) mem_controller_i (
        .mem_clk(sdram_clk),
        .reset(1'b0), // BOZO
        .cmd_ready,
        .stop,
        .read,
        .write,
        .write_strb,
        .addr,
        .write_data,
        .read_data,
        .read_data_val,
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

    // core cpu (
    //     .clk(sys_clk),
    //     .rst(sys_reset),
    //     .i_addr(),
    //     .i_rd_data(),
    //     .d_addr(),
    //     .d_we(),
    //     .d_wr_data(),
    //     .d_rd_data()
    // );

    ///////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////

    logic btn2_db;
`ifndef VERILATOR
    debounce #(
        .CLK_FREQ(MEM_CLK_FREQ),
        .PULSE(1)
    ) db_2 (
        .clk(sdram_clk),
        .db_in(btn2),
        .db_out(btn2_db)
    );
`endif

    logic done;
    logic test_busy;
    logic test_pass;
    logic test_fail;

    assign led[1] = ~btn2;

    assign led[5] = ~test_pass;
    assign led[3] = ~test_fail;
    assign led[0] = ~test_busy;

    logic [31:0] lfsr;
    logic lfsr_feedback;

    assign lfsr_feedback = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];
    assign write_data = lfsr;

    enum {
        IDLE,
        WRITE,
        WRITE_BURST,
        READ,
        READ_BURST
    } mt_state;

    logic [31:0] counter;
    logic [3:0] burst_len;

    localparam MAX_ADDR = 1 << 10; // 1 << 21;

    assign addr = counter;

    always_ff @(posedge sdram_clk) begin
        if (sdram_reset) begin
            mt_state <= IDLE;
            counter <= 0;

            write <= 0;
            read <= 0;
            done <= 0;
        end else begin
            case (mt_state)
                IDLE : begin
                    if (btn2_db) begin
                        mt_state <= WRITE;
                        write <= 1;
                        write_strb <= 4'hf;
                    end
                end

                WRITE : begin
                    if (cmd_ready) begin
                        mt_state <= WRITE_BURST;
                        burst_len <= 6;
                    end
                end

                WRITE_BURST : begin
                    if (burst_len == 0) begin
                        if ((counter + 32) >= MAX_ADDR) begin
                            counter <= 0;
                            mt_state <= READ;
                            write <= 0;
                            read <= 1;
                        end else begin
                            mt_state <= WRITE;
                            counter <= counter + 32;
                        end
                    end else begin
                        burst_len <= burst_len - 1;
                    end
                end

                READ : begin
                    if (cmd_ready) begin
                        mt_state <= READ_BURST;
                        burst_len <= 6;
                    end
                end

                READ_BURST : begin
                    if (burst_len == 0) begin
                        if ((counter + 32) >= MAX_ADDR) begin
                            counter <= 0;
                            mt_state <= IDLE;
                            read <= 0;
                            done <= 1;
                        end else begin
                            mt_state <= READ;
                            counter <= counter + 32;
                        end
                    end else begin
                        burst_len <= burst_len - 1;
                    end
                end

                default : begin
                    mt_state <= IDLE;
                end
            endcase
        end
    end


    always_ff @(posedge sdram_clk) begin
        if (sdram_reset || (mt_state == READ && counter == 0)) begin
            lfsr <= 32'h12345678; 
        end else if ((mt_state == WRITE && cmd_ready) || mt_state == WRITE_BURST) begin
            lfsr <= {lfsr[30:0], lfsr_feedback};
        end else if (read_data_val) begin
            lfsr <= {lfsr[30:0], lfsr_feedback};
        end
    end

    always_ff @(posedge sdram_clk) begin
        if (sdram_reset) begin
            test_busy <= 0;
        end else if (btn2_db) begin
            test_busy <= 1;
        end

        if (sdram_reset) begin
            test_pass <= 0;
        end else if (done && ~test_fail) begin
            test_pass <= 1;
        end

        if (sdram_reset) begin
            test_fail <= 0;
        end else if (read_data_val && (lfsr != read_data)) begin
            test_fail <= 1;
        end
    end

endmodule : top
