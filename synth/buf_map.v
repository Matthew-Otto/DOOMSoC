module \$buf (A, Y);
  parameter WIDTH = 1;
  input [WIDTH-1:0] A;
  output [WIDTH-1:0] Y;
  assign Y = A;
endmodule
