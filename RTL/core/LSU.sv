// load/store unit

`include "defines.svh"

// BOZO
// ideally a load returns in one cycle
// on a miss, assert stall until the cacheline is filled and the data is return
// writes complete immediately from the LSU perspective
//      may need to support backpressure if write is in progress when a load occurs
//      or maybe the cache handles this internally


module LSU #(
    parameter int ADDR_WIDTH,
    parameter int DATA_WIDTH, 
    parameter int ID_WIDTH
) (
    input  logic        core_clk,
    input  logic        bus_clk,
    input  logic        rst,

    // Core Control
    input  logic        valid,
    output logic        ready,

    input  logic        is_load_op,
    input  load_op_t    load_op,
    input  logic        is_store_op,
    input  store_op_t   store_op,
    input  logic [31:0] ls_addr,
    input  logic [31:0] write_data,
    input  logic [4:0]  rd_addr,

    // Register Write
    output logic        ld_valid,
    output logic        ld_inflight,
    output logic [4:0]  ld_rd_addr,
    output logic [31:0] ld_rd_data,

    AXI_BUS.Master      dcache_port
);    

    ////////////////////////////////////////////////////////////////////////
    //// Load Queue ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic        load;
    logic        pending_load;
    load_op_t    load_op_reg;
    logic [1:0]  read_byte_of;
    logic [31:0] core_read_data;
    logic [31:0] read_data_aligned;

    always_ff @(posedge core_clk) begin
        if (rst || ld_valid)
            pending_load <= 0;
        else if (load)
            pending_load <= 1;

        if (load) begin
            read_byte_of <= ls_addr[1:0];
            ld_rd_addr <= rd_addr;
            load_op_reg <= load_op;
        end
    end
    
    assign load = valid && is_load_op;
    assign ld_inflight = pending_load && ~ld_valid;

    always_comb begin
        case (read_byte_of)
            2'b01:   read_data_aligned = {8'b0,  core_read_data[31:8]};
            2'b10:   read_data_aligned = {16'b0, core_read_data[31:16]};
            2'b11:   read_data_aligned = {24'b0, core_read_data[31:24]};
            default: read_data_aligned = core_read_data;
        endcase
    end

    always_comb begin
        case (load_op_reg)
            i_LB   : ld_rd_data = {{24{read_data_aligned[7]}},read_data_aligned[7:0]};
            i_LH   : ld_rd_data = {{16{read_data_aligned[15]}},read_data_aligned[15:0]};
            i_LW   : ld_rd_data = read_data_aligned;
            i_LBU  : ld_rd_data = {24'b0,read_data_aligned[7:0]};
            i_LHU  : ld_rd_data = {16'b0,read_data_aligned[15:0]};
            default: ld_rd_data = read_data_aligned;
        endcase
    end


    ////////////////////////////////////////////////////////////////////////
    //// Write masking /////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic store;
    logic [3:0] we_mask;
    logic [3:0] wr_en;
    
    always_comb begin
        case (store_op)
            i_SB   : we_mask = 4'b0001;
            i_SH   : we_mask = 4'b0011;
            i_SW   : we_mask = 4'b1111;
            default: we_mask = 4'b0000;
        endcase
    end
    
    assign store = is_store_op && valid && ~ld_inflight;
    assign wr_en = {4{store}} & we_mask;


    ////////////////////////////////////////////////////////////////////////
    //// Dcache ////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic cache_rdy;
    assign ready = ~(valid && (is_store_op || is_load_op ) && ~cache_rdy);
    
    cache #(
        .MASTER_ID(1),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) dcache_i (
        .core_clk,
        .core_clk_rst(rst),
        .bus_clk,
        .core_flush(1'b0),
        .core_rdy(cache_rdy),
        .core_addr(ls_addr),
        .core_read_val(load),
        .core_write_val(wr_en),
        .core_write_data(write_data),
        .core_read_data,
        .core_read_data_val(ld_valid),
        .m_axi(dcache_port)
    );

endmodule : LSU
