module tmds_encoder (
    input  logic       p_clk,
    input  logic       reset,

    input  logic       de,
    input  logic [1:0] ctrl,
    input  logic [7:0] color_value,

    output logic [9:0] encoded
);

    // count number of 1s in the input data
    logic [3:0] ones_cnt;
    assign ones_cnt = color_value[0] + color_value[1] + color_value[2] + color_value[3] + color_value[4] + color_value[5] + color_value[6] + color_value[7];

    logic use_xnor;
    assign use_xnor = (ones_cnt > 4'd4) || ((ones_cnt == 4'd4) && (color_value[0] == 1'b0));

    logic [8:0] q_m;
    
    // Serial X(N)OR
    always_comb begin
        q_m[0] = color_value[0];
        q_m[8] = ~use_xnor;
        if (use_xnor) begin
            q_m[1] = q_m[0] ^~ color_value[1];
            q_m[2] = q_m[1] ^~ color_value[2];
            q_m[3] = q_m[2] ^~ color_value[3];
            q_m[4] = q_m[3] ^~ color_value[4];
            q_m[5] = q_m[4] ^~ color_value[5];
            q_m[6] = q_m[5] ^~ color_value[6];
            q_m[7] = q_m[6] ^~ color_value[7];
        end else begin
            q_m[1] = q_m[0] ^ color_value[1];
            q_m[2] = q_m[1] ^ color_value[2];
            q_m[3] = q_m[2] ^ color_value[3];
            q_m[4] = q_m[3] ^ color_value[4];
            q_m[5] = q_m[4] ^ color_value[5];
            q_m[6] = q_m[5] ^ color_value[6];
            q_m[7] = q_m[6] ^ color_value[7];
        end
    end
    
    // Count 1s and 0s in the 8-bit payload of q_m
    logic [3:0] n1_qm;
    logic [3:0] n0_qm;
    assign n1_qm = q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7];
    assign n0_qm = 4'd8 - n1_qm;

    // Disparity difference (N1 - N0) for the current byte
    logic signed [5:0] disparity_diff;
    assign disparity_diff = $signed({2'b00, n1_qm}) - $signed({2'b00, n0_qm});

    // Running disparity counter
    logic signed [5:0] cnt;
    always_ff @(posedge p_clk) begin
        if (reset) begin
            encoded <= '0;
            cnt     <= '0;
        end else begin
            if (!de) begin
                // During blanking, reset disparity counter and output control tokens
                cnt <= 6'sd0;
                case (ctrl)
                    2'b00: encoded <= 10'b1101010100;
                    2'b01: encoded <= 10'b0010101011;
                    2'b10: encoded <= 10'b0101010100;
                    2'b11: encoded <= 10'b1010101011;
                endcase
            end else begin
                // Active video data encoding
                if (cnt == 6'sd0 || n1_qm == n0_qm) begin
                    encoded[9]   <= ~q_m[8];
                    encoded[8]   <= q_m[8];
                    encoded[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];

                    if (q_m[8]) begin
                        cnt <= cnt + disparity_diff;
                    end else begin
                        cnt <= cnt - disparity_diff;
                    end
                end else if ((cnt > 0 && n1_qm > n0_qm) || (cnt < 0 && n0_qm > n1_qm)) begin
                    // Polarity inversion to fix drifting disparity
                    encoded[9]   <= 1'b1;
                    encoded[8]   <= q_m[8];
                    encoded[7:0] <= ~q_m[7:0];
                    cnt <= cnt + (q_m[8] ? 6'sd2 : 6'sd0) - disparity_diff;
                end else begin
                    // No polarity inversion required
                    encoded[9]   <= 1'b0;
                    encoded[8]   <= q_m[8];
                    encoded[7:0] <= q_m[7:0];
                    cnt <= cnt - (q_m[8] ? 6'sd0 : 6'sd2) + disparity_diff;
                end
            end
        end
    end

endmodule : tmds_encoder
