// Reset synchronizer

module reset_sync (
    input  logic async_reset,
    input  logic sync_clk,
    output logic sync_reset
);

    (* async_reg = "true" *) logic [1:0] sync_reg;

    always_ff @(posedge sync_clk) begin
        sync_reg <= {sync_reg[0], async_reset};
    end

    assign sync_reset = sync_reg[1];

endmodule : reset_sync
