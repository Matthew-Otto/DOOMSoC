`include "defines.svh"

module EXU (
    input  alu_op_t     alu_op,
    input  logic        is_imm,
    input  logic        is_store_op,
    input  logic        is_jump_op,
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
    output logic [31:0] alu_out
);

    ////////////////////////////////////////////////////////////////////////
    //// Operand MUX ///////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [31:0] operand_a;
    logic [31:0] operand_b;

    assign operand_a = (is_jump_op || is_auipc) ? PC : rs1_data;

    always_comb begin
        casez ({is_auipc, is_jump_op, is_imm, is_store_op})
            4'b1??? : operand_b = imm_u;
            4'b01?? : operand_b = 32'd4;
            4'b0010 : operand_b = imm_i;
            4'b0001 : operand_b = imm_s;
            default : operand_b = rs2_data;
        endcase
    end


    ////////////////////////////////////////////////////////////////////////
    //// Add / Sub /////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [31:0] operand_b_inv;
    logic [32:0] full_sum;
    logic [31:0] adder_out;

    assign operand_b_inv = operand_b ^ {32{subtract}};
    assign full_sum = operand_a + operand_b_inv + subtract;
    assign adder_out = full_sum[31:0];


    ////////////////////////////////////////////////////////////////////////
    //// Shift /////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [4:0]  shamt;
    logic [31:0] shifter_out;

    assign shamt = operand_b[4:0];

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


    ////////////////////////////////////////////////////////////////////////
    //// Compare ///////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic        lt;
    logic [31:0] comp_out;

    always_comb begin
        case (comp_op)
            c_SLT  : lt = $signed(operand_a) < $signed(operand_b);
            c_SLTU : lt = $unsigned(operand_a) < $unsigned(operand_b);
            default: lt = 1'b0;
        endcase
    end

    assign comp_out = {31'b0,lt};


    ////////////////////////////////////////////////////////////////////////
    //// Bitwise Ops ///////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    logic [31:0] xor_out;
    logic [31:0] or_out;
    logic [31:0] and_out;

    assign xor_out = rs1_data ^ operand_b;
    assign or_out  = rs1_data | operand_b;
    assign and_out = rs1_data & operand_b;


    ////////////////////////////////////////////////////////////////////////
    //// Multiply //////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
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

    ////////////////////////////////////////////////////////////////////////
    //// Output MUX ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    always_comb begin : out_mux
        case (alu_op)
            ADDER_OP   : alu_out = adder_out;
            MUL_OP     : alu_out = multiplier_out;
            XOR_OP     : alu_out = xor_out;
            OR_OP      : alu_out = or_out;
            AND_OP     : alu_out = and_out;
            SHIFTER_OP : alu_out = shifter_out;
            COMP_OP    : alu_out = comp_out;
            LUI_OP     : alu_out = imm_u;
            default    : alu_out = adder_out;
        endcase
    end

endmodule : EXU
