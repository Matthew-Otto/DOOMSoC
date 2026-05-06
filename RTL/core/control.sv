module control (
    // Source Bypass/Hazard
    input  logic rs1_addr_DE,
    input  logic rs2_addr_DE,
    input  logic ld_valid_LS,
    input  logic ld_inflight_LS,
    input  logic ld_rd_addr_LS,
    input  logic is_load_op_DE,
    input  logic is_store_op_DE,

    output logic forward_rs1_DE,
    output logic forward_rs2_DE

);

    logic rs1_hazard;
    logic rs2_hazard;
    logic forward_rs1;
    logic forward_rs2;

    assign rs1_hazard = (ld_rd_addr_LS == rs1_addr_DE);
    assign rs2_hazard = (ld_rd_addr_LS == rs2_addr_DE);

    assign stall_EX = ld_inflight_LS && (rs1_hazard || rs2_hazard || is_load_op_DE || is_store_op_DE);

    assign forward_rs1_DE = ld_valid_LS && rs1_hazard;
    assign forward_rs2_DE = ld_valid_LS && rs2_hazard;


endmodule : control
