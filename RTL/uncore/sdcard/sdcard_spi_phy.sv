module sdcard_spi_phy #(
    parameter int ADDR_WIDTH=8
) (
    input  logic clk,
    input  logic rst,

    // manual SPI byte interface
    input  logic       spi_send_byte,
    input  logic [7:0] spi_wr_byte,
    output logic       spi_byte_return,
    output logic [7:0] spi_rd_byte,

    input  logic       core_set_cs,
    input  logic       core_clear_cs,
    output logic       busy,
    output logic       success,
    output logic       error,

    // automated block transfers
    input  logic        write_block,
    input  logic        read_block,
    input  logic [31:0] block_addr,

    // data buffer interface
    output logic [ADDR_WIDTH-1:0] addr,
    input  logic [31:0]           read_data,
    output logic [3:0]            write_en,
    output logic [31:0]           write_data,

    // SPI interface
    output logic sd_clk,
    output logic mosi,
    input  logic miso,
    output logic cs
);

    localparam logic [7:0] CMD0  = 8'h40;
    localparam logic [7:0] CMD8  = 8'h48;
    localparam logic [7:0] CMD17 = 8'h51;
    localparam logic [7:0] CMD24 = 8'h58;
    localparam logic [7:0] CMD55 = 8'h77;
    localparam logic [7:0] CMD58 = 8'h7A;
    localparam logic [7:0] END_BIT = 8'h01;
    localparam logic [7:0] DATA_TOKEN = 8'hFE;
    localparam logic [7:0] DUMMY_BYTE = 8'hFF;


    // SPI driver
    logic [7:0] tx_byte;
    logic       tx_byte_valid;
    logic       tx_byte_ready;
    logic [7:0] rx_byte;
    logic       rx_byte_valid;
    // chipselect
    logic set_cs, clear_cs;


    logic set_read_active, set_write_active;
    logic read_active, write_active;
    logic [8:0] idx, next_idx;

    enum {
        RESET,
        IDLE,
        SINGLE_TRANSFR,
        SEND_READ_CMD,
        SEND_WRITE_CMD,
        SEND_ADDR,
        SEND_CHKSUM,
        WAIT_R1,
        READ_GAP,
        READ_BLOCK,
        READ_CRC,
        WRITE_GAP,
        WRITE_START,
        WRITE_BLOCK,
        WRITE_CRC,
        WAIT_WR_RESP,
        WAIT_WR_COMMIT,
        ERROR
    } state, next_state;

    always_ff @(posedge clk) begin
        if (rst) state <= RESET;
        else     state <= next_state;

        if (rst) idx <= 0;
        else     idx <= next_idx;
    end

    always_comb begin
        next_state = state;
        next_idx = idx;

        busy = 1'b1;

        set_read_active = 1'b0;
        set_write_active = 1'b0;

        tx_byte = '0;
        tx_byte_valid = 1'b0;
        spi_byte_return = 1'b0;

        write_en = '0;
        addr = '0;

        set_cs = 1'b0;
        clear_cs = 1'b0;

        case (state)
            RESET : begin
                set_cs = 1'b1;
                next_state = IDLE;
            end

            IDLE : begin
                tx_byte = DUMMY_BYTE;
                if (tx_byte_ready) begin
                    busy = 1'b0;
                    if (spi_send_byte) begin
                        tx_byte_valid = 1'b1;
                        tx_byte = spi_wr_byte;
                        next_state = SINGLE_TRANSFR;
                    end if (read_block) begin
                        tx_byte_valid = 1'b1;
                        clear_cs = 1'b1;
                        next_state = SEND_READ_CMD;
                    end else if (write_block) begin
                        tx_byte_valid = 1'b1;
                        clear_cs = 1'b1;
                        next_state = SEND_WRITE_CMD;
                    end
                end
            end

            SINGLE_TRANSFR : begin
                if (rx_byte_valid) begin
                    spi_byte_return = 1'b1;
                    next_state = IDLE;
                end
            end

            SEND_READ_CMD : begin
                tx_byte = CMD17;
                tx_byte_valid = 1'b1;
                set_read_active = 1'b1;
                if (tx_byte_ready) begin
                    next_idx = 3;
                    next_state = SEND_ADDR;
                end
            end

            SEND_WRITE_CMD : begin
                tx_byte = CMD24;
                tx_byte_valid = 1'b1;
                set_write_active = 1'b1;
                if (tx_byte_ready) begin
                    next_idx = 3;
                    next_state = SEND_ADDR;
                end
            end

            SEND_ADDR : begin
                tx_byte = block_addr[idx*8+:8];
                tx_byte_valid = 1'b1;
                if (tx_byte_ready) begin
                    if (idx == 0)
                        next_state = SEND_CHKSUM;
                    else
                        next_idx = idx - 1;
                end
            end

            SEND_CHKSUM : begin
                tx_byte_valid = 1'b1;
                tx_byte = END_BIT;
                if (tx_byte_ready)
                    next_state = WAIT_R1;
            end

            WAIT_R1 : begin
                tx_byte_valid = 1'b1;
                tx_byte = DUMMY_BYTE;
                if (rx_byte_valid) begin
                    if (!rx_byte[7]) begin
                        next_idx = 0;
                        if (|rx_byte[6:0])
                            next_state = ERROR;
                        else if (read_active)
                            next_state = READ_GAP;
                        else if (write_active)
                            next_state = WRITE_GAP;
                    end
                end
            end

            READ_GAP : begin
                tx_byte_valid = 1'b1;
                tx_byte = DUMMY_BYTE;
                if (rx_byte_valid && (rx_byte == DATA_TOKEN))
                    next_state = READ_BLOCK;
            end

            READ_BLOCK : begin
                tx_byte_valid = 1'b1;
                tx_byte = DUMMY_BYTE;

                addr = idx[8:2];
                if (rx_byte_valid) begin
                    write_en = 1'b1 << idx[1:0];
                    if (idx == 511) begin
                        next_idx = 1;
                        next_state = READ_CRC;
                    end else begin
                        next_idx = idx + 1;
                    end
                end
            end

            READ_CRC : begin
                tx_byte_valid = 1'b1;
                tx_byte = DUMMY_BYTE;
                if (tx_byte_ready) begin
                    if (idx == 0) begin
                        set_cs = 1'b1;
                        next_state = IDLE;
                    end else begin
                        next_idx = idx - 1;
                    end
                end
            end

            WRITE_GAP : begin
                tx_byte_valid = 1'b1;
                tx_byte = DUMMY_BYTE;
                if (tx_byte_ready)
                   next_state = WRITE_START;
            end

            WRITE_START : begin
                tx_byte_valid = 1'b1;
                tx_byte = DATA_TOKEN;
                if (tx_byte_ready) begin
                    next_idx = 0;
                    next_state = WRITE_BLOCK;
                end
            end

            WRITE_BLOCK : begin
                tx_byte_valid = 1'b1;
                tx_byte = read_data[idx[1:0]*8+:8];
                addr = idx[8:2];
                if (tx_byte_ready) begin
                    if (idx == 511) begin
                        next_idx = 1;
                        next_state = WRITE_CRC;
                    end else begin
                        next_idx = idx + 1;
                    end
                end
            end

            WRITE_CRC : begin
                tx_byte_valid = 1'b1;
                tx_byte = DUMMY_BYTE;
                if (tx_byte_ready) begin
                    if (idx == 0)
                        next_state = WAIT_WR_RESP;
                    else
                        next_idx = idx - 1;
                end
            end

            WAIT_WR_RESP : begin
                tx_byte_valid = 1'b1;
                tx_byte = DUMMY_BYTE;
                if (rx_byte_valid) begin
                    if (!rx_byte[7]) begin
                        if (rx_byte[4:0] == 5'h5)
                            next_state = WAIT_WR_COMMIT;
                        else if (rx_byte[4:0] == 5'hB) // CRC error
                            next_state = ERROR;
                        else if (rx_byte[4:0] == 5'hD) // other Error
                            next_state = ERROR;
                    end
                end
            end

            WAIT_WR_COMMIT : begin
                tx_byte_valid = 1'b1;
                tx_byte = DUMMY_BYTE;
                if (rx_byte_valid) begin
                    if (rx_byte == 8'hFF) begin
                        set_cs = 1'b1;
                        next_state = IDLE;
                    end
                end
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (state == IDLE)
            read_active <= 1'b0;
        else if (set_read_active)
            read_active <= 1'b1;

        if (state == IDLE)
            write_active <= 1'b0;
        else if (set_write_active)
            write_active <= 1'b1;
    end

    assign write_data = {4{rx_byte}};
    assign spi_rd_byte = rx_byte;


    logic clk_en;

    spi spi_i (
        .clk,
        .rst,
        .tx_byte,
        .tx_byte_valid,
        .tx_byte_ready,
        .rx_byte,
        .rx_byte_valid,
        .clk_en,
        .mosi,
        .miso
    );

    always_ff @(posedge clk) begin
        if (rst || set_cs || core_set_cs) cs <= 1'b1;
        else if (clear_cs || core_clear_cs) cs <= 1'b0;
    end

    assign sd_clk = clk_en & clk;

endmodule : sdcard_spi_phy
