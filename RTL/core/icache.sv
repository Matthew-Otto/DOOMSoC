// 8KB icache
// 256 bit cachelines
// direct mapped

// CPU will issue read address to core_instr and stall until core_instr_val is asserted
// in the background, cache will issue a read to SDRAM 

module icache (
    input  logic        core_clk,
    input  logic        bus_clk,
    input  logic        rst,

    input  logic        flush,
    input  logic [31:0] core_addr,
    input  logic        core_read_val,
    output logic        core_rdy,
    
    output logic [31:0] core_instr,
    output logic        core_instr_val,

    AXI_BUS.Master      m_axi
);


    //// Core Control
    logic valid_tag;
    logic [18:0] tag_read;
    logic tag_match;
    logic read_active;
    logic miss;
    logic pending_fill;
    logic suppress;
    logic [31:0] core_addr_buffer;

    //// Core Addressing
    logic [1:0]  byte_offset;
    logic [2:0]  word_offset;
    logic [7:0]  index;
    logic [18:0] tag;
    logic [10:0] bram_addr;

    assign {tag, index, word_offset, byte_offset} = pending_fill ? core_addr_buffer : core_addr;
    assign bram_addr = {index, word_offset};

    //// Bus Addressing
    logic [31:0] write_addr, next_write_addr;
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
    logic        cacheline_filled;
    logic [7:0]  tag_write_index;
    logic [19:0] tag_write_data;


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
    //// Tag store /////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    assign tag_write_index = rst_active ? rst_idx : write_index;
    assign tag_write_data = rst_active ? '0 : {cacheline_filled,write_tag};

    dual_port_bram #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(20)
    ) tag_store (
        .clk(core_clk),
        .wr_en(write_en || rst_active),
        .write_addr(tag_write_index),
        .write_data(tag_write_data),
        .read_addr(index),
        .read_data({valid_tag,tag_read})
    );

    assign tag_match = (tag == tag_read);


    ////////////////////////////////////////////////////////////////////////
    //// Data store ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    dual_port_bram #(
        .ADDR_WIDTH(11),
        .DATA_WIDTH(32)
    ) data_store (
        .clk(core_clk),
        .wr_en(write_en),
        .write_addr(write_bram_addr),
        .write_data(write_data),
        .read_addr(bram_addr),
        .read_data(core_instr)
    );

    assign core_instr_val = ~rst_active && ~flush && ~suppress && (valid_tag && tag_match);


    ////////////////////////////////////////////////////////////////////////
    //// Read Status Tracking //////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    always_ff @(posedge core_clk) begin
        if (rst_active)
            read_active <= 0;
        else
            read_active <= (core_rdy && core_read_val);

        // make miss sticky until the cacheline is filled
        if (rst || cacheline_filled)
            pending_fill <= 0;
        else if (miss)
            pending_fill <= 1;

        // block output if a flush occurs during a fill
        if (rst || cacheline_filled)
            suppress <= 1'b0;
        else if (flush && (miss || pending_fill))
            suppress <= 1'b1;
        
        // save addresses for later fills
        if (core_rdy && core_read_val)
            core_addr_buffer <= core_addr;
    end

    assign miss = ~rst_active && read_active && ~(valid_tag && tag_match);

    assign core_rdy = ~(rst_active || miss || pending_fill);


    ////////////////////////////////////////////////////////////////////////
    //// AXI Port //////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    enum logic [1:0] {
        STATE_IDLE,
        STATE_AR_REQ,
        STATE_R_WAIT
    } state, next_state;

    always_ff @(posedge bus_clk) begin
        if (rst) begin
            state      <= STATE_IDLE;
            write_addr <= '0;
        end else begin
            state      <= next_state;
            write_addr <= next_write_addr;
        end
    end

    always_comb begin
        next_state      = state;
        next_write_addr = write_addr;

        // Default AXI driver states
        m_axi.ar_valid = 1'b0;
        m_axi.r_ready  = 1'b0;
        m_axi.ar_addr  = {core_addr[31:5], 5'b00000};

        // Default BRAM driver states
        write_en   = 1'b0;
        write_data = m_axi.r_data;
        cacheline_filled = 1'b0;

        case (state)
            STATE_IDLE: begin
                if (miss || pending_fill) begin
                    next_write_addr = {core_addr[31:5], 5'b00000};
                    m_axi.ar_valid = 1'b1;
                    if (m_axi.ar_ready)
                        next_state = STATE_R_WAIT;
                    else
                        next_state = STATE_AR_REQ;
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
                    next_write_addr = write_addr + 32'd4; 

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
