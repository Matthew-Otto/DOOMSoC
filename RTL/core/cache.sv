// 8KB cache
// 256 bit cachelines
// direct mapped
// write through
// TODO non-caching reads

module cache #(
    parameter int MASTER_ID,
    parameter int ADDR_WIDTH,
    parameter int DATA_WIDTH,
    parameter int ID_WIDTH
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        core_flush,
    output logic        core_rdy,
    input  logic [31:0] core_addr,
    input  logic        core_read_val,
    input  logic [3:0]  core_write_val,
    input  logic [31:0] core_write_data,

    output logic        fill_in_progress,
    output logic [31:0] core_read_data,
    output logic        core_read_data_val,

    AXI_BUS.Master      m_axi
);

    localparam CACHELINE_OFFSET = 5;


    ////////////////////////////////////////////////////////////////////////
    //// Address Lookup ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic uncacheable_addr;

    always_comb begin
        uncacheable_addr = 1'b0;
        casez (core_addr)
            32'h4???_???? : uncacheable_addr = 1'b1;
        endcase
    end


    ////////////////////////////////////////////////////////////////////////
    //// Core Input Latch //////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic        tag_read, tag_read_ready;
    logic        latch_address;
    logic        latch_write_data;
    logic        incr_fill_addr;
    logic [31:0] addr_buffer;
    logic [31:0] fill_addr;
    logic [3:0]  wr_strb_buffer;
    logic [31:0] write_data_buffer;

    logic trigger_fill;
    logic fill_complete;
    logic pending_fill;

    always_ff @(posedge clk) begin
        tag_read_ready <= tag_read;

        if (latch_address)
            addr_buffer <= core_addr;

        if (latch_write_data) begin
            wr_strb_buffer <= core_write_val;
            write_data_buffer <= core_write_data;
        end

        if (latch_address) begin
            fill_addr <= {core_addr[31:CACHELINE_OFFSET], {CACHELINE_OFFSET{1'b0}}};
        end else if (incr_fill_addr) begin
            fill_addr <= fill_addr + 4;
        end

        if (trigger_fill) begin
            pending_fill <= 1'b1;
        end else if (core_flush || fill_complete) begin
            pending_fill <= 1'b0;
        end
    end


    ////////////////////////////////////////////////////////////////////////
    //// Addressing Logic //////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [1:0]  core_byte_os, buffer_byte_os, fill_byte_os;
    logic [2:0]  core_word_os, buffer_word_os, fill_word_os;
    logic [7:0]  core_index, buffer_index, fill_index;
    logic [18:0] core_tag, buffer_tag, fill_tag;
    
    assign {core_tag, core_index, core_word_os, core_byte_os} = core_addr;
    assign {buffer_tag, buffer_index, buffer_word_os, buffer_byte_os} = addr_buffer;
    assign {fill_tag, fill_index, fill_word_os, fill_byte_os} = fill_addr;
    

    ////////////////////////////////////////////////////////////////////////
    //// Tag store /////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    logic        tag_hit;
    logic        ts_wr_en;
    logic [7:0]  ts_wr_addr, ts_rd_addr;
    logic [19:0] ts_wr_data;
    logic        ts_rd_valid;
    logic [18:0] ts_rd_data;
    
    sdp_bram #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(20)
    ) tag_store (
        .wr_clk(clk),
        .wr_en(ts_wr_en),
        .wr_addr(ts_wr_addr),
        .wr_data(ts_wr_data),
        .rd_clk(clk),
        .rd_addr(ts_rd_addr),
        .rd_data({ts_rd_valid,ts_rd_data})
    );

    assign tag_hit = tag_read_ready && ts_rd_valid && (buffer_tag == ts_rd_data);


    ////////////////////////////////////////////////////////////////////////
    //// Data store ////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////// 

    logic [3:0]  ds_wr_en;
    logic [10:0] ds_wr_addr, ds_rd_addr;
    logic [31:0] ds_wr_data, ds_rd_data;
    
    dp_bram_be #(
        .ADDR_WIDTH(11),
        .DATA_WIDTH(32)
    ) data_store (
        .clk(clk),
        .wr_en(ds_wr_en),
        .wr_addr(ds_wr_addr),
        .wr_data(ds_wr_data),
        .rd_addr(ds_rd_addr),
        .rd_data(ds_rd_data)
    );

    ////////////////////////////////////////////////////////////////////////
    //// FSM ///////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic [7:0] rst_idx, next_rst_idx;

    enum {
        RESET,
        IDLE,
        WRITE,
        WRITE_WAIT_DATA,
        WRITE_WAIT_ADDR,
        WRITE_WAIT,
        CACHE_READ,
        FILL_CACHE,
        READ_WORD,
        READ_WORD_WAIT,
        CACHE_FILLED
    } state, next_state;

    always_ff @(posedge clk) begin
        if (rst) state <= RESET;
        else              state <= next_state;

        if (rst) rst_idx <= 8'd255;
        else              rst_idx <= next_rst_idx;
    end

    always_comb begin
        next_state = state;
        next_rst_idx = rst_idx;

        core_rdy = 1'b0;
        core_read_data_val = 1'b0;

        tag_read = 1'b0;
        latch_address = 1'b0;
        latch_write_data = 1'b0;

        incr_fill_addr = 1'b0;
        trigger_fill = 1'b0;
        fill_in_progress = 1'b0;
        fill_complete = 1'b0;

        ts_rd_addr = core_index;
        
        ts_wr_en = 1'b0;
        ts_wr_addr = buffer_index;
        ts_wr_data = {1'b1,buffer_tag};
        
        ds_rd_addr = {core_index, core_word_os};

        ds_wr_en = '0;
        ds_wr_addr = {fill_index, fill_word_os};
        ds_wr_data = m_axi.r_data;

        m_axi.aw_valid = 1'b0;
        m_axi.w_valid = 1'b0;

        m_axi.ar_valid = 1'b0;
        m_axi.ar_addr = 'x;
        m_axi.ar_len = 'x;

        m_axi.r_ready = 1'b0;
        core_read_data = ds_rd_data;
        

        case (state)
            RESET : begin
                ts_wr_en = 1'b1;
                ts_wr_addr = rst_idx;
                ts_wr_data = '0;

                if (rst_idx == 0)
                    next_state = IDLE;
                else
                    next_rst_idx = rst_idx - 1;
            end

            IDLE : begin
                core_rdy = 1'b1;
                if (core_write_val) begin
                    latch_address = 1'b1;
                    latch_write_data = 1'b1;
                    tag_read = 1'b1;
                    next_state = WRITE;
                end else if (core_read_val) begin
                    latch_address = 1'b1;
                    if (uncacheable_addr) begin
                        next_state = READ_WORD;
                    end else begin
                        tag_read = 1'b1;
                        next_state = CACHE_READ;
                    end
                end
            end

            WRITE : begin
                ds_wr_en = {4{tag_hit}} & wr_strb_buffer;
                ds_wr_addr = {buffer_index, buffer_word_os};
                ds_wr_data = write_data_buffer;

                m_axi.aw_valid = 1'b1;
                m_axi.w_valid = 1'b1;

                case ({m_axi.aw_ready, m_axi.w_ready})
                    2'b11 : begin
                        core_rdy = 1'b1;
                        if (core_write_val) begin
                            latch_address = 1'b1;
                            latch_write_data = 1'b1;
                            tag_read = 1'b1;
                            next_state = WRITE;
                        end else if (core_read_val) begin
                            latch_address = 1'b1;
                            if (uncacheable_addr) begin
                                next_state = READ_WORD;
                            end else begin
                                tag_read = 1'b1;
                                next_state = CACHE_READ;
                            end
                        end else begin
                            next_state = IDLE;
                        end
                    end

                    2'b10 : next_state = WRITE_WAIT_DATA;
                    2'b01 : next_state = WRITE_WAIT_ADDR;
                    2'b00 : next_state = WRITE_WAIT;
                endcase
            end

            WRITE_WAIT : begin
                m_axi.aw_valid = 1'b1;
                m_axi.w_valid = 1'b1;

                case ({m_axi.aw_ready, m_axi.w_ready})
                    2'b11 : begin
                        core_rdy = 1'b1;
                        if (core_write_val) begin
                            latch_address = 1'b1;
                            latch_write_data = 1'b1;
                            tag_read = 1'b1;
                            next_state = WRITE;
                        end else if (core_read_val) begin
                            latch_address = 1'b1;
                            if (uncacheable_addr) begin
                                next_state = READ_WORD;
                            end else begin
                                tag_read = 1'b1;
                                next_state = CACHE_READ;
                            end
                        end else begin
                            next_state = IDLE;
                        end
                    end

                    2'b10 : next_state = WRITE_WAIT_DATA;
                    2'b01 : next_state = WRITE_WAIT_ADDR;
                    2'b00 : next_state = WRITE_WAIT;
                endcase
            end

            WRITE_WAIT_DATA : begin
                m_axi.w_valid = 1'b1;
                if (m_axi.w_ready) begin
                    core_rdy = 1'b1;
                    if (core_write_val) begin
                        latch_address = 1'b1;
                        latch_write_data = 1'b1;
                        tag_read = 1'b1;
                        next_state = WRITE;
                    end else if (core_read_val) begin
                        latch_address = 1'b1;
                        if (uncacheable_addr) begin
                            next_state = READ_WORD;
                        end else begin
                            tag_read = 1'b1;
                            next_state = CACHE_READ;
                        end
                    end else begin
                        next_state = IDLE;
                    end
                end
            end

            WRITE_WAIT_ADDR : begin
                m_axi.aw_valid = 1'b1;
                if (m_axi.aw_ready) begin
                    core_rdy = 1'b1;
                    if (core_write_val) begin
                        latch_address = 1'b1;
                        latch_write_data = 1'b1;
                        tag_read = 1'b1;
                        next_state = WRITE;
                    end else if (core_read_val) begin
                        latch_address = 1'b1;
                        if (uncacheable_addr) begin
                            next_state = READ_WORD;
                        end else begin
                            tag_read = 1'b1;
                            next_state = CACHE_READ;
                        end
                    end else begin
                        next_state = IDLE;
                    end
                end
            end

            CACHE_READ : begin
                core_rdy = (tag_hit || core_flush);
                core_read_data_val = tag_hit;

                if (tag_hit || core_flush) begin
                    // pipeline writes
                    if (core_write_val) begin
                        latch_address = 1'b1;
                        latch_write_data = 1'b1;
                        tag_read = 1'b1;
                        next_state = WRITE;
                    
                    // pipeline reads
                    end else if (core_read_val) begin
                        latch_address = 1'b1;
                        if (uncacheable_addr) begin
                            next_state = READ_WORD;
                        end else begin
                            tag_read = 1'b1;
                            next_state = CACHE_READ;
                        end

                    end else begin
                        next_state = IDLE;
                    end

                end else begin
                    m_axi.ar_valid = 1'b1;
                    m_axi.ar_addr = fill_addr;
                    m_axi.ar_len = 8'd7; // 8 beats (ARLEN is length - 1)
                    trigger_fill = 1'b1;
                    fill_in_progress = 1'b1;
                    next_state = FILL_CACHE;
                end
            end

            FILL_CACHE : begin
                m_axi.r_ready = 1'b1;
                ds_wr_addr = {fill_index, fill_word_os};
                ds_wr_data = m_axi.r_data;
                fill_in_progress = 1'b1;

                if (m_axi.r_valid) begin
                    ds_wr_en = 4'hF;
                    incr_fill_addr = 1'b1;
                    if (m_axi.r_last) begin
                        // Update tag
                        ts_wr_en = 1'b1;
                        ts_wr_addr = buffer_index;
                        ts_wr_data = {1'b1,buffer_tag};                

                        // TODO can reduce the latency here by one cycle (if tag store uses bypass)
                        ds_rd_addr = {buffer_index, buffer_word_os};
                        next_state = CACHE_FILLED;
                    end
                end
            end

            CACHE_FILLED : begin
                core_read_data_val = pending_fill && ~core_flush;
                fill_complete = 1'b1;

                core_rdy = 1'b1;
                if (core_write_val) begin
                    latch_address = 1'b1;
                    latch_write_data = 1'b1;
                    tag_read = 1'b1;
                    next_state = WRITE;
                end else if (core_read_val) begin
                    latch_address = 1'b1;
                    if (uncacheable_addr) begin
                        next_state = READ_WORD;
                    end else begin
                        tag_read = 1'b1;
                        next_state = CACHE_READ;
                    end
                end else begin
                    next_state = IDLE;
                end
            end

            READ_WORD : begin
                m_axi.ar_valid = 1'b1;
                m_axi.ar_addr = addr_buffer;
                m_axi.ar_len = 8'd0; // read a single word
                next_state = READ_WORD_WAIT;
            end

            READ_WORD_WAIT : begin
                m_axi.r_ready = 1'b1;
                core_read_data = m_axi.r_data;
                if (m_axi.r_valid) begin
                    core_read_data_val = 1'b1;
                    
                    core_rdy = 1'b1;
                    if (core_write_val) begin
                        latch_address = 1'b1;
                        latch_write_data = 1'b1;
                        tag_read = 1'b1;
                        next_state = WRITE;
                    end else if (core_read_val) begin
                        latch_address = 1'b1;
                        if (uncacheable_addr) begin
                            next_state = READ_WORD;
                        end else begin
                            tag_read = 1'b1;
                            next_state = CACHE_READ;
                        end
                    end else begin
                        next_state = IDLE;
                    end
                end
            end
        endcase
    end

    
    assign m_axi.aw_addr  = addr_buffer;
    assign m_axi.aw_len   = '0;
    assign m_axi.aw_size  = '0;
    assign m_axi.aw_burst = '0;
    assign m_axi.aw_id    = MASTER_ID;
    
    assign m_axi.w_data   = write_data_buffer;
    assign m_axi.w_strb   = wr_strb_buffer;
    assign m_axi.w_last   = 1'b1;
    assign m_axi.b_ready  = 1'b1;

    assign m_axi.ar_size  = 3'b010;   // 4 bytes per beat (32-bit bus)
    assign m_axi.ar_burst = 2'b01;    // INCR burst type
    assign m_axi.ar_id    = MASTER_ID;

endmodule : cache
