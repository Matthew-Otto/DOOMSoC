`include "defines.svh"

module core #(
    parameter int ADDR_WIDTH,
    parameter int DATA_WIDTH,
    parameter int ID_WIDTH
) (
    input  logic        core_clk,
    input  logic        bus_clk,
    input  logic        rst,

    AXI_BUS.Master      icache_port,
    AXI_BUS.Master      dcache_port
);

    ////////////////////////////////////////////////////////////////////////
    //// Fetch /////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic        ready_FE;
    logic        valid_FE;
    logic [31:0] PC_FE;
    logic [31:0] instr_FE;
    logic        branch_EX;
    logic [31:0] branch_target_EX;

    fetch #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) fetch_unit (
        .core_clk,
        .bus_clk,
        .rst,
        .branch(branch_EX),
        .branch_target(branch_target_EX),
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
    logic flush_DE;
    logic stall_DE;
    logic valid_DE_i;
    logic [31:0] PC_DE;
    logic [31:0] instr_DE;

    skid_buffer #(
        .DATA_WIDTH(64)
    ) skid_buffer_i (
        .clk(core_clk),
        .reset(rst || flush_FE),
        .input_ready(ready_FE),
        .input_valid(valid_FE),
        .input_data({PC_FE,instr_FE}),
        .output_ready(~stall_DE),
        .output_valid(valid_DE_i),
        .output_data({PC_DE,instr_DE})
    );

    assign stall_DE = 1'b0; // BOZO TODO

    ////////////////////////////////////////////////////////////////////////
    //// Decode ////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    struct packed {
        logic        valid;
        logic [31:0] PC;
        logic [31:0] instr;

        logic [4:0]  rd_addr;
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
    } DE_o, EX_i;
  
    assign DE_o.valid = valid_DE_i && ~flush_DE;
    assign DE_o.PC = PC_DE;
    assign DE_o.instr = instr_DE;

    decode decode_unit (
        .instr(instr_DE),
        .rd_addr(DE_o.rd_addr),
        .rs1_addr(DE_o.rs1_addr),
        .rs2_addr(DE_o.rs2_addr),
        .is_writeback(DE_o.is_writeback),
        .alu_op(DE_o.alu_op),
        .mul_op(DE_o.mul_op),
        .comp_op(DE_o.comp_op),
        .subtract(DE_o.subtract),
        .shift_right(DE_o.shift_right),
        .shift_arith(DE_o.shift_arith),
        .is_auipc(DE_o.is_auipc),
        .is_load_op(DE_o.is_load_op),
        .load_op(DE_o.load_op),
        .is_store_op(DE_o.is_store_op),
        .store_op(DE_o.store_op),
        .is_ctrl_op(DE_o.is_ctrl_op),
        .br_type(DE_o.br_type),
        .is_jump_op(DE_o.is_jump_op),
        .is_imm(DE_o.is_imm),
        .imm_b(DE_o.imm_b),
        .imm_i(DE_o.imm_i),
        .imm_s(DE_o.imm_s),
        .imm_u(DE_o.imm_u),
        .imm_j(DE_o.imm_j)
    );

    //// Source Bypass Logic
    logic [31:0] rs1_data_DE;
    logic [31:0] rs2_data_DE;
    logic forward_rs1_DE;
    logic forward_rs2_DE;

    logic [31:0] ld_rd_data;

    assign DE_o.rs1_data = forward_rs1_DE ? ld_rd_data : rs1_data_DE;
    assign DE_o.rs2_data = forward_rs2_DE ? ld_rd_data : rs2_data_DE;


    ////////////////////////////////////////////////////////////////////////
    //// DE:EX Pipeline Register ///////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic flush_EX;

    pipeline_reg #(
        .WIDTH($bits(DE_o))
    ) pipeline_de_ex (
        .clk(core_clk),
        .in(DE_o),
        .out(EX_i)
    );
    

    ////////////////////////////////////////////////////////////////////////
    //// Execute ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    struct packed {
        logic        valid;
        logic [31:0] PC;
        logic [31:0] instr;

        logic [31:0] alu_out;
        logic [4:0]  rd_addr;
        logic [31:0] st_data;
        logic        is_load_op;
        load_op_t    load_op;
        logic        is_store_op;
        store_op_t   store_op;
    } EX_o, LS_i;

    EXU execution_unit (
        .alu_op(EX_i.alu_op),
        .is_imm(EX_i.is_imm),
        .is_store_op(EX_i.is_store_op),
        .is_jump_op(EX_i.is_jump_op),
        .is_auipc(EX_i.is_auipc),
        .comp_op(EX_i.comp_op),
        .subtract(EX_i.subtract),
        .shift_right(EX_i.shift_right),
        .shift_arith(EX_i.shift_arith),
        .mul_op(EX_i.mul_op),
        .rs1_data(EX_i.rs1_data),
        .rs2_data(EX_i.rs2_data),
        .imm_i(EX_i.imm_i),
        .imm_u(EX_i.imm_u),
        .imm_s(EX_i.imm_s),
        .PC(EX_i.PC),
        .alu_out(EX_o.alu_out)
    );

    BRU branch_unit (
        .valid(EX_i.valid),
        .PC(EX_i.PC),
        .is_ctrl_op(EX_i.is_ctrl_op),
        .br_type(EX_i.br_type),
        .comp_op(EX_i.comp_op),
        .is_jump_op(EX_i.is_jump_op),
        .rs1_data(EX_i.rs1_data),
        .rs2_data(EX_i.rs2_data),
        .imm_b(EX_i.imm_b),
        .imm_i(EX_i.imm_i),
        .imm_j(EX_i.imm_j),
        .branch(branch_EX),
        .branch_target(branch_target_EX)
    );

    // Pass through
    assign EX_o.valid = EX_i.valid && ~flush_EX;
    assign EX_o.PC = EX_i.PC;
    assign EX_o.instr = EX_i.instr;

    assign EX_o.rd_addr = EX_i.rd_addr;
    assign EX_o.st_data = EX_i.rs2_data;
    assign EX_o.is_load_op = EX_i.is_load_op;
    assign EX_o.load_op = EX_i.load_op;
    assign EX_o.is_store_op = EX_i.is_store_op;
    assign EX_o.store_op = EX_i.store_op;

    ////////////////////////////////////////////////////////////////////////
    //// EX:LS Pipeline Register ///////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    pipeline_reg #(
        .WIDTH($bits(EX_o))
    ) pipeline_ex_ls (
        .clk(core_clk),
        .in(EX_o),
        .out(LS_i)
    );


    ////////////////////////////////////////////////////////////////////////
    //// Load/Store ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    logic        ld_valid;
    logic        ld_inflight;
    logic [4:0]  ld_rd_addr;
    logic stall_LS; // BOZO TODO

    LSU #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) loadstore_unit (
        .core_clk,
        .bus_clk,
        .rst,
        .valid(LS_i.valid),
        .stall(stall_LS),
        .is_load_op(LS_i.is_load_op),
        .load_op(LS_i.load_op),
        .is_store_op(LS_i.is_store_op),
        .store_op(LS_i.store_op),
        .ls_addr(LS_i.alu_out),
        .write_data(LS_i.st_data),
        .rd_addr(LS_i.rd_addr),
        .ld_valid,
        .ld_inflight,
        .ld_rd_addr,
        .ld_rd_data,
        .dcache_port
    );


    ////////////////////////////////////////////////////////////////////////
    //// Register File /////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    logic ex_we;
    logic ld_we;

    assign ex_we = EX_o.valid && EX_i.is_writeback;
    assign ld_we = ld_valid;

    regfile regfile_i (
        .clk(core_clk),
        .ex_we,
        .ex_rd_addr(EX_i.rd_addr),
        .ex_rd_data(EX_o.alu_out),
        .ld_we,
        .ld_rd_addr,
        .ld_rd_data,
        .rs1_addr(DE_o.rs1_addr),
        .rs2_addr(DE_o.rs2_addr),
        .rs1_data(rs1_data_DE),
        .rs2_data(rs2_data_DE)
    );


    ////////////////////////////////////////////////////////////////////////
    //// Control Logic /////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    control control_i (
        .branch_EX,
        .flush_FE,
        .flush_DE,
        .flush_EX,

        // Source Bypass/Hazard
        .rs1_addr_DE(DE_o.rs1_addr),
        .rs2_addr_DE(DE_o.rs2_addr),
        .ld_valid_LS(ld_valid),
        .ld_inflight_LS(ld_inflight),
        .ld_rd_addr_LS(ld_rd_addr),
        .is_load_op_DE(DE_o.is_load_op),
        .is_store_op_DE(DE_o.is_store_op),
        
        .forward_rs1_DE,
        .forward_rs2_DE,
        .stall_EX()
    );

endmodule : core
