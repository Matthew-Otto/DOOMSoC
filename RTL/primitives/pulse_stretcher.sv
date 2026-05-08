// glitchless fast to slow CDC pulse stretch

module pulse_stretcher #(
    parameter FACTOR = 2 
) (
    input  logic clk,
    input  logic pulse_in,
    output logic pulse_out
);

    logic [FACTOR-2:0] shift_reg;

    always_ff @(posedge clk) begin
        shift_reg <= (shift_reg << 1) | pulse_in;
        pulse_out <= pulse_in | (|shift_reg); 
    end

endmodule : pulse_stretcher
