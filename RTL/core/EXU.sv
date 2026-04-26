`include "defines.svh"

module EXU (
    input  alu_op_t     alu_op,
    input  logic        is_imm,
    input  logic        is_store_op,
    input  logic        is_auipc,
    input  comp_t       comp_op,
    input  logic        subtract,
    input  logic        shift_right,
    input  logic        shift_arith,
    input  mul_op_t     mul_op, 

    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  logic [31:0] imm_i,
    input  logic [31:0] imm_u,
    input  logic [31:0] imm_s,
    input  logic [31:0] PC,
    output logic [31:0] rd_data
);

    // BOZO TODO SET LESS THAN instructions
    logic eq;
    logic lt;
    logic ltu;
    logic geu;
    
    logic [31:0] b_mux;
    logic [31:0] s_mux;
    logic [31:0] adder_out;
    logic        comp_out;
    logic [31:0] shifter_out;
    logic [31:0] xor_out;
    logic [31:0] or_out;
    logic [31:0] and_out;


    assign b_mux = is_imm ? imm_i : rs2_data;
    assign s_mux = is_store_op ? imm_s : b_mux;

    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] operand_b_inv;
    logic [32:0] full_sum;

    assign operand_a = is_auipc ? PC : rs1_data;
    assign operand_b = is_auipc ? imm_u : s_mux;

    assign operand_b_inv = operand_b ^ {32{subtract}};

    assign full_sum = operand_a + operand_b_inv + subtract;
    assign adder_out = full_sum[31:0];

    assign eq = operand_a == operand_b;
    assign lt = $signed(operand_a) < $signed(operand_b);
    assign ltu = $unsigned(operand_a) < $unsigned(operand_b);
    assign geu = ~ltu;

    // BOZO non branch comp ops
    always_comb begin : comparator
        case (comp_op)
            c_BEQ  : comp_out = eq;
            c_BNE  : comp_out = ~eq;
            c_SLT,
            c_BLT  : comp_out = lt;
            c_BGE  : comp_out = ~lt;
            c_SLTU,
            c_BLTU : comp_out = ltu;
            c_BGEU : comp_out = geu;
        endcase
    end

    logic [4:0] shamt;

    assign shamt = b_mux[4:0];

    always_comb begin
        if (shift_right) begin
            // Arithmetic Shift Right (ASR)
            if (shift_arith) begin
                shifter_out = 32'($signed(rs1_data) >>> shamt);
            // Logical Shift Right (LSR)
            end else begin
                shifter_out = rs1_data >> shamt;
            end
        // Logical Shift Left (LSL)
        end else begin
            shifter_out = rs1_data << shamt;
        end
    end

    assign xor_out = rs1_data ^ b_mux;
    assign or_out  = rs1_data | b_mux;
    assign and_out = rs1_data & b_mux;

    logic sign_ext_a;
    logic sign_ext_b;
    logic signed [32:0] multiplicand_a;
    logic signed [32:0] multiplicand_b;
    logic signed [65:0] full_product;
    logic [31:0] multiplier_out;
    
    assign sign_ext_a = (mul_op == m_MULHU) ? 1'b0 : rs1_data[31];
    assign sign_ext_b = (mul_op == m_MULHSU || mul_op == m_MULHU) ? 1'b0 : rs2_data[31];

    assign multiplicand_a = {sign_ext_a, rs1_data};
    assign multiplicand_b = {sign_ext_b, rs2_data};
    
    assign full_product = multiplicand_a * multiplicand_b;

    always_comb begin
        if (mul_op == m_MUL)
            multiplier_out = full_product[31:0];
        else
            multiplier_out = full_product[63:32];
    end

    always_comb begin : out_mux
        case (alu_op)
            ADDER_OP   : rd_data = adder_out;
            MUL_OP     : rd_data = multiplier_out;
            XOR_OP     : rd_data = xor_out;
            OR_OP      : rd_data = or_out;
            AND_OP     : rd_data = and_out;
            SHIFTER_OP : rd_data = shifter_out;
            LUI_OP     : rd_data = imm_u;
            default    : rd_data = adder_out;
        endcase
    end

endmodule : EXU
