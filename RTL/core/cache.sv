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
    input  logic        bus_clk_rst,

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

    localparam CACHELINE_OFFSET = 5;

    ////////////////////////////////////////////////////////////////////////
    //// Reset Logic ///////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    // BRAMs can't be cleared asynchronously, must write every address manually
    // This makes cache instructions like FENCE.I very expensive.
    // Reset is in core_clk domain, but reset index generation is in bus_clk domain

    logic [7:0] rst_idx;
    logic rst_active;

    always_ff @(posedge bus_clk) begin
        if (bus_clk_rst) begin
            rst_active <= 1;
            rst_idx <= 8'd255;
        end else if (rst_active) begin
            if (rst_idx == 0)
                rst_active <= 0;
            else
                rst_idx <= rst_idx - 1;
        end
    end

    // TODO reset CDC


    ////////////////////////////////////////////////////////////////////////
    //// Core IDK ///////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic tag_read, tag_read_ready;
    logic        latch_address;
    logic [31:0] core_addr_buffer;
    logic        latch_write_data;
    logic [3:0]  core_wr_en_buffer;
    logic [31:0] core_write_data_buffer;

    always_ff @(posedge core_clk) begin
        tag_read_ready <= tag_read;

        if (latch_address)
            core_addr_buffer <= core_addr;

        if (latch_write_data) begin
            core_wr_en_buffer <= core_write_val;
            core_write_data_buffer <= core_write_data;
        end
    end

    ////////////////////////////////////////////////////////////////////////
    //// Addressing Logic //////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [31:0] core_ts_addr_mux, core_ds_addr_mux;
    logic [1:0]  core_ts_byte_os, core_ds_byte_os, core_byte_os_buffer;
    logic [2:0]  core_ts_word_os, core_ds_word_os, core_word_os_buffer;
    logic [7:0]  core_ts_index, core_ds_index, core_index_buffer;
    logic [18:0] core_ts_tag, core_ds_tag, core_tag_buffer;
    
    assign {core_ts_tag, core_ts_index, core_ts_word_os, core_ts_byte_os} = core_ts_addr_mux;
    assign {core_ds_tag, core_ds_index, core_ds_word_os, core_ds_byte_os} = core_ds_addr_mux;
    assign {core_tag_buffer, core_index_buffer, core_word_os_buffer, core_byte_os_buffer} = core_addr_buffer;
    
    
    
    ////////////////////////////////////////////////////////////////////////
    //// Core Interface ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic hit;
    logic trigger_cache_fill;
    logic [3:0] core_ds_wr_en;

    // CDC
    logic trigger_mem_write;
    logic write_committed;

    enum {
        CORE_IDLE,
        CORE_WRITE,
        CORE_WRITE_WAIT,
        CORE_READ,
        CORE_CACHE_FILL,
        CORE_CACHE_FILL_FLUSHED
    } core_state, next_core_state;

    always_ff @(posedge core_clk) begin
        if (rst_active) core_state <= CORE_IDLE;
        else            core_state <= next_core_state;
    end

    always_comb begin
        next_core_state = core_state;
        core_rdy = 1'b0;
        core_read_data_val = 1'b0;

        core_ts_addr_mux = core_addr;
        core_ds_addr_mux = core_addr;

        latch_address = 1'b0;
        latch_write_data = 1'b0;
        tag_read = 1'b0;
        core_ds_wr_en = '0;
        trigger_mem_write = 1'b0;
        trigger_cache_fill = 1'b0;


        case (core_state)           
            CORE_IDLE : begin
                if (~rst_active) begin
                    core_rdy = 1'b1;
                    if (core_write_val) begin
                        latch_address = 1'b1;
                        latch_write_data = 1'b1;
                        tag_read = 1'b1;
                        next_core_state = CORE_WRITE;
                    end else if (core_read_val) begin
                        latch_address = 1'b1;
                        tag_read = 1'b1;
                        next_core_state = CORE_READ;
                    end
                end
            end
            
            CORE_WRITE : begin
                // Write word to cache
                if (hit) begin
                    core_ds_wr_en = core_wr_en_buffer;
                    core_ds_addr_mux = core_addr_buffer;
                end
                
                // Write word to DRAM
                trigger_mem_write = 1'b1;
                if (write_committed) begin
                    core_rdy = 1'b1;
                    if (core_read_val) begin
                        latch_address = 1'b1;
                        tag_read = 1'b1;
                        next_core_state = CORE_READ;
                    end else if (core_write_val) begin
                        latch_address = 1'b1;
                        latch_write_data = 1'b1;
                        tag_read = 1'b1;
                    end else begin
                        next_core_state = CORE_IDLE;
                    end
                end else begin
                    next_core_state = CORE_WRITE_WAIT;
                end
            end

            CORE_WRITE_WAIT : begin
                if (write_committed) begin
                    core_rdy = 1'b1;
                    if (core_read_val) begin
                        latch_address = 1'b1;
                        tag_read = 1'b1;
                        next_core_state = CORE_READ;
                    end else if (core_write_val) begin
                        latch_address = 1'b1;
                        latch_write_data = 1'b1;
                        tag_read = 1'b1;
                    end else begin
                        next_core_state = CORE_IDLE;
                    end
                end
            end
            
            CORE_READ : begin
                core_rdy = hit;
                core_read_data_val = hit;

                if (hit || core_flush) begin
                    // pipeline reads
                    if (core_read_val) begin
                        latch_address = 1'b1;
                        tag_read = 1'b1;

                    // pipeline writes
                    end else if (core_write_val) begin
                        latch_address = 1'b1;
                        latch_write_data = 1'b1;
                        tag_read = 1'b1;
                        trigger_mem_write = 1'b1;
                        next_core_state = CORE_WRITE;

                    end else begin
                        next_core_state = CORE_IDLE;
                    end

                // if miss (and not flush), must fill cacheline from DRAM
                end else begin
                    trigger_cache_fill = 1'b1;
                    core_ts_addr_mux = core_addr_buffer;
                    next_core_state = CORE_CACHE_FILL;
                end
            end
            
            CORE_CACHE_FILL : begin
                core_rdy = hit;
                core_read_data_val = ~core_flush && hit;

                if (hit) begin
                    // pipeline reads
                    if (core_read_val) begin
                        latch_address = 1'b1;
                        tag_read = 1'b1;
                        next_core_state = CORE_READ;

                    // pipeline writes
                    end else if (core_write_val) begin
                        latch_address = 1'b1;
                        latch_write_data = 1'b1;
                        tag_read = 1'b1;
                        trigger_mem_write = 1'b1;
                        next_core_state = CORE_WRITE;

                    end else begin
                        next_core_state = CORE_IDLE;
                    end
                end else begin
                    tag_read = 1;
                    core_ts_addr_mux = core_addr_buffer;
                    if (core_flush)
                        next_core_state = CORE_CACHE_FILL_FLUSHED;
                end
            end

            CORE_CACHE_FILL_FLUSHED : begin
                core_rdy = hit;

                if (hit) begin
                    // pipeline reads
                    if (core_read_val) begin
                        latch_address = 1'b1;
                        tag_read = 1'b1;
                        next_core_state = CORE_READ;

                    // pipeline writes
                    end else if (core_write_val) begin
                        latch_address = 1'b1;
                        latch_write_data = 1'b1;
                        tag_read = 1'b1;
                        trigger_mem_write = 1'b1;
                        next_core_state = CORE_WRITE;

                    end else begin
                        next_core_state = CORE_IDLE;
                    end
                end else begin
                    tag_read = 1;
                    core_ts_addr_mux = core_addr_buffer;
                end
            end
        endcase
    end


    ////////////////////////////////////////////////////////////////////////
    //// Bus Addressing ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [1:0]  bus_byte_os;
    logic [2:0]  bus_word_os;
    logic [7:0]  bus_index;
    logic [18:0] bus_tag;

    logic        cacheline_filled;
    logic [31:0] fill_addr, next_fill_addr;
    
    assign {bus_tag, bus_index, bus_word_os, bus_byte_os} = fill_addr;

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


    ////////////////////////////////////////////////////////////////////////
    //// Tag store /////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic        core_tag_rd_valid;
    logic [18:0] core_tag_rd_data;

    sdp_bram #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(20)
    ) tag_store (
        .wr_clk(bus_clk),
        .wr_en(bus_tag_wr_en),
        .wr_addr(bus_tag_addr),
        .wr_data(bus_tag_wr_data),
        .rd_clk(core_clk),
        .rd_addr(core_ts_index),
        .rd_data({core_tag_rd_valid,core_tag_rd_data})
    );

    assign hit = tag_read_ready && core_tag_rd_valid && (core_tag_buffer == core_tag_rd_data);


    ////////////////////////////////////////////////////////////////////////
    //// Data store ////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////// 
    logic bus_data_wr_en;

    assign bus_data_wr_en = m_axi.r_ready && m_axi.r_valid;

    tdp_bram_be #(
        .ADDR_WIDTH(11),
        .DATA_WIDTH(32)
    ) data_store (
        .clk_a(core_clk),
        .addr_a({core_ds_index, core_ds_word_os}),
        .wr_en_a(core_ds_wr_en),
        .wr_data_a(core_write_data_buffer),
        .rd_data_a(core_read_data),
        .clk_b(bus_clk),
        .addr_b({bus_index, bus_word_os}),
        .wr_en_b({4{bus_data_wr_en}}),
        .wr_data_b(m_axi.r_data),
        .rd_data_b()
    );


    ////////////////////////////////////////////////////////////////////////
    //// AXI Bus Interface /////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    enum {
        BUS_IDLE,
        BUS_READ_REQ,
        BUS_READ_WAIT,
        BUS_PEND_WRITE,
        BUS_WRITE_SYNC
    } bus_state, next_bus_state;

    always_ff @(posedge bus_clk) begin
        if (rst_active) bus_state <= BUS_IDLE;
        else            bus_state <= next_bus_state;
    end

    always_ff @(posedge bus_clk) begin
        if (m_axi.ar_ready && m_axi.ar_valid) begin
            fill_addr <= {core_addr_buffer[31:CACHELINE_OFFSET], {CACHELINE_OFFSET{1'b0}}};
        end else begin
            fill_addr <= next_fill_addr;
        end
    end

    assign m_axi.ar_addr  = {core_addr_buffer[31:CACHELINE_OFFSET], {CACHELINE_OFFSET{1'b0}}};
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
        next_bus_state = bus_state;
        next_fill_addr = fill_addr;

        m_axi.ar_valid = 1'b0;
        m_axi.aw_valid = 1'b0;
        m_axi.w_valid = 1'b0;
        m_axi.r_ready  = 1'b0;
        cacheline_filled = 1'b0;
        write_committed = 1'b0;

        case (bus_state)
            BUS_IDLE : begin
                if (trigger_cache_fill) begin
                    m_axi.ar_valid = 1'b1;
                    if (m_axi.ar_ready)
                        next_bus_state = BUS_READ_WAIT;
                    else
                        next_bus_state = BUS_READ_REQ;
                end else if (trigger_mem_write) begin
                    // BOZO the bus may accept aw and w at different times
                    m_axi.aw_valid = 1'b1;
                    m_axi.w_valid = 1'b1;
                    if (~m_axi.aw_ready) begin
                        next_bus_state = BUS_PEND_WRITE;
                    end else begin
                        write_committed = 1'b1;
                        next_bus_state = BUS_WRITE_SYNC;
                    end
                end
            end

            BUS_READ_REQ : begin
                m_axi.ar_valid = 1'b1;
                if (m_axi.ar_ready)
                    next_bus_state = BUS_READ_WAIT;
            end
                
            BUS_READ_WAIT : begin
                m_axi.r_ready = 1'b1;
                if (m_axi.r_valid) begin
                    next_fill_addr = fill_addr + 32'd4;
                    if (m_axi.r_last) begin
                        cacheline_filled = 1'b1;
                        next_bus_state = BUS_IDLE;
                    end
                end
            end

            BUS_PEND_WRITE : begin
                // BOZO the bus may accept aw and w at different times
                m_axi.aw_valid = 1'b1;
                m_axi.w_valid = 1'b1;
                if (m_axi.aw_ready) begin
                    write_committed = 1'b1;
                    next_bus_state = BUS_WRITE_SYNC;
                end
            end

            BUS_WRITE_SYNC : begin
                write_committed = 1'b1;
                next_bus_state = BUS_IDLE;
            end
        endcase
    end

endmodule : cache
