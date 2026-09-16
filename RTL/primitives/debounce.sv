// Debounces input from a (active high) physical button. 
// PULSE=0: Outputs a continuous high level while held.
// PULSE=1: Outputs a single 1 cycle pulse when pressed.

module debounce #(
    parameter int CLK_FREQ = 100_000_000,
    parameter bit PULSE    = 0
) (
    input  logic clk,
    input  logic db_in,
    output logic db_out
);

    // Find smallest divisor that will generate a period of at least ~10ms
    localparam int DIVISOR = $clog2(CLK_FREQ / 100);

    logic sync_reg[1:0];
    logic db_in_sync;
    logic db_level = 0;
    logic [DIVISOR-1:0] cnt = 0;

    // Two-stage synchronizer to prevent metastability
    always_ff @(posedge clk) begin
        sync_reg <= {sync_reg[0], db_in};
    end

    assign db_in_sync = sync_reg[1];

    // Symmetric debounce logic (handles both press and release bounces)
    always_ff @(posedge clk) begin
        if (db_in_sync != db_level) begin
            cnt <= cnt + 1'b1;
            
            if (&cnt) begin
                db_level <= db_in_sync;
                cnt      <= 0;
            end
        end else begin
            cnt <= 0;
        end
    end

    generate
        if (PULSE) begin : gen_pulse
            logic db_level_delay = 0;

            always_ff @(posedge clk) begin
                db_level_delay <= db_level;
            end

            assign db_out = db_level & ~db_level_delay;            
        end else begin : gen_no_pulse
            assign db_out = db_level;
        end
    endgenerate

endmodule : debounce