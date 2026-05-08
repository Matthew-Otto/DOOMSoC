module pipeline_reg #(
    parameter int WIDTH
)(
    input  logic             clk,
    input  logic [WIDTH-1:0] in,
    output logic [WIDTH-1:0] out
);

    always_ff @(posedge clk) begin
        out <= in;
    end

endmodule : pipeline_reg
