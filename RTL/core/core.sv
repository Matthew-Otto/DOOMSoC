`include "defines.svh"

module core (
    input  logic        clk,
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
    logic [31:0] PC;     // current PC
    logic [31:0] PC_p4;  // next PC
    logic        flush;
    logic        fetch_stall;
    logic        st_en;
    logic        ld_en;

    logic [4:0]  ld_rd;
    logic [4:0]  dec_rd;
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
    
    logic        is_br_type;
    br_type_t    br_type;
    logic        is_jump_op;
    logic        take_branch;
    

    logic [31:0] i_addr;
    logic [31:0] i_data;
    logic        i_data_val; // BOZO TODO stall core on cache miss
    
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
        .fetch_stall,
        .reg_we(we),
        .st_en,
        .ld_en
    );

    icache icache (
        .clk,
        .rst,
        .core_addr(i_addr),
        .core_read(i_data),
        .core_read_valid(i_data_val),
        .m_axi(icache_port)
    );

    // PC calc / front-end
    fetch fetch_i (
        .clk,
        .rst,
        .fetch_stall,
        .is_br_type,
        .br_type,
        .take_branch,
        .rs1_data,
        .imm_b,
        .imm_i,
        .imm_j,
        .i_addr,
        .PC_f(PC_p4),
        .PC_e(PC),
        .flush
    );

    // Decode
    decode decode_i (
        .instr(i_data),
        .rd(dec_rd),
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
        .is_br_type,
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
        .PC,
        .rd_data(alu_rd_data),
        .branch(take_branch)
    );

    regfile regfile_i (
        .clk,
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
        .clk,
        .rst,
        .st_en,
        .ld_en,
        .rd(dec_rd),
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

    assign rd_addr = ld_valid ? ld_rd : dec_rd;

    always_comb begin
        casez ({ld_valid,is_jump_op})
            2'b1? : rd_data = ld_rd_data;
            2'b01 : rd_data = PC_p4;
            default: rd_data = alu_rd_data;
        endcase
    end

endmodule : core
