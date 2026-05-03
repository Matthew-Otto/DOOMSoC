// SDRAM controller AXI wrapper

// Non-AXI compliant:
// Asserts all channels ready, but will only accept one read or write at a time
//  - Write gets priority, reads will be ignored.
// Assumes write address and data arrive on the same cycle.
// Does not respect backpressure / axi handshake during a burst. 
//  - Burst must be contiguous or data will be lost.


module sdram_axi_interface #(
    parameter int MEM_CLK_FREQ
) (
    input  logic        mem_clk,
    input  logic        reset,

    AXI_BUS.Slave       s_axi,

    output logic        O_sdram_clk,
    output logic        O_sdram_cke,
    output logic [1:0]  O_sdram_ba,       // four banks
    output logic [10:0] O_sdram_addr,     // 11 bit multiplexed address bus
    output logic        O_sdram_cs_n,     // chip select
    output logic        O_sdram_ras_n,    // row address select
    output logic        O_sdram_cas_n,    // columns address select
    output logic        O_sdram_wen_n,    // write enable
    inout  logic [31:0] IO_sdram_dq,      // 32 bit bidirectional data bus
    output logic [3:0]  O_sdram_dqm       // data mask
);

    logic        stop;
    logic        read;
    logic        write;
    logic [3:0]  write_strb;
    logic [20:0] addr;
    logic        cmd_ready;
    logic [31:0] write_data;
    logic [31:0] read_data;
    logic        read_data_val;


    enum {
        IDLE,
        WRITE_DATA,
        WRITE_RESP,
        READ_DATA
    } state, next_state;

    logic trigger_wr_resp;
    logic [2:0] r_burst_len, r_burst_cnt;

    logic aw_fire;
    logic ar_fire;
    logic w_fire;
    logic r_fire;

    assign aw_fire = s_axi.aw_valid && s_axi.aw_ready;
    assign ar_fire = s_axi.ar_valid && s_axi.ar_ready;
    assign w_fire  = s_axi.w_valid  && s_axi.w_ready;
    assign r_fire  = s_axi.r_valid  && s_axi.r_ready;

    // Constant connections
    assign write_data   = s_axi.w_data;
    assign write_strb   = s_axi.w_strb;
    assign s_axi.r_data = read_data;
    assign s_axi.b_resp = 2'b00; // OKAY
    assign s_axi.r_resp = 2'b00; // OKAY

    always_ff @(posedge mem_clk) begin
        if (reset) state <= IDLE;
        else       state <= next_state;
    end


    always_comb begin
        next_state     = state;
        
        s_axi.aw_ready = 1'b0;
        s_axi.ar_ready = 1'b0;
        s_axi.w_ready  = 1'b0;
        s_axi.b_valid  = 1'b0;
        s_axi.r_valid  = 1'b0;
        s_axi.r_last   = 1'b0;

        trigger_wr_resp = 1'b0;
        write = 1'b0;
        read  = 1'b0;
        stop  = 1'b0;
        addr  = '0;

        case (state)
            IDLE: begin
                // Assert ready early, relying on SDRAM cmd_ready
                s_axi.aw_ready = cmd_ready;
                s_axi.ar_ready = cmd_ready && ~s_axi.aw_valid;
                // Zero-bubble write data ready
                s_axi.w_ready = ~s_axi.ar_valid; 

                // Command dispatch logic & State Transitions
                if (aw_fire && w_fire) begin
                    write = 1'b1;
                    addr  = s_axi.aw_addr[22:2];
                    
                    // Handle early termination if a single-beat write arrives immediately
                    if (s_axi.w_last) begin
                        stop = 1'b1;
                        trigger_wr_resp = 1'b1;
                        next_state = IDLE;
                    end else begin
                        next_state = WRITE_DATA;
                    end
                end else if (ar_fire) begin
                    read  = 1'b1;
                    addr  = s_axi.ar_addr[22:2];
                    next_state = READ_DATA;
                end
            end

            WRITE_DATA: begin
                s_axi.w_ready = 1'b1;

                if (w_fire && s_axi.w_last) begin
                    stop = 1'b1;
                    trigger_wr_resp = 1'b1;
                    next_state = IDLE;
                end
            end

            READ_DATA: begin
                s_axi.r_valid = read_data_val;
                s_axi.r_last  = (r_burst_cnt == r_burst_len);
                
                if (r_fire && s_axi.r_last) begin
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // Write response
    always_ff @(posedge mem_clk) begin
        if (reset || (s_axi.b_ready && s_axi.b_valid)) begin
            s_axi.b_valid <= 1'b0;
        end else if (trigger_wr_resp) begin
            s_axi.b_valid <= 1'b1;
        end
    end

    // Read Beat Tracking
    always_ff @(posedge mem_clk) begin
        if (reset) begin
            r_burst_len <= '0;
            r_burst_cnt <= '0;
        end else begin
            if (ar_fire) begin
                r_burst_len <= s_axi.ar_len[2:0];
                r_burst_cnt <= '0;
            end else if (read_data_val) begin
                r_burst_cnt <= r_burst_cnt + 3'd1;
            end
        end
    end


    sdram_controller #(
        .MEM_CLK_FREQ(MEM_CLK_FREQ)
    ) sdram_controller_i (
        .mem_clk,
        .reset,
        .stop,
        .read,
        .write,
        .write_strb,
        .addr,
        .cmd_ready,
        .write_data,
        .read_data,
        .read_data_val,
        .O_sdram_clk,
        .O_sdram_cke,
        .O_sdram_ba,
        .O_sdram_addr,
        .O_sdram_cs_n,
        .O_sdram_ras_n,
        .O_sdram_cas_n,
        .O_sdram_wen_n,
        .IO_sdram_dq,
        .O_sdram_dqm
    );

endmodule : sdram_axi_interface