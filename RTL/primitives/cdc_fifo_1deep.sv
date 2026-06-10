module cdc_fifo_1deep #(
    parameter int WIDTH
) (
    input  logic             w_clk,
    input  logic             w_rst,
    output logic             w_rdy,
    input  logic             w_val,
    input  logic [WIDTH-1:0] w_data,

    input  logic             r_clk,
    input  logic             r_rst,
    input  logic             r_rdy,
    output logic             r_val,
    output logic [WIDTH-1:0] r_data
);

    logic [WIDTH-1:0] mem [0:1];

    logic w_ptr, r_ptr;
    logic ws1_r_ptr, ws2_r_ptr;
    logic rs1_w_ptr, rs2_w_ptr;

    /////////////////////////////////////////////
    //// Write Domain ///////////////////////////
    /////////////////////////////////////////////

    //// write data
    always_ff @(posedge w_clk) begin
        if (w_rst) begin
            w_ptr <= 1'b0;
        end else if (w_val && w_rdy) begin
            w_ptr <= ~w_ptr;
            mem[w_ptr] <= w_data;
        end
    end

    //// r_ptr synchronization
    always_ff @(posedge w_clk) begin
        if (w_rst) {ws2_r_ptr, ws1_r_ptr} <= 2'b0;
        else       {ws2_r_ptr, ws1_r_ptr} <= {ws1_r_ptr, r_ptr};
    end

    assign w_rdy = (w_ptr == ws2_r_ptr);


    /////////////////////////////////////////////
    //// Read Domain ////////////////////////////
    /////////////////////////////////////////////

    //// read data
    always_ff @(posedge r_clk) begin
        if (r_rst) begin
            r_ptr <= 1'b0;
        end else if (r_val && r_rdy) begin
            r_ptr <= ~r_ptr;
        end
    end

    //// w_ptr synchronization
    always_ff @(posedge r_clk) begin
        if (r_rst) {rs2_w_ptr, rs1_w_ptr} <= 2'b0;
        else       {rs2_w_ptr, rs1_w_ptr} <= {rs1_w_ptr, w_ptr};
    end

    assign r_val = (r_ptr != rs2_w_ptr);

    assign r_data = mem[r_ptr];

endmodule : cdc_fifo_1deep
