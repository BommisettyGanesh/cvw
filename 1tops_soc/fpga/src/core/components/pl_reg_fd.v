module pl_reg_fd (
    input             clk, reset,
    input             StallD,
    input             FlushD,
    input             IFU_DataPhase,
    input      [31:0] InstrF, PCF, PCPlus4F,
    output reg [31:0] InstrD, PCD, PCPlus4D,
    output reg        ValidD
);

initial begin
    InstrD = 32'h00000013; PCD = 0; PCPlus4D = 0; ValidD = 0;
end

always @(posedge clk) begin
    if (reset || FlushD) begin
        InstrD   <= 32'h00000013;
        PCD      <= 32'd0;
        PCPlus4D <= 32'd0;
        ValidD   <= 1'b0;
    end else if (!StallD) begin
        if (IFU_DataPhase) begin
            InstrD   <= InstrF;
            PCD      <= PCF;
            PCPlus4D <= PCPlus4F;
            ValidD   <= 1'b1;
        end else begin
            InstrD   <= 32'h00000013;
            PCD      <= 32'd0;
            PCPlus4D <= 32'd0;
            ValidD   <= 1'b0;
        end
    end
end

endmodule
