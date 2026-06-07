module axi_bram_intf #(
    parameter int LOG_SIZE   = 10,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 1
) (
    input  logic clk,
    input  logic rst,

    AXI_BUS.Slave s_axi,

    // Single-Port BRAM Interface
    output logic                      rd_en,
    output logic [(DATA_WIDTH/8)-1:0] wr_en,
    output logic [LOG_SIZE-1:0]       addr,
    output logic [DATA_WIDTH-1:0]     wr_data,
    input  logic [DATA_WIDTH-1:0]     rd_data
);

    ////////////////////////////////////////////////////////////////////////
    //// Arbitration Logic /////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    logic int_wr_req,  int_wr_grant;
    logic int_rd_req,  int_rd_grant;
    
    logic [(DATA_WIDTH/8)-1:0] int_wr_en;
    logic [LOG_SIZE-1:0]       int_wr_addr;
    logic                      int_rd_en;
    logic [LOG_SIZE-1:0]       int_rd_addr;

    // Write Priority Arbitration
    assign int_wr_grant = int_wr_req; 
    assign int_rd_grant = int_rd_req && !int_wr_req;

    // Multiplexing signals to the single BRAM port
    assign wr_en = int_wr_grant ? int_wr_en : '0;
    assign rd_en = int_rd_grant ? int_rd_en : 1'b0;
    assign addr = int_wr_grant ? int_wr_addr : int_rd_addr;

    assign wr_data = s_axi.w_data;

    ////////////////////////////////////////////////////////////////////////
    //// AXI Write Logic ///////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    enum {
        WR_IDLE,
        WR_ACTIVE
    } wr_state, wr_next_state;

    logic [LOG_SIZE-1:0] write_addr, next_write_addr;
    logic                b_channel_stall;
    logic                b_valid_reg;
    logic [ID_WIDTH-1:0] b_id_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_state    <= WR_IDLE;
            write_addr  <= '0;
            b_valid_reg <= 1'b0;
            b_id_reg    <= '0;
        end else begin
            wr_state   <= wr_next_state;
            write_addr <= next_write_addr;

            // B-Channel Handshake
            if (s_axi.b_valid && s_axi.b_ready) begin
                b_valid_reg <= 1'b0;
            end else if (s_axi.w_valid && s_axi.w_ready && s_axi.w_last) begin
                b_valid_reg <= 1'b1;
            end

            // Capture ID on address phase
            if (s_axi.aw_ready && s_axi.aw_valid) begin
                b_id_reg <= s_axi.aw_id;
            end
        end
    end

    always_comb begin
        wr_next_state   = wr_state;
        next_write_addr = write_addr;
        
        b_channel_stall = b_valid_reg && !s_axi.b_ready;

        s_axi.aw_ready = 1'b0;
        s_axi.w_ready  = 1'b0;
        
        int_wr_req  = 1'b0;
        int_wr_en   = '0;
        int_wr_addr = '0;

        case (wr_state)
            WR_IDLE : begin
                if (!b_channel_stall) begin
                    s_axi.aw_ready = 1'b1;
                    if (s_axi.aw_valid) begin
                        next_write_addr = s_axi.aw_addr[2+:LOG_SIZE];
                        wr_next_state   = WR_ACTIVE;
                    end
                end
            end

            WR_ACTIVE : begin
                if (s_axi.w_valid) begin
                    int_wr_req  = 1'b1;
                    int_wr_en   = s_axi.w_strb;
                    int_wr_addr = write_addr;
                    
                    // Only advance if the arbiter gave us access to the BRAM
                    if (int_wr_grant) begin
                        s_axi.w_ready   = 1'b1;
                        next_write_addr = write_addr + 1;

                        if (s_axi.w_last) begin
                            wr_next_state = WR_IDLE;
                        end
                    end
                end
            end
        endcase
    end

    assign s_axi.b_id    = b_id_reg;
    assign s_axi.b_valid = b_valid_reg;
    assign s_axi.b_resp  = 2'b00;

    ////////////////////////////////////////////////////////////////////////
    //// AXI Read Logic ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    typedef enum logic { RD_IDLE, RD_ACTIVE } rd_state_t;
    rd_state_t rd_state, rd_next_state;

    logic [LOG_SIZE-1:0] burst_addr, next_burst_addr;
    logic [ID_WIDTH-1:0] r_id;
    logic [7:0]          r_burst_len, next_r_burst_len;
    logic [7:0]          r_burst_cnt, next_r_burst_cnt;
    
    logic r_valid_reg, r_last_reg;

    assign s_axi.r_id    = r_id;
    assign s_axi.r_resp  = 2'b00;
    assign s_axi.r_data  = rd_data;
    assign s_axi.r_valid = r_valid_reg;
    assign s_axi.r_last  = r_last_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_state    <= RD_IDLE;
            burst_addr  <= '0;
            r_burst_len <= '0;
            r_burst_cnt <= '0;
            r_valid_reg <= 1'b0;
            r_last_reg  <= 1'b0;
        end else begin
            rd_state    <= rd_next_state;
            burst_addr  <= next_burst_addr;
            r_burst_len <= next_r_burst_len;
            r_burst_cnt <= next_r_burst_cnt;

            // R-Channel Handshake
            if (s_axi.r_valid && s_axi.r_ready) begin
                r_valid_reg <= 1'b0;
                r_last_reg  <= 1'b0;
            end

            // Only mark data as valid next cycle IF the arbiter granted the read
            if (int_rd_req && int_rd_grant) begin
                r_valid_reg <= 1'b1;
                r_last_reg  <= (next_r_burst_cnt == r_burst_len + 1); 
            end
            
            // Capture ID
            if (s_axi.ar_ready && s_axi.ar_valid) begin
                r_id <= s_axi.ar_id;
            end
        end
    end

    always_comb begin
        rd_next_state    = rd_state;
        next_burst_addr  = burst_addr;
        next_r_burst_len = r_burst_len;
        next_r_burst_cnt = r_burst_cnt;

        s_axi.ar_ready = 1'b0;
        int_rd_req     = 1'b0;
        int_rd_en      = 1'b0;
        int_rd_addr    = '0;

        case (rd_state)
            RD_IDLE : begin
                s_axi.ar_ready = 1'b1;
                if (s_axi.ar_valid) begin
                    next_burst_addr  = s_axi.ar_addr[2+:LOG_SIZE];
                    next_r_burst_len = s_axi.ar_len;
                    next_r_burst_cnt = 8'd0;
                    rd_next_state    = RD_ACTIVE;
                end
            end

            RD_ACTIVE : begin
                if (!r_valid_reg || s_axi.r_ready) begin
                    int_rd_req  = 1'b1;
                    int_rd_en   = 1'b1;
                    int_rd_addr = burst_addr;
                    
                    // Only advance the burst logic if the arbiter gave us access
                    if (int_rd_grant) begin
                        next_burst_addr  = burst_addr + 1;
                        next_r_burst_cnt = r_burst_cnt + 1;

                        if (r_burst_cnt == r_burst_len) begin
                            rd_next_state = RD_IDLE;
                        end
                    end
                end
            end
        endcase
    end

endmodule : axi_bram_intf
