module pulse_stretcher #(
    parameter FACTOR = 5
) (
    input  logic clk,
    input  logic pulse_in,
    output logic pulse_out
);

    logic [FACTOR-1:0] shift_reg;

    always_ff @(posedge clk) begin
        shift_reg <= {shift_reg[FACTOR-2:0], pulse_in};
    end
    assign pulse_out = |shift_reg;

endmodule : pulse_stretcher
