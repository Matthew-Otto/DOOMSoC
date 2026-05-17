// Calculates PC and fetches instructions from icache

// if a branch occurs during an icache fill, 
// the new branch target fetch will be stalled
// while the badpath PC is loaded into the icache

module fetch #(
    parameter logic [31:0] RESET_PC = 32'h2000_0000,
    parameter int ADDR_WIDTH,
    parameter int DATA_WIDTH, 
    parameter int ID_WIDTH
) (
    input  logic        core_clk,
    input  logic        core_clk_rst,
    input  logic        bus_clk,
    input  logic        bus_clk_rst,

    input  logic        branch,
    input  logic [31:0] branch_target,
    input  logic        stall_FE,

    output logic        valid_FE,
    output logic [31:0] instr_FE,
    output logic [31:0] PC_FE,

    AXI_BUS.Master      icache_port
);

    logic [31:0] PC_reg;
    logic [31:0] fetch_PC;
    logic [31:0] next_PC;
    logic        cache_ready;

    assign next_PC = (branch && ~cache_ready) ? branch_target : fetch_PC + 4;

    always_ff @(posedge core_clk) begin
        if (core_clk_rst) begin
            PC_reg <= RESET_PC;
        end else if (branch || (~stall_FE && cache_ready)) begin
            PC_reg <= next_PC;
        end
    end

    assign fetch_PC = branch ? branch_target : PC_reg;

    cache #(
        .MASTER_ID(0),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) icache_i (
        .core_clk,
        .core_clk_rst,
        .bus_clk,
        .bus_clk_rst,
        .core_flush(branch),
        .core_rdy(cache_ready),
        .core_addr(fetch_PC),
        .core_read_val(~stall_FE),
        .core_write_val('0),
        .core_write_data('0),
        .core_read_data(instr_FE),
        .core_read_data_val(valid_FE),
        .m_axi(icache_port)
    );

    always_ff @(posedge core_clk) begin
        if (core_clk_rst)
            PC_FE <= '0;
        else if (~stall_FE && cache_ready)
            PC_FE <= fetch_PC;
    end

endmodule : fetch
