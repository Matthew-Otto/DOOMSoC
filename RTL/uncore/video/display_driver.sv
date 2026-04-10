module display_driver (
    input  logic clk,
    input  logic reset,

    output logic pclk,
    output logic blue,
    output logic green,
    output logic red
);

    ////////////////////////////////////////////////////////////////////////
    //// clk gen ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    (* keep = 1 *) logic p_clk; // pixel clock
    (* keep = 1 *) logic s_clk; // serializer clock (10 bit / p_clk) (DDR)

    // Serial clock generator
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
        .CLKIN(clk), // 27.0 MHz
        .CLKOUT(s_clk), // 126.0 MHz
        .LOCK()
    );

    // pixel clock generator
    CLKDIV #(
        .DIV_MODE("5")
    ) pclk_div_i (
        .HCLKIN(s_clk),
        .RESETN(~reset),
        .CALIB(1'b0),
        .CLKOUT(p_clk) // 25.2 MHz
    );


    ////////////////////////////////////////////////////////////////////////
    //// timing generator //////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    localparam H_ACTIVE     = 640;
    localparam H_FRONT      = 16;
    localparam H_SYNC       = 96;
    localparam H_BACK       = 48;
    localparam H_SYNC_START = H_ACTIVE + H_FRONT;
    localparam H_SYNC_END   = H_SYNC_START + H_SYNC;
    localparam H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK; // 800

    localparam V_ACTIVE     = 480;
    localparam V_FRONT      = 10;
    localparam V_SYNC       = 2;
    localparam V_BACK       = 33;
    localparam V_SYNC_START = V_ACTIVE + V_FRONT;
    localparam V_SYNC_END   = V_SYNC_START + V_SYNC;
    localparam V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK; // 525


    logic       de;
    logic       hsync;
    logic       vsync;

    logic [9:0] x_count, y_count;
    logic [9:0] x_pos, y_pos;


    always_ff @(posedge p_clk) begin
        if (reset) begin
            x_count <= '0;
            y_count <= '0;
            x_pos   <= '0;
            y_pos   <= '0;
            de      <= '0;
            hsync   <= '0;
            vsync   <= '0;
        end else begin
            if (x_count == H_TOTAL-1) begin
                x_count <= 0;
                if (y_count == V_TOTAL-1) begin
                    y_count <= 0;
                end else begin
                    y_count <= y_count + 1;
                end
            end else begin
                x_count <= x_count + 1;
            end

            de <= (x_count < H_ACTIVE) && (y_count < V_ACTIVE);
            
            hsync <= (x_count >= H_SYNC_START) && (x_count < H_SYNC_END);
            vsync <= (y_count >= V_SYNC_START) && (y_count < V_SYNC_END);
            
            x_pos <= x_count;
            y_pos <= y_count;
        end
    end

    ////////////////////////////////////////////////////////////////////////
    //// scaling ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    // scale 640x480 to 320x200 by duplicating pixels
    logic [15:0] frame_addr;
    logic [8:0] x_pos_scaled;
    logic [7:0] y_pos_scaled;
    
    
    // TODO convert this to LUT?
    assign y_pos_scaled = (y_pos * 1705) >> 12; // y * 2.4
    assign x_pos_scaled = x_pos[9:1]; // x * 2

    assign frame_addr = x_pos_scaled + (y_pos_scaled * 320);

    ////////////////////////////////////////////////////////////////////////
    //// framebuffer ///////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic [7:0]  color_idx;
    logic [23:0] pixel;

    frame_buffer frame_buffer_i (
        .clk(1'b0),
        .reset(1'b0),
        .read_addr(frame_addr),
        .read_data(color_idx)
    );

    palette palette_i (
        .clk(1'b0),
        .read_addr(color_idx),
        .read_data(pixel)
    );


    ////////////////////////////////////////////////////////////////////////
    //// TMDS encoders /////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic [7:0] blue_value, green_value, red_value;
    logic [9:0] blue_symbol, green_symbol, red_symbol;

    assign {red_value, green_value, blue_value} = pixel;

    tmds_encoder blue_encoder (
        .p_clk,
        .reset,
        .de,
        .ctrl({vsync, hsync}),
        .color_value(blue_value),
        .encoded(blue_symbol)
    );
    tmds_encoder green_encoder (
        .p_clk,
        .reset,
        .de,
        .ctrl(2'b0),
        .color_value(green_value),
        .encoded(green_symbol)
    );
    tmds_encoder red_encoder (
        .p_clk,
        .reset,
        .de,
        .ctrl(2'b0),
        .color_value(red_value),
        .encoded(red_symbol)
    );


    ////////////////////////////////////////////////////////////////////////
    //// serializers ///////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    // this seems silly but hopefully keeps the signals in phase with the clock
    tmds_serializer pclk_serializer (
        .p_clk,
        .s_clk,
        .reset,
        .symbol_data(10'b1111100000),
        .serial_out(pclk)
    );
    tmds_serializer blue_serializer (
        .p_clk,
        .s_clk,
        .reset,
        .symbol_data(blue_symbol),
        .serial_out(blue)
    );
    tmds_serializer gree_serializer (
        .p_clk,
        .s_clk,
        .reset,
        .symbol_data(green_symbol),
        .serial_out(green)
    );
    tmds_serializer red_serializer (
        .p_clk,
        .s_clk,
        .reset,
        .symbol_data(red_symbol),
        .serial_out(red)
    );


endmodule : display_driver
