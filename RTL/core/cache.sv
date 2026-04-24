// 256 bit cachelines
// direct mapped
// write through (dcache)

// CPU will issue read address to core_read and stall until core_read_valid is asserted
// in the background, cache will issue a read to SDRAM 

// 8KB icache
module icache (
    input  logic clk,
    input  logic rst,

    input  logic [31:0] core_addr,
    output logic [31:0] core_read,
    output logic        core_read_valid,

    AXI_BUS.Master m_axi
);

    //// Core Addressing
    logic [1:0]  byte_offset;
    logic [2:0]  word_offset;
    logic [7:0]  index;
    logic [18:0] tag;
    logic [10:0] bram_addr;

    assign {tag, index, word_offset, byte_offset} = core_addr;
    assign bram_addr = {index, word_offset};

    //// Core Control
    logic valid_read;
    logic [18:0] tag_read;
    logic tag_match;

    //// Bus Addressing
    logic [31:0] write_addr;
    logic [31:0] write_data;

    logic [1:0]  write_byte_offset;
    logic [2:0]  write_word_offset;
    logic [7:0]  write_index;
    logic [18:0] write_tag;
    logic [10:0] write_bram_addr;

    assign {write_tag, write_index, write_word_offset, write_byte_offset} = write_addr;
    assign write_bram_addr = {write_index, write_word_offset};

    //// Bus Control
    logic        write_en;
    logic        tag_valid;
    logic [7:0]  tag_write_index;
    logic [18:0] tag_write_data;


    ////////////////////////////////////////////////////////////////////////
    //// rst Logic ///////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [7:0] rst_idx;
    logic rst_active;

    always_ff @(posedge clk) begin
        if (rst) begin
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
    //// Tag store /////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [19:0] tag_store [0:255]; // valid, tag

    assign tag_write_index = rst_active ? rst_idx : write_index;
    assign tag_write_data = rst_active ? '0 : {tag_valid,write_tag};

    always_ff @(posedge clk) begin
        if (write_en || rst_active)
            tag_store[write_index] <= tag_write_data;

        if (rst)
            {valid_read,tag_read} <= '0;
        else
            {valid_read,tag_read} <= tag_store[index];
    end
    assign tag_match = (tag == tag_read) && ~rst_active;


    ////////////////////////////////////////////////////////////////////////
    //// Data store ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [31:0] data_store [0:2047];

    always_ff @(posedge clk) begin
        if (write_en)
            data_store[write_bram_addr] <= write_data;

        core_read <= data_store[bram_addr];
    end

    assign core_read_valid = valid_read && tag_match;


    ////////////////////////////////////////////////////////////////////////
    //// AXI Port //////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    enum logic [1:0] {
        STATE_IDLE,
        STATE_AR_REQ,
        STATE_R_WAIT
    } state, next_state;
    logic [31:0] fetch_addr, next_fetch_addr;

    always_ff @(posedge clk) begin
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
        write_en   = 1'b0;
        write_addr = fetch_addr;
        write_data = m_axi.r_data;

        case (state)
            STATE_IDLE: begin
                // If the CPU is requesting an address that misses, and we aren't rstting
                if (!core_read_valid && !rst_active) begin
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
                    write_en = 1'b1;
                    next_fetch_addr = fetch_addr + 32'd4; 

                    if (m_axi.r_last) begin
                        // Assert valid ONLY on the final beat of the burst
                        tag_valid = 1'b1;
                        next_state = STATE_IDLE;
                    end
                end
            end
            
            default: next_state = STATE_IDLE;
        endcase
    end

    // ---------------------------------------------------------------------
    // AXI Channel Tie-offs
    // ---------------------------------------------------------------------

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


endmodule : icache
