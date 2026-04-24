// Reset synchronizer

module reset_sync #(
    parameter STAGES = 2
) (
    input  logic clk,
    input  logic async_reset,
    output logic sync_reset
);

    logic [STAGES-1:0] sync;

    always @(posedge clk or posedge async_reset) begin
        if (async_reset)
            sync <= '1;
        else
            sync <= {sync[STAGES-2:0], 1'b0};
    end

    assign sync_reset = sync[STAGES-1];

endmodule : reset_sync
