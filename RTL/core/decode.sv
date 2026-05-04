// instruction decode unit

`include "defines.svh"

module decode (
    input  logic [31:0] instr,

    output logic [4:0]  rd_addr,
    output logic [4:0]  rs1_addr,
    output logic [4:0]  rs2_addr,
    output logic        is_writeback,

    output alu_op_t     alu_op,
    output mul_op_t     mul_op,
    output comp_t       comp_op,
    output logic        subtract,
    output logic        shift_right,
    output logic        shift_arith,
    output logic        is_auipc,
    
    output logic        is_load_op,
    output load_op_t    load_op,
    output logic        is_store_op,
    output store_op_t   store_op,

    output logic        is_ctrl_op,
    output br_type_t    br_type,
    output logic        is_jump_op,

    output logic        is_imm,
    output logic [31:0] imm_b,
    output logic [31:0] imm_i,
    output logic [31:0] imm_s,
    output logic [31:0] imm_u,
    output logic [31:0] imm_j
);
    
    logic [4:0]  op;
    logic [2:0]  funct3;
    logic [6:0]  funct7;

    assign op = instr[6:2];
    assign is_imm = ~op[3];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];

    assign rd_addr = instr[7+:5];
    assign rs1_addr = instr[15+:5];
    assign rs2_addr = instr[20+:5];

    // instructions that write to the register file
    // (ALU and Jumps)
    assign is_writeback = ({op[4],op[2:1]} == 3'b010) | ({op[4:2],op[0]} == 4'b1101);

    // ALU decode
    always_comb begin
        casez ({op,funct3,funct7[0]})
            9'b01101_???_? : alu_op = LUI_OP;
            9'b110?1_???_?,  // Jumps
            9'b00101_???_?,  // AUIPC
            9'b0?000_???_?,  // Load/Store
            9'b0?100_000_0 : alu_op = ADDER_OP;
            9'b0?100_01?_0 : alu_op = COMP_OP;
            9'b01100_???_1 : alu_op = MUL_OP;
            9'b0?100_100_0 : alu_op = XOR_OP;
            9'b0?100_110_0 : alu_op = OR_OP;
            9'b0?100_111_0 : alu_op = AND_OP;
            9'b0?100_001_0,
            9'b0?100_101_0 : alu_op = SHIFTER_OP;
            default        : alu_op = ADDER_OP;
        endcase
    end

    // subtract enable
    assign subtract = {op,funct3,funct7[5]} == 9'b01100_000_1;

    // multiply type decode
    assign mul_op = mul_op_t'(funct3);

    assign is_auipc = (op == 5'b00101);

    // compare type decode
    assign comp_op = comp_t'(funct3);

    // shift type decode
    assign shift_right = funct3[2];
    assign shift_arith = funct7[5];

    // branch decode
    assign is_ctrl_op = ({op[4:2]} == 3'b110);
    assign br_type = br_type_t'(op[1:0]);
    assign is_jump_op = is_ctrl_op & op[0];

    // load/store decode
    assign is_load_op = (op == 5'b00000);
    assign load_op = load_op_t'(funct3);
    assign is_store_op = (op == 5'b01000);
    assign store_op = store_op_t'(funct3);

    // B-type: imm[12], imm[10:5], imm[4:1], imm[11] sign extended
    assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    // I-type: imm[11:0] sign extended
    assign imm_i = {{20{instr[31]}}, instr[31:20]};
    // S-type: imm[15:5] imm[4:0] sign extended
    assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    // U-type: imm[31:12] lower 12 bits zero
    assign imm_u = {instr[31:12], 12'b0};
    // J-type: imm[20], imm[10:1], imm[11], imm[19:12]
    assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

endmodule : decode
