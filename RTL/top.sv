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

    output logic tmds_clk_p, // pixel clock
    output logic tmds_d0_p,  // blue channel
    output logic tmds_d1_p,  // green channel
    output logic tmds_d2_p,  // red channel
    
    output logic [5:0] led
);

    ////////////////////////////////////////////////////////////////////////
    //// user IO ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic btn1_db;

    debounce #(
        .CLK_FREQ(100000000),
        .PULSE(1)
    ) db_1 (
        .clk(clk),
        .db_in(btn1),
        .db_out(btn1_db)
    );

    ////////////////////////////////////////////////////////////////////////
    //// reset /////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic reset;
    logic reset_i;

    init_rst init_rst_i (
        .clk(clk),
        .reset(reset_i)
    );

    assign reset = reset_i | btn1_db;


    ////////////////////////////////////////////////////////////////////////
    //// display ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    display_driver display_driver_i (
        .clk,
        .reset,
        .pclk(tmds_clk_p),
        .blue(tmds_d0_p),
        .green(tmds_d1_p),
        .red(tmds_d2_p)
    );

endmodule : top
