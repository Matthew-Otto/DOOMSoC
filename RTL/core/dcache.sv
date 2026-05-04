// 8KB dcache
// 256 bit cachelines
// direct mapped
// write through

// bozo
// when reading, index into tag store and cache
// if tag match, return value from cache
// if no tag match, issue read to dram
    // upon read return, fill cacheline and return data to core

// when writing, immediately issue a write to DRAM (if bus is free)
// at the same time, index into tag store
    // if tag match, write value into cache
    // if no tag match, no nothing

module dcache (
    input  logic        core_clk,
    input  logic        bus_clk,
    input  logic        rst,

    output logic        core_rdy,
    input  logic [31:0] core_addr,
    input  logic        core_read_val,
    input  logic [3:0]  core_write_val,
    input  logic [31:0] core_write_data,

    output logic [31:0] core_read_data,
    output logic        core_read_data_val,

    AXI_BUS.Master      m_axi
);


    // TODO core_rdy
    // TODO core_rdy

    ////////////////////////////////////////////////////////////////////////
    //// Reset Logic ///////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [7:0] rst_idx;
    logic rst_active;

    always_ff @(posedge core_clk) begin
        if (rst) begin // BOZO FENCE.I can clear icache
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
    //// Read/Write Buffering //////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic do_read;
    logic do_write;
    logic pending_read;
    logic pending_write;

    logic [31:0] addr_buffer;
    logic [31:0] write_buffer;
    logic [3:0]  wr_mask_buffer;

    assign do_read = core_rdy && core_read_val;
    assign do_write = core_rdy && |core_write_val;

    always_ff @(posedge core_clk) begin
        if (rst_active) begin
            pending_read <= 0;
            pending_write <= 0;
        end else begin
            pending_read <= do_read;
            pending_write <= do_write;
        end

        // save addresses for later fills or cache writes
        if (do_read || do_write)
            addr_buffer <= core_addr;

        // save write data for late cache writes
        if (do_write) begin
            wr_mask_buffer <= core_write_val;
            write_buffer <= core_write_data;
        end
    end


    ////////////////////////////////////////////////////////////////////////
    //// Control Buffering /////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic pending_fill;
    logic update_cacheline;
    logic cacheline_filled;

    logic tag_hit;
    logic read_tag_miss;

    always_ff @(posedge core_clk) begin
        // make miss sticky until the cacheline is filled
        if (rst || cacheline_filled)
            pending_fill <= 0;
        else if (read_tag_miss)
            pending_fill <= 1;
    end

    assign update_cacheline = pending_write && tag_hit;


    ////////////////////////////////////////////////////////////////////////
    //// Addressing Logic //////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [31:0] mem_write_addr;

    logic [1:0]  rd_byte_os, wr_byte_os;
    logic [2:0]  rd_word_os, wr_word_os;
    logic [7:0]  rd_index, wr_index;
    logic [18:0] rd_tag, wr_tag;

    assign {rd_tag, rd_index, rd_word_os, rd_byte_os} = pending_fill ? addr_buffer : core_addr;
    assign {wr_tag, wr_index, wr_word_os, wr_byte_os} = update_cacheline ? addr_buffer : mem_write_addr;
    

    ////////////////////////////////////////////////////////////////////////
    //// Tag store /////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic        fill;
    logic [7:0]  tag_write_index;
    logic [19:0] tag_write_data;
    logic        valid_tag;
    logic [18:0] tag_read;
    
    assign tag_write_index = rst_active ? rst_idx : wr_index;
    assign tag_write_data = rst_active ? '0 : {cacheline_filled,wr_tag};

    dual_port_bram #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(20)
    ) tag_store (
        .clk(core_clk),
        .wr_en(fill || rst_active),
        .write_addr(tag_write_index),
        .write_data(tag_write_data),
        .read_addr(rd_index),
        .read_data({valid_tag,tag_read})
    );

    assign tag_hit = ~rst_active && valid_tag && (rd_tag == tag_read);
    assign read_tag_miss = pending_read && ~tag_hit;

    assign core_rdy = ~(rst_active || read_tag_miss || pending_fill);
    //assign core_rdy = //BOZO TODO read ready (pending write in progress)
    assign core_read_data_val = tag_hit;


    ////////////////////////////////////////////////////////////////////////
    //// Data store ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////   
    logic [3:0]  dstore_wr_en;
    logic [10:0] dstore_rd_addr, dstore_wr_addr;
    logic [31:0] dstore_wr_data;
    logic [31:0] mem_write_data;

    assign dstore_wr_en = update_cacheline ? wr_mask_buffer : {4{fill}};
    assign dstore_rd_addr = {rd_index, rd_word_os};
    assign dstore_wr_addr = {wr_index, wr_word_os};
    assign dstore_wr_data = update_cacheline ? write_buffer : mem_write_data;

    dual_port_bram_be #(
        .ADDR_WIDTH(11),
        .DATA_WIDTH(32)
    ) data_store (
        .clk(core_clk),
        .wr_en(dstore_wr_en),
        .write_addr(dstore_wr_addr),
        .write_data(dstore_wr_data),
        .read_addr(dstore_rd_addr),
        .read_data(core_read_data)
    );


    // BOZO TODO: WRITE AXI PORT
    ////////////////////////////////////////////////////////////////////////
    //// AXI Port //////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    enum logic [1:0] {
        STATE_IDLE,
        STATE_AR_REQ,
        STATE_R_WAIT
    } state, next_state;
    logic [31:0] fetch_addr, next_fetch_addr;

    always_ff @(posedge bus_clk) begin
        if (rst) begin
            state      <= STATE_IDLE;
            fetch_addr <= '0;
        end else begin
            state      <= next_state;
            fetch_addr <= next_fetch_addr;
        end
    end

    always_comb begin
        next_state      = state;
        next_fetch_addr = fetch_addr;

        // Default AXI driver states
        m_axi.ar_valid = 1'b0;
        m_axi.r_ready  = 1'b0;

        // Default BRAM driver states
        fill   = 1'b0;
        mem_write_addr = fetch_addr;
        mem_write_data = m_axi.r_data;
        cacheline_filled = 1'b0;

        case (state)
            STATE_IDLE: begin
                if (read_tag_miss || pending_fill) begin
                    next_fetch_addr = {core_addr[31:5], 5'b00000};
                    next_state      = STATE_AR_REQ;
                end
            end

            STATE_AR_REQ: begin
                m_axi.ar_valid = 1'b1;
                if (m_axi.ar_ready) begin
                    next_state = STATE_R_WAIT;
                end
            end

            STATE_R_WAIT: begin
                m_axi.r_ready = 1'b1;
                if (m_axi.r_valid) begin
                    fill = 1'b1;
                    next_fetch_addr = fetch_addr + 32'd4; 

                    if (m_axi.r_last) begin
                        // Assert valid ONLY on the final beat of the burst
                        cacheline_filled = 1'b1;
                        next_state = STATE_IDLE;
                    end
                end
            end
            
            default: next_state = STATE_IDLE;
        endcase
    end

    ////////////////////////////////////////////////////////////////////////
    //// AXI Channel Tie-offs
    ////////////////////////////////////////////////////////////////////////

    // AXI Read Address Channel (AR)
    assign m_axi.ar_addr   = {fetch_addr[31:5], 5'b00000}; // Lock to cacheline start
    assign m_axi.ar_len    = 8'd7;     // 8 beats (ARLEN is length - 1)
    assign m_axi.ar_size   = 3'b010;   // 4 bytes per beat (32-bit bus)
    assign m_axi.ar_burst  = 2'b01;    // INCR burst type
    assign m_axi.ar_id     = '0;
    //assign m_axi.ar_prot   = 3'b000;
    //assign m_axi.ar_lock   = 1'b0;
    //assign m_axi.ar_cache  = 4'b0010;  // Normal Non-cacheable Modifiable
    //assign m_axi.ar_qos    = '0;
    //assign m_axi.ar_region = '0;

    // AXI Write Channels (Tied off)
    assign m_axi.aw_valid  = 1'b0;
    assign m_axi.aw_addr   = '0;
    assign m_axi.aw_len    = '0;
    assign m_axi.aw_size   = '0;
    assign m_axi.aw_burst  = '0;
    assign m_axi.aw_id     = '0;
    assign m_axi.w_valid   = 1'b0;
    assign m_axi.w_data    = '0;
    assign m_axi.w_strb    = '0;
    assign m_axi.w_last    = 1'b0;
    assign m_axi.b_ready   = 1'b0;


endmodule : dcache
