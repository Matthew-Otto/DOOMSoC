`include "defines.svh"

module core (
    input  logic        core_clk,
    input  logic        bus_clk,
    input  logic        rst,

    AXI_BUS.Master      icache_port,
    AXI_BUS.Master      dcache_port
);

    // control
    logic        flush;

    logic [4:0]  ld_rd_addr;
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
    logic        stall_EX;
    logic        valid_EX;
    logic [31:0] instr_EX;
    logic [31:0] PC_EX;
 
    // data
    logic        we;
    logic [4:0]  rd_addr;
    logic [31:0] rd_data;
    logic [31:0] ls_rd_data;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    logic [31:0] alu_out;
    logic [31:0] ld_rd_data;

    logic [31:0] imm_b;
    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_u;
    logic [31:0] imm_j;


    control control_unit (
        .is_writeback,
        .ld_valid,
        .rs1_addr,
        .rs2_addr,
        .ld_rd_addr,
        .reg_we(we)
    );
    // BOZO TODO data hazards from load

    fetch fetch_unit (
        .core_clk,
        .bus_clk,
        .rst,
        .branch,
        .branch_target,
        .ready(~stall_EX),
        .valid(valid_EX),
        .instr(instr_EX),
        .PC(PC_EX),
        .icache_port
    );


    decode decode_unit (
        .instr(instr_EX),
        .rd_addr,
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

    EXU execution_unit (
        .alu_op,
        .is_imm,
        .is_store_op,
        .is_jump_op,
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
        .alu_out
    );

    BRU branch_unit (
        .valid(valid_EX),
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

    // BOZO TODO writeback jump ops
    regfile regfile_i (
        .clk(core_clk),
        .flush,
        .ex_we(is_writeback),
        .ex_rd_addr(rd_addr),
        .ex_rd_data(alu_out),
        .ld_we(ld_valid),
        .ld_rd_addr,
        .ld_rd_data,
        .rs1_addr,
        .rs2_addr,
        .rs1_data,
        .rs2_data
    );

    LSU loadstore_unit (
        .core_clk,
        .bus_clk,
        .rst,
        .valid(0), // BOZO TODO
        .flush,
        .stall(stall_EX),
        .is_load_op,
        .load_op,
        .is_store_op,
        .store_op,
        .ls_addr(alu_out),
        .write_data(rs2_data),
        .rd_addr,
        .ld_valid,
        .ld_rd_addr,
        .ld_rd_data,
        .dcache_port
    );

endmodule : core
