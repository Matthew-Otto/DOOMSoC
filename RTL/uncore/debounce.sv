// Debounces input from a (active high) physical button. 
// Optionally outputs a single (fast_clk) cycle pulse per button press if PULSE is enabled

module debounce #(
    parameter int CLK_FREQ = 50000000,
    parameter logic PULSE = 0
) (
    input  logic clk,
    input  logic db_in,
    output logic db_out
);

    // find smallest divisor that will generate a period of at least 10ms
    localparam DIVISOR = $clog2(CLK_FREQ / 100);

    logic [DIVISOR-1:0] cnt;
    logic q1, q2;
    logic db_in_rising_edge;

    assign db_in_rising_edge = q1 && ~q2;

    always_ff @(posedge clk) begin
        q1 <= db_in;
        q2 <= q1;

        if (|cnt || db_in_rising_edge)
            cnt <= cnt + 1;
    end

    if (PULSE) begin : gen_pulse
        logic pulse;

        always_ff @(posedge clk) begin
            if (db_out)
                pulse <= 1;
            else if (~db_in)
                pulse <= 0;
        end

        assign db_out = &cnt && db_in && ~pulse;
    end else begin : gen_no_pulse
        assign db_out = &cnt && db_in;
    end


endmodule : debounce
