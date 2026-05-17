module control (
    input  logic branch_EX,
    input  logic ready_LS,

    input  logic valid_DE,
    input  logic valid_EX,
    input  logic valid_LS,

    output logic flush_DE,
    output logic flush_EX,
    output logic flush_LS,

    output logic stall_DE,
    output logic stall_EX,
    output logic stall_LS,
    output logic stall_FE,

    // Source Bypass/Hazard
    input  logic       is_imm_DE,
    input  logic [4:0] rs1_addr_DE,
    input  logic [4:0] rs2_addr_DE,

    input  logic       is_load_op_EX,
    input  logic [4:0] rd_addr_EX,

    input  logic       is_load_op_LS,
    input  logic [4:0] rd_addr_LS,
    input  logic [4:0] ld_rd_addr_LS,
    input  logic       ld_inflight_LS,
    input  logic       ld_valid_LS,

    input  logic       is_store_op_EX
);

    logic rs1_match_EX;
    logic rs2_match_EX;
    logic source_hazard_EX;

    logic rs1_match_LS_dispatch;
    logic rs2_match_LS_dispatch;
    logic source_hazard_LS_dispatch;
    logic rs1_match_LS_inflight;
    logic rs2_match_LS_inflight;
    logic source_hazard_LS_inflight;
    logic source_hazard_LS;

    logic LSU_busy;

    // Stall if DE depends on destination of Load in EX
    // Other dependencies in EX will be forwarded automatically in regfile
    assign rs1_match_EX = (rs1_addr_DE == rd_addr_EX);
    assign rs2_match_EX = (rs2_addr_DE == rd_addr_EX) && ~is_imm_DE;
    assign source_hazard_EX = valid_EX && is_load_op_EX && (rs1_match_EX || rs2_match_EX);

    // Stall if DE depends on destination of Load in LS and the result is not ready
    assign rs1_match_LS_dispatch = (rs1_addr_DE == rd_addr_LS);
    assign rs2_match_LS_dispatch = (rs2_addr_DE == rd_addr_LS) && ~is_imm_DE;
    assign source_hazard_LS_dispatch = valid_LS && is_load_op_LS && (rs1_match_LS_dispatch || rs2_match_LS_dispatch);

    assign rs1_match_LS_inflight = (rs1_addr_DE == ld_rd_addr_LS);
    assign rs2_match_LS_inflight = (rs2_addr_DE == ld_rd_addr_LS) && ~is_imm_DE;
    assign source_hazard_LS_inflight = ld_inflight_LS && (rs1_match_LS_inflight || rs2_match_LS_inflight) && ~ld_valid_LS;

    assign source_hazard_LS = source_hazard_LS_dispatch || source_hazard_LS_inflight;
   
    // Stall LD/ST op in EX if the LSU unit is busy
    assign LSU_busy = valid_EX && (is_load_op_EX || is_store_op_EX) && ~ready_LS;

    // pipeline control
    assign stall_LS = 0;
    assign flush_LS = LSU_busy;

    assign stall_EX = LSU_busy;
    assign flush_EX = source_hazard_EX || source_hazard_LS || branch_EX;
    
    assign stall_DE = stall_EX || source_hazard_EX || source_hazard_LS;
    assign flush_DE = branch_EX;
    
    assign stall_FE = stall_DE;

endmodule : control
