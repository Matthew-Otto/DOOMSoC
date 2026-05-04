// load/store unit

`include "defines.svh"

// bozo
// ideally a load returns in one cycle
// on a miss, assert stall until the cacheline is filled and the data is return
// writes complete immediately from the LSU perspective
//      may need to support backpressure if write is in progress when a load occurs
//      or maybe the cache handles this internally


module LSU (
    input  logic        core_clk,
    input  logic        bus_clk,
    input  logic        rst,

    // Core Control
    // TODO valid bit and flush
    input  logic        valid,
    input  logic        flush,
    output logic        stall,
    input  logic        is_load_op,
    input  load_op_t    load_op,
    input  logic        is_store_op,
    input  store_op_t   store_op,
    input  logic [31:0] ls_addr,
    input  logic [31:0] write_data,
    input  logic [4:0]  rd_addr,

    // Register Write
    output logic        ld_valid,
    output logic [4:0]  ld_rd_addr,
    output logic [31:0] ld_rd_data,

    AXI_BUS.Master      dcache_port
);    

    ////////////////////////////////////////////////////////////////////////
    //// Load Queue ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic load;
    logic pending_load;
    logic load_in_progress;
    load_op_t load_op_reg;
    logic [31:0] core_read_data;

    always_ff @(posedge core_clk) begin
        if (rst || ld_valid)
            pending_load <= 0;
        else if (load)
            pending_load <= 1;

        if (load) begin
            ld_rd_addr <= rd_addr;
            load_op_reg <= load_op;
        end
    end
    
    assign load = valid && ~flush && is_load_op;
    assign load_in_progress = pending_load && ~ld_valid;

    always_comb begin
        case (load_op_reg)
            i_LB   : ld_rd_data = {{24{core_read_data[7]}},core_read_data[7:0]};
            i_LH   : ld_rd_data = {{16{core_read_data[15]}},core_read_data[15:0]};
            i_LW   : ld_rd_data = core_read_data;
            i_LBU  : ld_rd_data = {24'b0,core_read_data[7:0]};
            i_LHU  : ld_rd_data = {16'b0,core_read_data[15:0]};
            default: ld_rd_data = core_read_data;
        endcase
    end


    ////////////////////////////////////////////////////////////////////////
    //// Write masking /////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic store;
    logic [3:0] we_mask;
    logic [3:0] write_mask;
    
    always_comb begin
        case (store_op)
            i_SB   : we_mask = 4'b0001;
            i_SH   : we_mask = 4'b0011;
            i_SW   : we_mask = 4'b1111;
            default: we_mask = 4'b0000;
        endcase
    end
    
    assign store = is_store_op && valid && ~flush && ~load_in_progress;
    assign write_mask = {4{store}} & we_mask;


    ////////////////////////////////////////////////////////////////////////
    //// Dcache ////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic cache_rdy;
    
    // BOZO load_in_progress might be redundant (cache will deassert rdy when loads in progress)
    assign stall = (is_load_op || is_store_op) && (load_in_progress || ~cache_rdy);

    dcache dcache_i (
        .core_clk,
        .bus_clk,
        .rst,
        .core_addr(ls_addr),
        .core_rdy(cache_rdy),
        .core_read_val(load),
        .core_write_val(write_mask),
        .core_write_data(write_data),
        .core_read_data,
        .core_read_data_val(ld_valid),
        .m_axi(dcache_port)
    );

endmodule : LSU
