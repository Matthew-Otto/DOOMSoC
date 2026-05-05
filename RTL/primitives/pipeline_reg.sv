module pipeline_reg #(
    parameter int WIDTH
)(
    input  logic             clk,
    input  logic             valid_in,
    output logic             valid_out,
    input  logic [WIDTH-1:0] in,
    output logic [WIDTH-1:0] out
);

    always_ff @(posedge clk) begin
        valid_out <= valid_in;
    end

    always_ff @(posedge clk) begin
        if (valid_in)
            out <= in;
    end

endmodule : pipeline_reg
