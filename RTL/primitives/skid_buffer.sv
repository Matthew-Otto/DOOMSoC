module skid_buffer #(parameter DATA_WIDTH) (
    input  logic                  clk, reset,

    output logic                  input_ready,
    input  logic                  input_valid,
    input  logic [DATA_WIDTH-1:0] input_data,

    input  logic                  output_ready,
    output logic                  output_valid,
    output logic [DATA_WIDTH-1:0] output_data
);

logic valid_reg;
logic [DATA_WIDTH-1:0] data_reg;


always @(posedge clk) begin
    if (reset) begin
        input_ready <= 1'b1;
        output_valid <= 1'b0;
        valid_reg <= 1'b0;
        
    // stall
    end else if (input_ready && ~output_ready && output_valid) begin
        input_ready <= 1'b0;
        valid_reg <= input_valid;
        if (input_valid)
            data_reg <= input_data;
    
    // resume
    end else if (~input_ready && output_ready) begin
        input_ready <= 1'b1;
        output_valid <= valid_reg;
        if (valid_reg)
            output_data <= data_reg;
    
    // normal operation
    end else if (input_ready) begin
        output_valid <= input_valid;
        if (input_valid)
            output_data <= input_data;
    end
end

endmodule: skid_buffer
