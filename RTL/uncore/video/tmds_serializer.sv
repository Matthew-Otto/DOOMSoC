module tmds_serializer (
    input  logic       p_clk,
    input  logic       s_clk,
    input  logic       reset,
    input  logic [9:0] symbol_data,
    
    output logic       serial_out
);

    OSER10 oser_inst (
        .Q(serial_out),
        .D0(symbol_data[0]),
        .D1(symbol_data[1]),
        .D2(symbol_data[2]),
        .D3(symbol_data[3]),
        .D4(symbol_data[4]),
        .D5(symbol_data[5]),
        .D6(symbol_data[6]),
        .D7(symbol_data[7]),
        .D8(symbol_data[8]),
        .D9(symbol_data[9]),
        .PCLK(p_clk),
        .FCLK(s_clk),
        .RESET(reset)
    );

endmodule : tmds_serializer
