module reset_ff #(parameter WIDTH = 32, RESET_VAL = 0) (
    input       clk, rst, clr,
    input       [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);

initial begin
    q = RESET_VAL;
end

always @(posedge clk) begin
    if (rst) q <= RESET_VAL;
    else if (!clr) q <= d;
end

endmodule
