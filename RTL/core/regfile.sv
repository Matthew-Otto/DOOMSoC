module regfile (
    input  logic        clk,
    
    input  logic        flush,
    input  logic        ex_we,
    input  logic [4:0]  ex_rd_addr,
    input  logic [31:0] ex_rd_data,
    input  logic        ld_we,
    input  logic [4:0]  ld_rd_addr,
    input  logic [31:0] ld_rd_data,

    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data
);

    // Register file
    logic [31:0] regs [31:1];

    // fuck it, two write ports.
    // always_ff @(posedge clk) begin
    //     if (ex_we && |ex_rd_addr && ~flush) begin
    //         regs[ex_rd_addr] <= ex_rd_data;
    //     end
    //     if (ld_we && |ld_rd_addr && ~flush) begin
    //         regs[ld_rd_addr] <= ld_rd_data;
    //     end
    // end

    logic        rf_we;
    logic [4:0]  rf_wa;
    logic [31:0] rf_wd;

    always_comb begin
        // Assuming Load has priority over Execute, or they never happen at the same time
        if (ld_we) begin
            rf_we = 1'b1;
            rf_wa = ld_rd_addr;
            rf_wd = ld_rd_data;
        end else if (ex_we) begin
            rf_we = 1'b1;
            rf_wa = ex_rd_addr;
            rf_wd = ex_rd_data;
        end else begin
            rf_we = 1'b0;
            rf_wa = 5'b0;
            rf_wd = 32'b0;
        end
    end

    // 2. A clean, single-write-port memory block
    always_ff @(posedge clk) begin
        if (rf_we && |rf_wa && ~flush) begin
            regs[rf_wa] <= rf_wd;
        end
    end


    assign rs1_data = (rs1_addr == 0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 0) ? 32'b0 : regs[rs2_addr];

endmodule : regfile
