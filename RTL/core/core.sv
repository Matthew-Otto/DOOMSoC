`include "defines.svh"

module core (
    input  logic        core_clk,
    input  logic        bus_clk,
    input  logic        rst,

    AXI_BUS.Master      icache_port,
    AXI_BUS.Master      dcache_port
);

    ////////////////////////////////////////////////////////////////////////
    //// Fetch /////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic        branch;
    logic [31:0] branch_target;

    logic        ready_FE;
    logic        valid_FE;
    logic [31:0] PC_FE;
    logic [31:0] instr_FE;

    fetch fetch_unit (
        .core_clk,
        .bus_clk,
        .rst,
        .branch,
        .branch_target,
        .ready_FE(ready_FE),
        .valid_FE(valid_FE),
        .instr_FE(instr_FE),
        .PC_FE(PC_FE),
        .icache_port
    );


    ////////////////////////////////////////////////////////////////////////
    //// FE skid buffer ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic flush_FE;
    logic stall_EX;
    logic valid_EX;
    logic [31:0] PC_EX;
    logic [31:0] instr_EX;

    assign flush_FE = branch;

    skid_buffer #(
        .DATA_WIDTH(64)
    ) skid_buffer_i (
        .clk(core_clk),
        .reset(rst || flush_FE),
        .input_ready(ready_FE),
        .input_valid(valid_FE),
        .input_data({PC_FE,instr_FE}),
        .output_ready(~stall_EX),
        .output_valid(valid_EX),
        .output_data({PC_EX,instr_EX})
    );


    ////////////////////////////////////////////////////////////////////////
    //// Decode/Execute ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic [4:0]  rd_addr_EX;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
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

    logic        is_ctrl_op;
    br_type_t    br_type;
    logic        is_jump_op;

    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] imm_b;
    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_u;
    logic [31:0] imm_j;

    decode decode_unit (
        .instr(instr_EX),
        .rd_addr(rd_addr_EX),
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


    logic [31:0] rs1_mux;
    logic [31:0] rs2_mux;
    logic [31:0] alu_out;

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
        .rs1_data(rs1_mux),
        .rs2_data(rs2_mux),
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


    ////////////////////////////////////////////////////////////////////////
    //// EX:LS Pipeline stage //////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic        valid_LS;

    struct packed {
        logic [31:0] addr;
        logic [4:0]  rd_addr;
        logic [31:0] st_data;
        logic        is_load_op;
        load_op_t    load_op;
        logic        is_store_op;
        store_op_t   store_op;
    } EX, LS;

    assign EX.addr = alu_out;
    assign EX.rd_addr = rd_addr_EX;
    assign EX.st_data = rs2_data;
    assign EX.is_load_op = is_load_op;
    assign EX.load_op = load_op;
    assign EX.is_store_op = is_store_op;
    assign EX.store_op = store_op;

    pipeline_reg #(
        .WIDTH($bits(EX))
    ) pipeline_ex_ls (
        .clk(core_clk),
        .valid_in(valid_EX && ~branch), // BOZO TODO: check this, maybe move to control
        .valid_out(valid_LS),
        .in(EX),
        .out(LS)
    );


    ////////////////////////////////////////////////////////////////////////
    //// Load/Store ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic        ld_valid;
    logic        ld_inflight;
    logic [4:0]  ld_rd_addr;
    logic [31:0] ld_rd_data;

    LSU loadstore_unit (
        .core_clk,
        .bus_clk,
        .rst,
        .valid(valid_LS),
        .is_load_op(LS.is_load_op),
        .load_op(LS.load_op),
        .is_store_op(LS.is_store_op),
        .store_op(LS.store_op),
        .ls_addr(LS.addr),
        .write_data(LS.st_data),
        .rd_addr(LS.rd_addr),
        .ld_valid,
        .ld_inflight,
        .ld_rd_addr,
        .ld_rd_data,
        .dcache_port
    );


    ////////////////////////////////////////////////////////////////////////
    //// Register File /////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
        
    regfile regfile_i (
        .clk(core_clk),
        .ex_we(valid_EX && is_writeback),
        .ex_rd_addr(rd_addr_EX),
        .ex_rd_data(alu_out),
        .ld_we(ld_valid),
        .ld_rd_addr,
        .ld_rd_data,
        .rs1_addr,
        .rs2_addr,
        .rs1_data,
        .rs2_data
    );


    ////////////////////////////////////////////////////////////////////////
    //// Control/Forwarding Logic //////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    // BOZO: wrap this in a module?

    logic rs1_hazard;
    logic rs2_hazard;
    logic forward_rs1;
    logic forward_rs2;

    assign rs1_hazard = (ld_rd_addr == rs1_addr);
    assign rs2_hazard = (ld_rd_addr == rs2_addr);

    assign stall_EX = ld_inflight && (rs1_hazard || rs2_hazard || is_load_op || is_store_op);

    assign forward_rs1 = ld_valid && rs1_hazard;
    assign forward_rs2 = ld_valid && rs2_hazard;
    assign rs1_mux = forward_rs1 ? ld_rd_data : rs1_data;
    assign rs2_mux = forward_rs2 ? ld_rd_data : rs2_data;


endmodule : core
