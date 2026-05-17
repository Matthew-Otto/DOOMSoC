module display_driver #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 32,
    parameter int ID_WIDTH     = 1
) (
    input  logic bus_clk,
    input  logic bus_clk_rst,
    input  logic p_clk,
    input  logic p_clk_rst,
    input  logic s_clk,

    output logic serial_pclk,
    output logic serial_blue,
    output logic serial_green,
    output logic serial_red,

    AXI_BUS.Slave s_axi
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
        if (p_clk_rst) begin
            x_count <= '0;
            y_count <= '0;
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
        end
    end

    ////////////////////////////////////////////////////////////////////////
    //// scaling ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    // scale 640x480 to 320x200 by duplicating pixels
    logic [15:0] frame_addr;
    logic [8:0] x_scaled;
    logic [7:0] y_scaled;
    
    assign x_scaled = x_count[9:1]; // x * 2
    assign y_scaled = (y_count * 1705) >> 12; // y * 2.4

    assign frame_addr = x_scaled + (y_scaled * 320);

    ////////////////////////////////////////////////////////////////////////
    //// framebuffer ///////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic [7:0]  color_idx;
    logic [23:0] pixel;

    frame_buffer #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) frame_buffer_i (
        .bus_clk,
        .bus_clk_rst,
        .p_clk,
        .p_clk_rst,
        .s_axi,
        .read_addr(frame_addr),
        .read_data(color_idx)
    );

    palette palette_i (
        .clk(p_clk),
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
        .reset(p_clk_rst),
        .de,
        .ctrl({vsync, hsync}),
        .color_value(blue_value),
        .encoded(blue_symbol)
    );
    tmds_encoder green_encoder (
        .p_clk,
        .reset(p_clk_rst),
        .de,
        .ctrl(2'b0),
        .color_value(green_value),
        .encoded(green_symbol)
    );
    tmds_encoder red_encoder (
        .p_clk,
        .reset(p_clk_rst),
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
        .reset(p_clk_rst),
        .symbol_data(10'b0000011111),
        .serial_out(serial_pclk)
    );
    tmds_serializer blue_serializer (
        .p_clk,
        .s_clk,
        .reset(p_clk_rst),
        .symbol_data(blue_symbol),
        .serial_out(serial_blue)
    );
    tmds_serializer green_serializer (
        .p_clk,
        .s_clk,
        .reset(p_clk_rst),
        .symbol_data(green_symbol),
        .serial_out(serial_green)
    );
    tmds_serializer red_serializer (
        .p_clk,
        .s_clk,
        .reset(p_clk_rst),
        .symbol_data(red_symbol),
        .serial_out(serial_red)
    );


endmodule : display_driver
