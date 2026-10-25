`ifndef MUX5_DEFINED
`define MUX5_DEFINED
module mux5 #(parameter WIDTH = 32) (
    input      [WIDTH-1:0] d0, d1, d2, d3, d4,
    input      [2:0]       sel,
    output reg [WIDTH-1:0] y
);

always @(*) begin
    case (sel)
        3'b000:  y = d0; // ALUResultW
        3'b001:  y = d1; // ReadDataW (Data Memory)
        3'b010:  y = d2; // PCPlus4W  (JAL / JALR link)
        3'b011:  y = d3; // lAuiPCW   (LUI / AUIPC)
        3'b100:  y = d4; // CSRReadValW (CSR Read Data)
        default: y = d0;
    endcase
end

endmodule
`endif

