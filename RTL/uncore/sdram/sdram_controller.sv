module sdram_controller #(
    parameter int MEM_CLK_FREQ = 0
)(
    input  logic        mem_clk,
    input  logic        reset,

    output logic        cmd_ready,
    input  logic        stop,
    input  logic        read,
    input  logic        write,
    input  logic [3:0]  write_strb,
    input  logic [22:0] addr,  // {bank[1:0], row[10:0], col[7:0], word[1:0](discarded)}
    input  logic [31:0] write_data,
    output logic [31:0] read_data,
    output logic        read_data_val,

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

    //--------------------------------------------------------------------------
    // SDRAM parameters / settings
    //--------------------------------------------------------------------------
    // SDRAM timings (ns) from spec EM638325-6 (speed grade 6, 166MHz Fmax)
    localparam real tCK_ns = 1_000_000_000 / MEM_CLK_FREQ;
    localparam tRC_ns = 60;
    localparam tRCD_ns = 18;
    localparam tRP_ns = 18;
    localparam tRRD_ns = 12;
    localparam tRAS_ns = 42;
    localparam tREFI_ns = 15600;
    localparam tRFC_ns = 60;
    localparam tPOD_ns = 200_000;

    localparam int tCAS = 3; // 2/3 allowed, 3 required for mem_clk > 100 MHz
    localparam int tWR = 2;
    localparam int tCCD = 1;
    localparam int tMRD = 2;
    localparam int tRC = int'($ceil((tRC_ns + tCK_ns - 1) / tCK_ns));
    localparam int tRCD = int'($ceil((tRCD_ns + tCK_ns - 1) / tCK_ns));
    localparam int tRP = int'($ceil((tRP_ns + tCK_ns - 1) / tCK_ns));
    localparam int tRRD = int'($ceil((tRRD_ns + tCK_ns - 1) / tCK_ns));
    localparam int tRAS = int'($ceil((tRAS_ns + tCK_ns - 1) / tCK_ns));
    localparam int tREFI = int'($ceil((tREFI_ns + tCK_ns - 1) / tCK_ns));
    localparam int tRFC = int'($ceil((tRFC_ns + tCK_ns - 1) / tCK_ns));
    localparam int tPOD = int'($ceil((tPOD_ns + tCK_ns - 1) / tCK_ns));
    
    // SDRAM mode settings
    localparam BURST_LENGTH = 3'b011; // 000 = none, 001 = 2, 010 = 4, 011 = 8, 111 = full page
    localparam BURST_TYPE   = 1'b0;   // 0 = sequential, 1 = interleaved
    localparam CAS_LATENCY  = tCAS;   // 2/3 allowed, 3 required for mem_clk > 100 MHz
    localparam OP_MODE      = 2'b00;  // 0 = standard (vendor specific)
    localparam BURST_WRITE  = 1'b0;   // 0 = enabled, 1 = read burst, single write
    localparam MODE = {3'b0, BURST_WRITE, OP_MODE, CAS_LATENCY, BURST_TYPE, BURST_LENGTH};


    enum {
        INIT,
        IDLE,
        ACTIVATE,
        PRECHARGE,
        READ,
        READ_BURST,
        WRITE,
        WRITE_BURST,
        REFRESH_PRECHARGE, // Precharge all before calling AutoRefresh
        REFRESH,           // AutoRefresh
        WAIT,
        STOP
    } state, next_state, return_state;


    //--------------------------------------------------------------------------
    // Drive SDRAM signals
    //--------------------------------------------------------------------------
    // Command Encodings {RAS_n, CAS_n, WE_n}
    enum logic [2:0] {
        CMD_NOP     = 3'b111,
        CMD_STOP    = 3'b110,
        CMD_ACTIVE  = 3'b011,
        CMD_READ    = 3'b101,
        CMD_WRITE   = 3'b100,
        CMD_PRECHG  = 3'b010,
        CMD_AUTOREF = 3'b001,
        CMD_LMR     = 3'b000 // load mode register
    } init_cmd, sdram_cmd;

    logic [1:0]  sdram_bank;
    logic [10:0] init_addr, sdram_addr;

    assign O_sdram_clk = mem_clk;
    assign O_sdram_cke = 1'b1;
    assign O_sdram_cs_n = 1'b0;

    always_comb begin
        if (state == INIT) begin
            {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} = init_cmd;
            {O_sdram_ba,O_sdram_addr} = {2'b0,init_addr};
        end else begin
            {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} = sdram_cmd;
            {O_sdram_ba,O_sdram_addr} = {sdram_bank,sdram_addr};
        end
    end


    //--------------------------------------------------------------------------
    // Init FSM
    //--------------------------------------------------------------------------
    logic init_done;
    logic [15:0] init_delay_cnt;

    enum {
        INIT_POWER,
        INIT_PRECHARGE,
        INIT_AUTOREF1,
        INIT_AUTOREF2,
        INIT_MODE,
        INIT_DONE
    } init_state;

    always_ff @(posedge mem_clk) begin
        if (reset) begin
            init_state <= INIT_POWER;
            init_delay_cnt <= tPOD;
            init_cmd  <= CMD_NOP;
            init_addr <= '0;
            init_done <= 1'b0;
        end else begin
            init_cmd <= CMD_NOP; 
            if (init_delay_cnt > 0) begin
                init_delay_cnt <= init_delay_cnt - 1;
            end else begin
                case (init_state)
                    INIT_POWER : begin
                        init_cmd  <= CMD_PRECHG;
                        init_addr <= 11'b10000000000;
                        init_delay_cnt <= tRP - 1; 
                        init_state <= INIT_PRECHARGE;
                    end
                    
                    INIT_PRECHARGE : begin
                        init_cmd  <= CMD_AUTOREF;
                        init_delay_cnt <= tRC - 1;
                        init_state <= INIT_AUTOREF1;
                    end

                    INIT_AUTOREF1 : begin
                        init_cmd  <= CMD_AUTOREF;
                        init_delay_cnt <= tRC - 1;
                        init_state <= INIT_AUTOREF2;
                    end

                    INIT_AUTOREF2 : begin
                        init_cmd  <= CMD_LMR;
                        init_addr <= MODE;
                        init_delay_cnt <= tMRD - 1;
                        init_state <= INIT_MODE;
                    end

                    INIT_MODE : begin
                        init_state <= INIT_DONE;
                    end

                    INIT_DONE : begin
                        init_done <= 1'b1;
                    end
                endcase
            end
        end
    end


    //--------------------------------------------------------------------------
    // Refresh Timer
    //--------------------------------------------------------------------------
    logic [15:0] refresh_cnt;
    logic        refresh_req;

    always_ff @(posedge mem_clk) begin
        if (state == INIT) begin
            refresh_cnt <= 0;
            refresh_req <= 0;
        end else begin
            if (refresh_cnt == tREFI)
                refresh_cnt <= 0;
            else
                refresh_cnt <= refresh_cnt + 1;

            if (state == REFRESH)
                refresh_req <= 0;
            else if (refresh_cnt == tREFI)
                refresh_req <= 1;
        end
    end


    //--------------------------------------------------------------------------
    // Address Decoding / Latch
    //--------------------------------------------------------------------------
    logic        latch_input;
    logic        latched_read_cmd, latched_write_cmd;
    logic [1:0]  bank_addr, latched_bank_addr;
    logic [10:0] row_addr, latched_row_addr;
    logic [7:0]  col_addr, latched_col_addr;

    assign latch_input = (state == IDLE) && (read || write);
    assign {bank_addr,row_addr,col_addr} = addr[22:2];

    always_ff @(posedge mem_clk) begin
        if (reset) begin
            latched_read_cmd <= 0;
            latched_write_cmd <= 0;
            latched_bank_addr <= 0;
            latched_row_addr <= 0;
            latched_col_addr <= 0;
        end else if (latch_input) begin
            latched_read_cmd <= read;
            latched_write_cmd <= write;
            {latched_bank_addr,latched_row_addr,latched_col_addr} <= {bank_addr,row_addr,col_addr};
        end
    end


    //--------------------------------------------------------------------------
    // Track Open Rows
    //--------------------------------------------------------------------------
    logic [3:0]  open_rows;
    logic [10:0] open_row_addr [3:0];


    always_ff @(posedge mem_clk) begin
        if (reset) begin
            open_rows <= '0;
        end else begin
            case (state)
                ACTIVATE  : begin
                    open_rows[latched_bank_addr] <= 1'b1;
                    open_row_addr[latched_bank_addr] <= latched_row_addr;
                end
                PRECHARGE : open_rows[latched_bank_addr] <= 1'b0;
                REFRESH_PRECHARGE : open_rows <= 0;
            endcase
        end
    end


    //--------------------------------------------------------------------------
    // Write Driver
    //--------------------------------------------------------------------------
    // Tri-state data bus control
    logic write_active;

    assign IO_sdram_dq = write_active ? write_data : 'z;
    assign write_active = (state == WRITE) || (state == WRITE_BURST);


    //--------------------------------------------------------------------------
    // Track Valid Reads
    //--------------------------------------------------------------------------
    logic [31:0] bus_read_data;
    // simulation artifact
    assign read_data = bus_read_data;
`ifndef VERILATOR
    assign bus_read_data = IO_sdram_dq;
`endif

    logic read_queued;
    logic [tCAS-1:0] read_valid_delay;

    assign read_queued = ((state == READ) || (state == READ_BURST)) && ~&O_sdram_dqm;
    always_ff @(posedge mem_clk) begin
        if (reset) read_valid_delay <= 0;
        else begin
            read_valid_delay[tCAS-1] <= read_queued;
            for (int i = 0; i < tCAS-1; i++)
                read_valid_delay[i] <= read_valid_delay[i+1];
        end
    end
    assign read_data_val = read_valid_delay[0];


    //--------------------------------------------------------------------------
    // Track Required Delays
    //--------------------------------------------------------------------------
    logic [$clog2(tRRD)-1:0] tRRD_cnt; // ACT to ACT in different banks
    always_ff @(posedge mem_clk) begin
        if (reset) tRRD_cnt <= 0;
        else if (sdram_cmd == CMD_ACTIVE) tRRD_cnt <= tRRD - 1;
        else if (|tRRD_cnt) tRRD_cnt <= tRRD_cnt - 1;
    end
    
    logic [$clog2(tRAS)-1:0] tRAS_cnt; // ACT to PRECHARGE
    always_ff @(posedge mem_clk) begin
        if (reset) tRAS_cnt <= 0;
        else if (sdram_cmd == CMD_ACTIVE) tRAS_cnt <= tRAS - 1;
        else if (|tRAS_cnt) tRAS_cnt <= tRAS_cnt - 1;
    end

    logic [$clog2(tWR)-1:0] tWR_cnt; // ACT to PRECHARGE
    always_ff @(posedge mem_clk) begin
        if (reset) tWR_cnt <= 0;
        else if (sdram_cmd == CMD_WRITE) tWR_cnt <= tWR - 1;
        else if (|tWR_cnt) tWR_cnt <= tWR_cnt - 1;
    end



    //--------------------------------------------------------------------------
    // Command FSM
    //--------------------------------------------------------------------------
    logic [2:0] burst_cnt, next_burst_cnt;
    logic [15:0] delay_cnt, next_delay_cnt;

    always_ff @(posedge mem_clk) begin
        if (reset)               state <= INIT;
        else if (delay_cnt == 0) state <= next_state;

        if (|next_delay_cnt) begin
            state <= WAIT;
            return_state <= next_state;
        end
    end

    always_ff @(posedge mem_clk) begin
        if (reset)
            delay_cnt <= 0;
        else if (|delay_cnt)
            delay_cnt <= delay_cnt - 1;
        else
            delay_cnt <= next_delay_cnt;
    end

    always_ff @(posedge mem_clk) begin
        if (reset)
            burst_cnt <= 0;
        else if (|burst_cnt)
            burst_cnt <= burst_cnt - 1;
        else
            burst_cnt <= next_burst_cnt;
    end


    always_comb begin
        next_state = state;
        sdram_cmd = CMD_NOP;
        sdram_bank = '0;
        sdram_addr = '0;
        cmd_ready = 0;
        next_delay_cnt = 0;
        next_burst_cnt = 0;
        O_sdram_dqm = 4'h0;

        case (state)
            INIT : begin
                if (init_done) next_state = IDLE;
            end

            WAIT : begin
                next_state = return_state;
            end

            IDLE : begin
                if (refresh_req) begin
                    if (~|open_rows) next_state = REFRESH;
                    else if (tRAS_cnt == 0 && tWR_cnt == 0) next_state = REFRESH_PRECHARGE;
                end else if (read || write) begin
                    // if row is open (hit)
                    if (open_rows[bank_addr] && (row_addr == open_row_addr[bank_addr])) begin
                        if (write && ~read_data_val)
                            next_state = WRITE;
                        else if (read)
                            next_state = READ;
                    
                    // if row is open (miss)
                    end else if (open_rows[bank_addr] && (row_addr != open_row_addr[bank_addr])) begin
                        if (tRAS_cnt == 0 && tWR_cnt == 0)
                            next_state = PRECHARGE;
                    
                    // if row is closed
                    end else if (!open_rows[bank_addr]) begin
                        if (tRRD_cnt == 0)
                            next_state = ACTIVATE;
                    end
                end
            end

    
            READ : begin
                cmd_ready = 1;
                sdram_cmd = CMD_READ;
                sdram_bank = latched_bank_addr;
                sdram_addr = {3'b0,latched_col_addr};
                
                if (stop) begin
                    next_state = STOP;
                end else begin
                    next_state = READ_BURST;
                    next_burst_cnt = 7;
                end
            end
            
            READ_BURST : begin
                if (burst_cnt == 1)
                    next_state = IDLE;
                else if (stop)
                    next_state = STOP;
            end
            
            WRITE : begin
                cmd_ready = 1;
                sdram_cmd = CMD_WRITE;
                O_sdram_dqm = ~write_strb;
                sdram_bank = latched_bank_addr;
                sdram_addr = {3'b0,latched_col_addr};
                
                if (stop) begin
                    next_state = STOP;
                end else begin
                    next_state = WRITE_BURST;
                    next_burst_cnt = 7;
                end
            end

            WRITE_BURST : begin
                O_sdram_dqm = ~write_strb;

                if (burst_cnt == 1)
                    next_state = IDLE;
                else if (stop)
                    next_state = STOP;
            end

            STOP : begin
                sdram_cmd = CMD_STOP;
                next_state = IDLE;
            end


            ACTIVATE : begin
                sdram_cmd = CMD_ACTIVE;
                sdram_bank = latched_bank_addr;
                sdram_addr = latched_row_addr;
                next_delay_cnt = tRCD - 1;
                if (latched_read_cmd)
                    next_state = READ;
                else if (latched_write_cmd)
                    next_state = WRITE;
                else
                    next_state = IDLE;
            end

            PRECHARGE : begin
                sdram_cmd = CMD_PRECHG;
                sdram_bank = latched_bank_addr;
                next_delay_cnt = tRP - 1;
                next_state = ACTIVATE;
            end


            REFRESH_PRECHARGE : begin
                sdram_cmd = CMD_PRECHG;
                sdram_addr = 11'b10000000000;
                next_delay_cnt = tRP - 1;
                next_state = REFRESH;
            end

            REFRESH : begin
                sdram_cmd = CMD_AUTOREF;
                next_delay_cnt = tRFC - 1;
                next_state = IDLE;
            end
        endcase
    end

endmodule : sdram_controller
