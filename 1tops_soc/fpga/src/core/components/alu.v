module alu #(parameter WIDTH = 32) (
    input       [WIDTH-1:0] a, b,       // operands
    input       [3:0] alu_ctrl,         // ALU control
    output reg  [WIDTH-1:0] alu_out,    // ALU output
    output      zero,                   // zero flag
    output      less,                   // signed less than
    output      less_u                  // unsigned less than
);


// always block to determine the ALU output based on the ALU control signal
always @(*) begin
    case (alu_ctrl)
        4'b0000: alu_out = a + b;           // ADD
        4'b0001: alu_out = a - b;           // SUB
        4'b0010: alu_out = a & b;           // AND
        4'b0011: alu_out = a | b;           // OR
        4'b0100: alu_out = a << b[4:0];     // SLL (Shift Left Logical)
        4'b0101: alu_out = ($signed(a) < $signed(b)) ? 1 : 0; // SLT (Signed comparison)
        4'b0110: alu_out = (a < b) ? 1 : 0; // SLTU (Unsigned comparison)
        4'b0111: alu_out = a ^ b;           // XOR
        4'b1000: alu_out = $signed(a) >>> b[4:0]; // SRA (Arithmetic Right Shift)
        4'b1001: alu_out = a >> b[4:0];     // SRL (Logical Right Shift)
        default: alu_out = 1'bx;               // Default case
    endcase
end

// Flags
assign zero   = (alu_out == 0) ? 1'b1 : 1'b0;
assign less   = ($signed(a) < $signed(b)) ? 1'b1 : 1'b0;
assign less_u = (a < b) ? 1'b1 : 1'b0;

endmodule
