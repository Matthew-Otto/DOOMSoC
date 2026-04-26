`include "defines.svh"

module core (
    input  logic        core_clk,
    input  logic        bus_clk,
    input  logic        rst,

    // instruction port
    AXI_BUS.Master      icache_port,

    // data port
    output logic [31:0] d_addr,
    output logic [3:0]  d_we,
    output logic [31:0] d_wr_data,
    input  logic [31:0] d_rd_data
);

    // control
    logic        flush;
    logic        st_en;
    logic        ld_en;

    logic [4:0]  ld_rd;
    logic [4:0]  dec_rd_addr;
    logic        is_writeback;
    
    alu_op_t     alu_op;
    mul_op_t     mul_op;
    comp_t       comp_op;
    logic        subtract;
    logic        shift_right;
    logic        shift_arith;
    logic        is_imm;
    logic        is_auipc;
    
    logic        is_load_op;
    load_op_t    load_op;
    logic        is_store_op;
    store_op_t   store_op;
    logic        ld_valid;
    
    logic        is_ctrl_op;
    br_type_t    br_type;
    logic        is_jump_op;
    logic        branch;
    logic [31:0] branch_target;
    
    // fetch
    logic        ready_EX;
    logic        valid_EX;
    logic [31:0] instr_EX;
    logic [31:0] PC_EX;
 
    // data
    logic        we;
    logic [4:0]  rd_addr;
    logic [31:0] rd_data;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    logic [31:0] alu_rd_data;
    logic [31:0] ld_rd_data;

    logic [31:0] imm_b;
    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_u;
    logic [31:0] imm_j;



    control control_i (
        .flush,
        .is_writeback,
        .ld_valid,
        .rs1_addr,
        .rs2_addr,
        .ld_rd,
        .reg_we(we),
        .st_en,
        .ld_en
    );


    // PC calc / front-end
    fetch fetch_i (
        .core_clk,
        .bus_clk,
        .rst,
        .branch,
        .branch_target,
        .flush,
        .ready(ready_EX),
        .valid(valid_EX),
        .instr(instr_EX),
        .PC(PC_EX),
        .icache_port
    );

    // Decode
    decode decode_i (
        .instr(instr_EX),
        .rd_addr(dec_rd_addr),
        .rs1_addr,
        .rs2_addr,
        .is_writeback,
        .alu_op,
        .mul_op,
        .comp_op,
        .subtract,
        .shift_right,
        .shift_arith,
        .is_auipc,
        .is_load_op,
        .load_op,
        .is_store_op,
        .store_op,
        .is_ctrl_op,
        .br_type,
        .is_jump_op,
        .is_imm,
        .imm_b,
        .imm_i,
        .imm_s,
        .imm_u,
        .imm_j
    );

    // execution unit
    EXU EXU_i (
        .alu_op,
        .is_imm,
        .is_store_op,
        .is_auipc,
        .comp_op,
        .subtract,
        .shift_right,
        .shift_arith,
        .mul_op,
        .rs1_data,
        .rs2_data,
        .imm_i,
        .imm_u,
        .imm_s,
        .PC(PC_EX),
        .rd_data(alu_rd_data)
    );

    // branch unit
    BRU BRU_i (
        .PC(PC_EX),
        .is_ctrl_op,
        .br_type,
        .comp_op,
        .is_jump_op,
        .rs1_data,
        .rs2_data,
        .imm_b,
        .imm_i,
        .imm_j,
        .branch,
        .branch_target
    );

    regfile regfile_i (
        .clk(core_clk),
        .we,
        .rd_addr,
        .rd_data,
        .rs1_addr,
        .rs2_addr,
        .rs1_data,
        .rs2_data
    );

    // load / store
    LSU LSU_i (
        .clk(core_clk),
        .rst,
        .st_en,
        .ld_en,
        .rd(dec_rd_addr),
        .addr(alu_rd_data),
        .is_load_op,
        .is_store_op,
        .load_op,
        .store_op,
        .write_data(rs2_data),
        .ld_valid,
        .ld_rd,
        .ld_rd_data,
        .d_addr,
        .d_we,
        .d_wr_data,
        .d_rd_data
    );

    // BOZO TODO couple writeback tighter into LSU
    assign rd_addr = ld_valid ? ld_rd : dec_rd_addr;

    always_comb begin
        casez ({ld_valid,is_jump_op})
            2'b1? : rd_data = ld_rd_data;
            //2'b01 : rd_data = PC_p4;
            default: rd_data = alu_rd_data;
        endcase
    end

endmodule : core
