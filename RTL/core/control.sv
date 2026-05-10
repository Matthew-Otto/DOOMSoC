module control (
    input  logic branch_EX,
    input  logic ready_LS,

    input  logic valid_DE,
    input  logic valid_EX,

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
    input  logic       ld_valid_LS,
    input  logic       ld_inflight_LS,
    input  logic [4:0] ld_rd_addr_LS,
    input  logic       is_load_op_EX,
    input  logic       is_store_op_EX
);

    logic rs1_match;
    logic rs2_match;
    logic source_hazard;
    logic LSU_hazard;

    assign rs1_match = (ld_rd_addr_LS == rs1_addr_DE);
    assign rs2_match = (ld_rd_addr_LS == rs2_addr_DE) && ~is_imm_DE; // Immediate instructions dont use RS2
    assign source_hazard = ld_inflight_LS && (rs1_match || rs2_match) && ~ld_valid_LS;
   
    assign LSU_hazard = (is_load_op_EX || is_store_op_EX) && ~ready_LS;

    // pipeline control
    assign stall_LS = 0;
    assign flush_LS = LSU_hazard;

    assign stall_EX = LSU_hazard;
    assign flush_EX = source_hazard || branch_EX;
    
    assign stall_DE = stall_EX || source_hazard;
    assign flush_DE = branch_EX;
    
    assign stall_FE = stall_DE;

endmodule : control
