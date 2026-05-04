// bootloader ROM connected to the memory bus via AXI4
// Not AXI compliant - backpressure during a read burst will drop data.

module axi4_boot_rom #(
    parameter int LOG_SIZE     = 10,
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 32,
    parameter int ID_WIDTH     = 1,
    parameter string INIT_FILE = "bootloader.mem"
)(
    input  logic clk,
    input  logic reset,
    
    AXI_BUS.Slave s_axi
);

    ////////////////////////////////////////////////////////////////////////
    //// ROM ///////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    localparam int SIZE = 1 << LOG_SIZE;
    logic [DATA_WIDTH-1:0] rom [0:SIZE-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, rom);
        end
    end

    logic read;
    logic read_last;
    logic [LOG_SIZE-1:0] bram_addr;

    always_ff @(posedge clk) begin
        s_axi.r_data <= rom[bram_addr];
        s_axi.r_valid <= read;
        s_axi.r_last <= read_last;
    end


    ////////////////////////////////////////////////////////////////////////
    //// AXI Read Port /////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [LOG_SIZE-1:0] word_addr;
    logic [LOG_SIZE-1:0] burst_addr;
    logic [ID_WIDTH-1:0] r_id;
    logic [7:0] r_burst_len, r_burst_cnt;

    assign word_addr = s_axi.ar_addr[2+:LOG_SIZE];
    assign s_axi.r_id = r_id;
    assign s_axi.r_resp = 2'b00;

    enum {
        IDLE,
        READ
    } state, next_state;

    always_ff @(posedge clk) begin
        if (reset) state <= IDLE;
        else       state <= next_state;
    end


    always_comb begin
        next_state = state;
        read = 1'b0;
        read_last = 1'b0;
        bram_addr = '0;

        s_axi.ar_ready = 1'b0;

        case (state)
            IDLE : begin
                s_axi.ar_ready = 1'b1;
                if (s_axi.ar_valid) begin
                    read = 1'b1;
                    bram_addr = word_addr;
                    next_state = READ;
                end
            end

            READ : begin
                read = 1'b1;
                bram_addr = burst_addr;
                if (r_burst_len == r_burst_cnt) begin
                    read_last = 1'b1;
                    next_state = IDLE;
                end
            end
        endcase
    end


    always_ff @(posedge clk) begin
        if (reset) begin
            r_burst_len <= '0;
            r_burst_cnt <= '0;
        end else begin
            case (state)
                IDLE : begin
                    if (s_axi.ar_valid) begin
                        r_burst_len <= s_axi.ar_len;
                        r_burst_cnt <= 1;
                        burst_addr <= word_addr + 4;
                        r_id <= s_axi.ar_id;
                    end
                end

                READ : begin
                    if (s_axi.r_ready) begin
                        burst_addr <= burst_addr + 4;
                        r_burst_cnt <= r_burst_cnt + 1;
                    end
                end
            endcase
        end
    end




    // TODO BOZO: Blackhole any writes to prevent bus lockup
    assign s_axi.b_valid  = 1'b0; // TODO loopback
    assign s_axi.b_id     = '0; // TODO loopback
    assign s_axi.b_resp   = 2'b10; // SLVERR
    
    assign s_axi.aw_ready = 1'b1;
    assign s_axi.w_ready  = 1'b0;

endmodule : axi4_boot_rom
