// 8KB dcache
// 256 bit cachelines
// direct mapped
// write through

// when reading, index into tag store and cache
// if tag match, return value from cache
// if no tag match, issue read to dram
    // upon read return, fill cacheline and return data to core

// when writing, immediately issue a write to DRAM (if bus is free)
// at the same time, index into tag store
    // if tag match, write value into cache
    // if no tag match, no nothing

module cache #(
    parameter int MASTER_ID,
    parameter int ADDR_WIDTH,
    parameter int DATA_WIDTH,
    parameter int ID_WIDTH
) (
    input  logic        core_clk,
    input  logic        core_clk_rst,
    input  logic        bus_clk,

    input  logic        core_flush,
    output logic        core_rdy,
    input  logic [31:0] core_addr,
    input  logic        core_read_val,
    input  logic [3:0]  core_write_val,
    input  logic [31:0] core_write_data,

    output logic [31:0] core_read_data,
    output logic        core_read_data_val,

    AXI_BUS.Master      m_axi
);


    ////////////////////////////////////////////////////////////////////////
    //// Reset Logic ///////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    // BRAMs can't be cleared asynchronously, must write every address manually
    // This makes cache instructions like FENCE.I very expensive.
    // Reset is in core_clk domain, but reset index generation is in bus_clk domain

    logic [7:0] rst_idx;
    logic rst_active;

    always_ff @(posedge bus_clk) begin
        if (core_clk_rst) begin
            rst_active <= 1;
            rst_idx <= 8'd255;
        end else if (rst_active) begin
            if (rst_idx == 0)
                rst_active <= 0;
            else
                rst_idx <= rst_idx - 1;
        end
    end


    ////////////////////////////////////////////////////////////////////////
    //// Core State Tracking ///////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic hit, miss;
    logic read_in_progress;  // a read is in progress
    logic write_in_progress; // a write trigger a tag lookup
    logic [3:0]  core_wr_en_buffer;
    logic [31:0] core_addr_buffer;
    logic [31:0] core_write_data_buffer;
    logic        cacheline_filled;
    logic        cacheline_filled_core;

    always_ff @(posedge core_clk) begin
        if (rst_active)
            read_in_progress <= 0;
        else if (core_rdy && core_read_val)
            read_in_progress <= 1;
        else if (hit || core_flush)
            read_in_progress <= 0;

        if (rst_active)
            write_in_progress <= 0;
        else
            write_in_progress <= core_rdy && |core_write_val;

        if (core_rdy && (core_read_val || |core_write_val))
            core_addr_buffer <= core_addr;

        if (core_rdy && |core_write_val) begin
            core_write_data_buffer <= core_write_data;
            core_wr_en_buffer <= core_write_val;
        end
    end

    // strech cacheline_filled to make it safe for core_clk domain
    pulse_stretcher #(
        .FACTOR(2)
    ) cacheline_filled_cdc (
        .clk(bus_clk),
        .pulse_in(cacheline_filled),
        .pulse_out(cacheline_filled_core)
    );


    ////////////////////////////////////////////////////////////////////////
    //// Addressing Logic //////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [1:0]  core_byte_os, bus_byte_os;
    logic [2:0]  core_word_os, bus_word_os;
    logic [7:0]  core_index, bus_index;
    logic [18:0] core_tag, bus_tag;

    assign {core_tag, core_index, core_word_os, core_byte_os} = (cacheline_filled_core || write_in_progress) ? core_addr_buffer : core_addr;
    
    logic [31:0] fill_addr, next_fill_addr;
    
    assign {bus_tag, bus_index, bus_word_os, bus_byte_os} = fill_addr;


    ////////////////////////////////////////////////////////////////////////
    //// Tag store /////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic        core_tag_rd_valid;
    logic [18:0] core_tag_rd_data;

    logic [7:0]  bus_tag_addr;
    logic        bus_tag_wr_en;
    logic [19:0] bus_tag_wr_data;

    always_comb begin : tag_reset_mux
        if (rst_active) begin
            bus_tag_wr_en = 1'b1;
            bus_tag_addr = rst_idx;
            bus_tag_wr_data = '0;
        end else begin
            bus_tag_wr_en = cacheline_filled;
            bus_tag_addr = bus_index;
            bus_tag_wr_data = {1'b1,bus_tag};
        end
    end

    dpdc_bram #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(20)
    ) tag_store (
        .clk_a(core_clk),
        .addr_a(core_index),
        .wr_en_a('0),
        .wr_data_a('0),
        .rd_data_a({core_tag_rd_valid,core_tag_rd_data}),
        .clk_b(bus_clk),
        .addr_b(bus_tag_addr),
        .wr_en_b(bus_tag_wr_en),
        .wr_data_b(bus_tag_wr_data),
        .rd_data_b()
    );

    //// Tag match logic
    assign hit = core_tag == core_tag_rd_data;
    assign miss = ~hit;

    //// Core interface
    assign core_rdy = ~rst_active & (~(read_in_progress | write_in_progress) | hit);
    assign core_read_data_val = hit && read_in_progress;


    ////////////////////////////////////////////////////////////////////////
    //// Data store ////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////// 
    logic core_data_wr_en;
    logic bus_data_wr_en;

    assign core_data_wr_en = (hit && write_in_progress) ? core_wr_en_buffer : '0;
    assign bus_data_wr_en = m_axi.r_ready && m_axi.r_valid;

    dpdc_bram_be #(
        .ADDR_WIDTH(12),
        .DATA_WIDTH(32)
    ) data_store (
        .clk_a(core_clk),
        .addr_a({core_index, core_word_os}),
        .wr_en_a(|core_data_wr_en),
        .wr_data_a(core_write_data_buffer),
        .rd_data_a(core_read_data),
        .clk_b(bus_clk),
        .addr_b({bus_index, bus_word_os}),
        .wr_en_b({4{bus_data_wr_en}}),
        .wr_data_b(m_axi.r_data),
        .rd_data_b()
    );


    ////////////////////////////////////////////////////////////////////////
    //// AXI Interface /////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    enum {
        IDLE,
        READ_REQ,
        READ_WAIT,
        PENDING_WRITE
    } state, next_state;

    always_ff @(posedge bus_clk) begin
        if (rst_active) state <= IDLE;
        else            state <= next_state;
    end

    always_ff @(posedge bus_clk) begin
        if (m_axi.ar_ready && m_axi.ar_valid) begin
            fill_addr <= core_addr_buffer;
        end else begin
            fill_addr <= next_fill_addr;
        end
    end

    assign m_axi.ar_addr  = core_addr_buffer;
    assign m_axi.ar_len   = 8'd7;     // 8 beats (ARLEN is length - 1)
    assign m_axi.ar_size  = 3'b010;   // 4 bytes per beat (32-bit bus)
    assign m_axi.ar_burst = 2'b01;    // INCR burst type
    assign m_axi.ar_id    = MASTER_ID;

    assign m_axi.aw_addr  = core_addr_buffer;
    assign m_axi.aw_len   = '0;
    assign m_axi.aw_size  = '0;
    assign m_axi.aw_burst = '0;
    assign m_axi.aw_id    = MASTER_ID;
    
    assign m_axi.w_data   = core_write_data_buffer;
    assign m_axi.w_strb   = core_wr_en_buffer;
    assign m_axi.w_last   = 1'b1;
    assign m_axi.b_ready  = 1'b1;

    always_comb begin
        next_state = state;
        next_fill_addr = fill_addr;

        m_axi.ar_valid = 1'b0;
        m_axi.aw_valid = 1'b0;
        m_axi.w_valid = 1'b0;
        m_axi.r_ready  = 1'b0;
        cacheline_filled = 1'b0;

        case (state)
            IDLE : begin
                if (read_in_progress && miss) begin
                    m_axi.ar_valid = 1'b1;
                    if (m_axi.ar_ready)
                        next_state = READ_WAIT;
                    else
                        next_state = READ_REQ;
                end else if (write_in_progress) begin
                    // BOZO the bus may accept aw and w at different times
                    m_axi.aw_valid = 1'b1;
                    m_axi.w_valid = 1'b1;
                    if (~m_axi.aw_ready)
                        next_state = PENDING_WRITE;
                end
            end

            READ_REQ : begin
                m_axi.ar_valid = 1'b1;
                if (m_axi.ar_ready)
                    next_state = READ_WAIT;
            end
                
            READ_WAIT : begin
                m_axi.r_ready = 1'b1;
                if (m_axi.r_valid) begin
                    next_fill_addr = fill_addr + 32'd4;
                    if (m_axi.r_last) begin
                        // only update tag on final beat of the burst
                        cacheline_filled = 1'b1;
                        next_state = IDLE;
                    end
                end
            end

            PENDING_WRITE : begin
                // BOZO the bus may accept aw and w at different times
                m_axi.aw_valid = 1'b1;
                m_axi.w_valid = 1'b1;
                if (m_axi.aw_ready)
                    next_state = IDLE;
            end
        endcase
    end

endmodule : cache
