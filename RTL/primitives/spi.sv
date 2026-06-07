module spi (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] tx_byte,
    input  logic       tx_byte_valid,
    output logic       tx_byte_ready,
    output logic [7:0] rx_byte,
    output logic       rx_byte_valid,

    output logic       clk_en,
    output logic       mosi,
    input  logic       miso
);

    logic load_reg;
    logic shift;
    logic [7:0] tx_reg;

    logic [2:0] shift_cnt, next_shift_cnt;

    enum {
        IDLE,
        SHIFT
    } state, next_state;

    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else     state <= next_state;

        shift_cnt <= next_shift_cnt;
    end

    always_comb begin
        next_state = state;
        next_shift_cnt = shift_cnt;

        load_reg = 1'b0;
        shift = 1'b0;
        tx_byte_ready = 1'b0;
        rx_byte_valid = 1'b0;

        case (state)
            IDLE : begin
                tx_byte_ready = 1'b1;
                if (tx_byte_valid) begin
                    load_reg = 1'b1;
                    next_shift_cnt = 3'd7;
                    next_state = SHIFT;
                end
            end

            SHIFT : begin
                shift = 1'b1;
                if (shift_cnt == 0) begin
                    rx_byte_valid = 1'b1;
                    tx_byte_ready = 1'b1;
                    if (tx_byte_valid) begin
                        load_reg = 1'b1;
                        next_shift_cnt = 3'd7;
                    end else begin
                        next_state = IDLE;
                    end
                end else begin
                    next_shift_cnt = shift_cnt - 1;
                end
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (load_reg) begin
            tx_reg <= tx_byte;
        end else if (shift) begin
            for (int i = 1; i < 8; i=i+1) begin
                tx_reg[i] <= tx_reg[i-1];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (shift) begin
            rx_byte[0] <= miso;
            for (int i = 1; i < 8; i=i+1) begin
                rx_byte[i] <= rx_byte[i-1];
            end
        end
    end

    assign mosi = tx_reg[7];
    assign clk_en = shift;

endmodule : spi
