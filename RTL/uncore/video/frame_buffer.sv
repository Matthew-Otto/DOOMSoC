module frame_buffer #(
    parameter int ADDR_WIDTH,
    parameter int DATA_WIDTH,
    parameter int ID_WIDTH
) (
    input  logic        bus_clk,
    input  logic        bus_clk_rst,
    input  logic        p_clk,
    input  logic        p_clk_rst,

    AXI_BUS.Slave       s_axi,

    input  logic [15:0] read_addr,
    output logic [7:0]  read_data
);


    ////////////////////////////////////////////////////////////////////////
    //// Read Byte Mux /////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [13:0] bram_read_addr;
    logic [1:0]  read_byte_offset;
    logic [31:0] bram_read_word;

    assign bram_read_addr = read_addr[15:2];

    always_ff @(posedge p_clk)
        read_byte_offset <= read_addr[1:0];

    assign read_data = bram_read_word[read_byte_offset*8+:8];


    ////////////////////////////////////////////////////////////////////////
    //// AXI Write Logic ///////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    enum {
        IDLE,
        WRITE
    } state, next_state;

    logic                  b_valid_reg;
    logic [ID_WIDTH-1:0]   b_id_reg;

    logic [3:0]  bram_wren;
    logic [13:0] bram_write_addr;
    logic [31:0] bram_write_data;

    logic [13:0] aligned_addr;
    logic [13:0] write_addr, next_write_addr;

    assign aligned_addr = s_axi.aw_addr[15:2];
    assign bram_write_data = s_axi.w_data;


    always_ff @(posedge bus_clk) begin
        if (bus_clk_rst) state <= IDLE;
        else             state <= next_state;

        write_addr <= next_write_addr;
    end

    always_comb begin
        next_state = state;
        next_write_addr = write_addr;

        s_axi.aw_ready = 1'b0;
        s_axi.w_ready = 1'b0;

        bram_wren = '0;
        bram_write_addr = '0;

        case (state)
            IDLE : begin
                s_axi.aw_ready = 1'b1;
                s_axi.w_ready = 1'b1;
                bram_write_addr = aligned_addr;
                
                if (s_axi.aw_valid) begin
                    if (s_axi.w_valid) begin
                        bram_wren = s_axi.w_strb;
                        next_write_addr = aligned_addr + 1;
                        if (!s_axi.w_last)
                            next_state = WRITE;
                    end else begin
                        next_write_addr = aligned_addr;
                        next_state = WRITE;
                    end
                end
            end

            WRITE : begin
                s_axi.w_ready = 1'b1;
                bram_write_addr = write_addr;
                
                if (s_axi.w_valid) begin
                    bram_wren = s_axi.w_strb;
                    next_write_addr = write_addr + 1;

                    if (s_axi.w_last) begin
                        // TODO may need to accept address here to eliminate bubbles
                        next_state = IDLE;
                    end
                end
            end
        endcase
    end

    // Write response logic
    always_ff @(posedge bus_clk) begin
        b_valid_reg <= s_axi.w_last;
        if (s_axi.aw_ready && s_axi.aw_valid)
            b_id_reg <= s_axi.aw_id;
    end

    assign s_axi.b_id = b_id_reg;
    assign s_axi.b_valid = b_valid_reg;
    assign s_axi.b_resp = 2'b0;


    ////////////////////////////////////////////////////////////////////////
    //// Data Store ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    sdp_bram_be #(
        .ADDR_WIDTH(14),
        .DATA_WIDTH(32)
    ) frame_buffer_mem (
        .wr_clk(bus_clk),
        .wr_en(bram_wren),
        .wr_addr(bram_write_addr),
        .wr_data(bram_write_data),
        .rd_clk(p_clk),
        .rd_addr(bram_read_addr),
        .rd_data(bram_read_word)
    );

endmodule : frame_buffer
