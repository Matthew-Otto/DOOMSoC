// Empty definitions to appease Slang

(* blackbox *)
module BUFG (
    input  logic I,
    output logic O
);
endmodule

(* blackbox *)
module rPLL #(
    parameter FCLKIN = "100.0",
    parameter IDIV_SEL = 0,
    parameter FBDIV_SEL = 0,
    parameter ODIV_SEL = 8,
    parameter DYN_SDIV_SEL = 2
) (
    input  logic       CLKIN,
    input  logic       CLKFB,
    input  logic [5:0] FBDSEL,
    input  logic [5:0] IDSEL,
    input  logic [5:0] ODSEL,
    input  logic [3:0] PSDA,
    input  logic [3:0] DUTYDA,
    input  logic [3:0] FDLY,
    input  logic       RESET,
    input  logic       RESET_P,
    output logic       CLKOUT,
    output logic       LOCK,
    output logic       CLKOUTP,
    output logic       CLKOUTD,
    output logic       CLKOUTD3
);
endmodule

(* blackbox *)
module CLKDIV #(
    parameter DIV_MODE = "2",
    parameter GSREN = "false"
) (
    input  logic HCLKIN,
    input  logic RESETN,
    input  logic CALIB,
    output logic CLKOUT
);
endmodule

(* blackbox *)
module CLKDIV2 #(
    parameter GSREN = "false"
) (
    input  logic HCLKIN,
    input  logic RESETN,
    output logic CLKOUT
);
endmodule

(* blackbox *)
module OSER10 #(
    parameter GSREN = "false",
    parameter LSREN = "true"
) (
    output logic Q,
    input  logic D0,
    input  logic D1,
    input  logic D2,
    input  logic D3,
    input  logic D4,
    input  logic D5,
    input  logic D6,
    input  logic D7,
    input  logic D8,
    input  logic D9,
    input  logic PCLK,
    input  logic FCLK,
    input  logic RESET
);
endmodule

(* blackbox *)
module ODDR #(
    parameter INIT = 1'b0,
    parameter TXCLK_POL = 1'b0
)(
    input  wire D0,
    input  wire D1,
    input  wire TX,
    input  wire CLK,
    output wire Q0,
    output wire Q1
);
endmodule

(* blackbox *)
module DCS #(
    parameter DCS_MODE = "RISING"
)(
    input CLK0,
    input CLK1,
    input CLK2,
    input CLK3,
    input [3:0] CLKSEL,
    input SELFORCE,
    output CLKOUT
);
endmodule