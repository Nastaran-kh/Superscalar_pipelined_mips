module signext(input [15:0] in, output [31:0] out);
  assign out = {{16{in[15]}}, in};  // Sign-extend from 16 to 32 bits
endmodule
