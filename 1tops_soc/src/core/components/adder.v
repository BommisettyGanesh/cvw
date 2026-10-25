`ifndef ADDER_DEFINED
`define ADDER_DEFINED
module adder #(parameter WIDTH = 32) (
    input       [WIDTH-1:0] a, b,
    output      [WIDTH-1:0] sum
);

assign sum = a + b;

endmodule
`endif