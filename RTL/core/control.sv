// Generate control signals for core

module control (
    input  logic        is_writeback,
    input  logic        ld_valid,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    input  logic [4:0]  ld_rd_addr,

    output logic        reg_we
);

    logic data_hazard;

    assign data_hazard = ld_valid & ((rs1_addr == ld_rd_addr) | (rs2_addr == ld_rd_addr));
    
    // dont writeback if branching (flush), or if fetch_stall (waiting on prev load) and instr is a non-load writeback
    // BOZO TODO
    //assign reg_we = ~flush & ((~fetch_stall & is_writeback) | ld_valid); 
    //assign reg_we = ~flush & ((is_writeback) | ld_valid); 

    // assign stall_LS = ~(flush | data_hazard);

    //assign fetch_stall = (ld_valid & is_writeback) | data_hazard;



endmodule : control
