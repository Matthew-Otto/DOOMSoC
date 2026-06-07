module clk_gen #(
    parameter int INPUT_FREQ,
    parameter int OUTPUT_FREQ
) (
    input  logic clk_in,
    input  logic rst,
    output logic clk_out
);

    localparam int CLK_DIV = INPUT_FREQ / OUTPUT_FREQ;
    localparam int THRESH = CLK_DIV / 2;
    localparam int COUNTER_WIDTH = $clog2(THRESH);

    logic [COUNTER_WIDTH-1:0] counter;

    always_ff @(posedge clk_in) begin
        if (rst) begin
            counter <= '0;
            clk_out <= 1'b0;
        end else begin
            if (counter == THRESH - 1) begin
                counter <= '0;
                clk_out <= ~clk_out;
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end

endmodule : clk_gen
