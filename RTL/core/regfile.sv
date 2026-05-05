module regfile (
    input  logic        clk,
    
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
    always_ff @(posedge clk) begin
        if (ex_we && |ex_rd_addr) begin
            regs[ex_rd_addr] <= ex_rd_data;
        end
        if (ld_we && |ld_rd_addr) begin
            regs[ld_rd_addr] <= ld_rd_data;
        end
    end

    assign rs1_data = (rs1_addr == 0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 0) ? 32'b0 : regs[rs2_addr];

endmodule : regfile
