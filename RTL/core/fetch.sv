// Calculates PC and fetches instructions from icache

module fetch #(
    parameter logic [31:0] RESET_PC = 32'h8000_0000
)(
    input  logic        core_clk,
    input  logic        bus_clk,
    input  logic        rst,

    input  logic        branch,
    input  logic [31:0] branch_target,
    
    
    output logic        flush,
    input  logic        ready,
    output logic        valid,
    output logic [31:0] instr,
    output logic [31:0] PC,

    AXI_BUS.Master      icache_port
);

    logic [31:0] fetch_PC;
    logic [31:0] fetch_PC_mux;
    logic [31:0] next_fetch_PC;
    logic        cache_ready;
    logic        cache_valid;
    logic [31:0] cache_instr;
    logic [31:0] cache_PC;
    logic        buffer_rdy;
    logic        stall;


    assign next_fetch_PC = (branch && (~cache_ready || stall)) ? branch_target : fetch_PC_mux + 4;

    always_ff @(posedge core_clk) begin : PC_reg
        if (rst) begin
            fetch_PC <= RESET_PC;
        end else if (branch || (~stall && cache_ready)) begin
            fetch_PC <= next_fetch_PC;
        end
    end

    assign fetch_PC_mux = branch ? branch_target : fetch_PC;

    icache icache (
        .core_clk,
        .bus_clk,
        .rst,
        .core_addr(fetch_PC_mux),
        .core_read_rdy(cache_ready),
        .core_read_val(~stall),
        .core_instr(cache_instr),
        .core_instr_val(cache_valid),
        .m_axi(icache_port)
    );

    always_ff @(posedge core_clk) begin
        if (~stall && cache_ready)
            cache_PC <= fetch_PC_mux;
    end

    assign flush = branch;
    assign stall = ~buffer_rdy;

    skid_buffer #(
        .DATA_WIDTH(64)
    ) skid_buffer_i (
        .clk(core_clk),
        .reset(rst || flush),
        .input_ready(buffer_rdy),
        .input_valid(cache_valid),
        .input_data({cache_PC,cache_instr}),
        .output_ready(ready),
        .output_valid(valid),
        .output_data({PC,instr})
    );

endmodule : fetch
