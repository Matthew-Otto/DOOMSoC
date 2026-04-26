// Branch Unit. calculates branch targets
// and evaluates if conditional branches are taken

`include "defines.svh"

module BRU (
    input  logic [31:0] PC,
    input  logic        is_ctrl_op,
    input  comp_t       comp_op,
    input  br_type_t    br_type,
    input  logic        is_jump_op,

    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  logic [31:0] imm_b,
    input  logic [31:0] imm_i,
    input  logic [31:0] imm_j,

    output logic        branch,
    output logic [31:0] branch_target
);

    // Evaluate conditional branch
    logic eq;
    logic lt;
    logic ltu;
    logic geu;
    logic branch_eval;

    assign eq = rs1_data == rs2_data;
    assign lt = $signed(rs1_data) < $signed(rs2_data);
    assign ltu = $unsigned(rs1_data) < $unsigned(rs2_data);
    assign geu = ~ltu;

    always_comb begin
        case (comp_op)
            c_BEQ  : branch_eval = eq;
            c_BNE  : branch_eval = ~eq;
            c_BLT  : branch_eval = lt;
            c_BGE  : branch_eval = ~lt;
            c_BLTU : branch_eval = ltu;
            c_BGEU : branch_eval = geu;
            default: branch_eval = 1'b0;
        endcase
    end

    // Calculate branch target
    always_comb begin
        case (br_type)
            bt_BRANCH : branch_target = PC + imm_b;
            bt_JAL    : branch_target = PC + imm_j;
            bt_JALR   : branch_target = rs1_data + imm_i;
            default   : branch_target = 'x;
        endcase
    end

    assign branch = is_ctrl_op && (branch_eval || is_jump_op);

endmodule : BRU
