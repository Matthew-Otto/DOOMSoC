// True dual-port, dual-clock BRAM with byte-enables


module tdp_bram_be #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    // Port A
    input  logic                      clk_a,
    input  logic [ADDR_WIDTH-1:0]     addr_a,
    input  logic [(DATA_WIDTH/8)-1:0] wr_en_a,
    input  logic [DATA_WIDTH-1:0]     wr_data_a,
    output logic [DATA_WIDTH-1:0]     rd_data_a,

    // Port B
    input  logic                      clk_b,
    input  logic [ADDR_WIDTH-1:0]     addr_b,
    input  logic [(DATA_WIDTH/8)-1:0] wr_en_b,
    input  logic [DATA_WIDTH-1:0]     wr_data_b,
    output logic [DATA_WIDTH-1:0]     rd_data_b
);

    genvar i;
    generate
        for (i = 0; i < (DATA_WIDTH/16); i=i+1) begin : half_word_ram
            
            logic [13:0] ada;
            logic [13:0] adb;
            logic [15:0] doa_out;
            logic [15:0] dob_out;
            
            // Gowin DPB 16-bit addressing:
            // ADA[13:4] = word address (10 bits)
            // ADA[3:2] = 2'b00 (unused parity selects)
            // ADA[1:0] = byte enables (when WREA is high)
            
            assign ada = { {(10-ADDR_WIDTH){1'b0}}, addr_a, 2'b00, wr_en_a[i*2+:2] };
            assign adb = { {(10-ADDR_WIDTH){1'b0}}, addr_b, 2'b00, wr_en_b[i*2+:2] };

            DPB #(
                .READ_MODE0(1'b0),
                .READ_MODE1(1'b0),
                .WRITE_MODE0(2'b01),
                .WRITE_MODE1(2'b01),
                .BIT_WIDTH_0(16),
                .BIT_WIDTH_1(16),
                .RESET_MODE("SYNC")
            ) dpb_inst (
                .DOA(doa_out),
                .DOB(dob_out),
                .DIA(wr_data_a[i*16+:16]),
                .DIB(wr_data_b[i*16+:16]),
                .ADA(ada),
                .ADB(adb),
                .WREA(|wr_en_a[i*2+:2]),
                .WREB(|wr_en_b[i*2+:2]),
                .CLKA(clk_a),
                .CLKB(clk_b),
                .CEA(1'b1),
                .CEB(1'b1),
                .RESETA(1'b0),
                .RESETB(1'b0),
                .OCEA(1'b1),
                .OCEB(1'b1),
                .BLKSELA(3'b000),
                .BLKSELB(3'b000)
            );
            
            assign rd_data_a[i*16+:16] = doa_out;
            assign rd_data_b[i*16+:16] = dob_out;
        end
    endgenerate

endmodule : tdp_bram_be
