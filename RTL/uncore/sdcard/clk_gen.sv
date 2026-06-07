module clk_gen #(
    parameter int INPUT_FREQ,
    parameter int OUTPUT_FREQ
) (
    input  logic clk_in,
    input  logic rst,
    output logic clk_out
);

    //localparam logic [ACCUM_WIDTH-1:0] INCR = (64'(OUTPUT_FREQ) << ACCUM_WIDTH) / INPUT_FREQ;

    localparam int ACCUM_WIDTH = 16;
    localparam logic [ACCUM_WIDTH-1:0] INCR = (OUTPUT_FREQ / INPUT_FREQ) << ACCUM_WIDTH;

    logic [ACCUM_WIDTH-1:0] accum;

    always_ff @(posedge clk_in) begin
        if (rst) begin
            accum <= '0;
        end else begin
            accum <= accum + INCR;
        end
    end

    assign clk_out = accum[ACCUM_WIDTH-1];

endmodule : clk_gen