module sd_csr (
    input  logic clk,
    input  logic rst,

    AXI_LITE.Slave s_axi,

    output logic        init_clk,

    output logic        set_cs,
    output logic        clear_cs,
    output logic        block_write,
    output logic        block_read,

    input  logic        success,
    input  logic        error,

    output logic        spi_write,
    output logic [7:0]  spi_data_wr,
    input  logic        spi_read,
    input  logic [7:0]  spi_data_rd,

    output logic [31:0] sd_block_addr
);

    // ==========================================
    // AXI4-Lite Write Interface
    // ==========================================
    enum {
        WR_IDLE,
        AW_WAIT,
        W_WAIT,
        W_RESP
    } axi_wr_state, next_axi_wr_state;


    logic wr_en;
    logic latch_wr_addr;
    logic latch_wr_data;
    logic [31:0] write_addr, write_addr_buffer;
    logic [3:0]  write_strb, write_strb_buffer;
    logic [31:0] write_data, write_data_buffer;

    always_ff @(posedge clk) begin
        if (latch_wr_addr) begin
            write_addr_buffer <= s_axi.aw_addr;
        end

        if (latch_wr_data) begin
            write_strb_buffer <= s_axi.w_strb;
            write_data_buffer <= s_axi.w_data;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) axi_wr_state <= WR_IDLE;
        else axi_wr_state <= next_axi_wr_state;
    end

    always_comb begin
        next_axi_wr_state = axi_wr_state;

        wr_en = 1'b0;
        latch_wr_addr = 1'b0;
        latch_wr_data = 1'b0;
        s_axi.aw_ready = 1'b0;
        s_axi.w_ready = 1'b0;
        s_axi.b_valid = 1'b0;
        s_axi.b_resp = '0; // Always succeed

        write_addr = write_addr_buffer;
        write_strb = write_strb_buffer;
        write_data = write_data_buffer;

        case (axi_wr_state)
            WR_IDLE : begin
                s_axi.aw_ready = 1'b1;
                s_axi.w_ready = 1'b1;

                case ({s_axi.aw_valid, s_axi.w_valid})
                    2'b10 : begin
                        latch_wr_addr = 1'b1;
                        next_axi_wr_state = W_WAIT;
                    end
                    2'b01 : begin
                        latch_wr_data = 1'b1;
                        next_axi_wr_state = AW_WAIT;
                    end
                    2'b11 : begin
                        wr_en = 1'b1;
                        write_addr = s_axi.aw_addr;
                        write_strb = s_axi.w_strb;
                        write_data = s_axi.w_data;
                        next_axi_wr_state = W_RESP;
                    end
                    default;
                endcase
            end

            AW_WAIT : begin
                s_axi.aw_ready = 1'b1;
                if (s_axi.aw_valid) begin
                    wr_en = 1'b1;
                    write_addr = s_axi.aw_addr;
                    next_axi_wr_state = W_RESP;
                end
            end

            W_WAIT : begin
                s_axi.w_ready = 1'b1;
                if (s_axi.w_valid) begin
                    wr_en = 1'b1;
                    write_strb = s_axi.w_strb;
                    write_data = s_axi.w_data;
                    next_axi_wr_state = W_RESP;
                end
            end

            W_RESP : begin
                s_axi.b_valid = 1'b1;
                if (s_axi.b_ready) begin
                    next_axi_wr_state = WR_IDLE;
                end
            end
        endcase
    end


    // ==========================================
    // AXI4-Lite Read Interface
    // ==========================================
    enum {
        RD_IDLE,
        RD_WAIT
    } axi_rd_state, next_axi_rd_state;


    logic rd_en;
    logic latch_rd_addr;
    logic [31:0] rd_addr, rd_addr_buffer;
    logic [31:0] rd_data_buffer;

    always_ff @(posedge clk) begin
        if (latch_rd_addr)
            rd_addr_buffer <= s_axi.ar_addr;
    end

    always_ff @(posedge clk) begin
        if (rst) axi_rd_state <= RD_IDLE;
        else     axi_rd_state <= next_axi_rd_state;
    end

    always_comb begin
        next_axi_rd_state = axi_rd_state;
        
        rd_en = 1'b0;
        latch_rd_addr = 1'b0;
        s_axi.ar_ready = 1'b0;
        s_axi.r_valid = 1'b0;
        s_axi.r_resp = '0; // Always succeed
        s_axi.r_data = rd_data_buffer;

        rd_addr = rd_addr_buffer;

        case (axi_rd_state)
            RD_IDLE : begin
                s_axi.ar_ready = 1'b1;
                if (s_axi.ar_valid) begin
                    latch_rd_addr = 1'b1;
                    rd_en = 1'b1;
                    rd_addr = s_axi.ar_addr;
                    next_axi_rd_state = RD_WAIT;
                end
            end

            RD_WAIT : begin
                s_axi.r_valid = 1'b1;
                if (s_axi.r_ready) begin
                    next_axi_rd_state = RD_IDLE;
                end else begin
                    rd_en = 1'b1;
                end
            end
        endcase
    end


    logic write_stat;
    logic new_init_clk;
    logic write_block_addr;
    logic [7:0] spi_byte;
    logic busy;

    //// Write mux
    always_comb begin
        write_stat = 1'b0;
        set_cs = 1'b0;
        clear_cs = 1'b0;
        block_write = 1'b0;
        block_read = 1'b0;

        spi_write = 1'b0;
        spi_data_wr = 'x;

        write_block_addr = 1'b0;

        if (wr_en) begin // BOZO ignoring write strobe
            case (write_addr[3:0])
                4'h0 : begin
                    write_stat = 1'b1;
                    {block_read,block_write,clear_cs,set_cs,new_init_clk} = write_data;
                end
                4'h4 : begin
                    spi_write = 1'b1;
                    spi_data_wr = write_data[7:0];
                end
                4'h8 : write_block_addr = 1'b1;
                default;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (rst)
            init_clk <= 1;
        else if (write_stat)
            init_clk <= new_init_clk;

        if (rst) begin
            spi_byte <= '0;
            busy <= 1'b0;
        end else if (spi_write) begin
            spi_byte <= spi_data_wr;
            busy <= 1'b1;
        end else if (spi_read) begin
            spi_byte <= spi_data_rd;
            busy <= 1'b0;
        end

        if (rst)
            sd_block_addr <= '0;
        else if (write_block_addr)
            sd_block_addr <= write_data;
    end

    //// Read mux
    always_ff @(posedge clk) begin
        if (rd_en) begin
            case (rd_addr[3:0])
                4'h0 : rd_data_buffer <= {21'b0,error,success,busy,7'b0,init_clk};
                4'h4 : rd_data_buffer <= {24'b0,spi_byte};
                4'h8 : rd_data_buffer <= sd_block_addr;
                default;
            endcase
        end
    end

endmodule : sd_csr
