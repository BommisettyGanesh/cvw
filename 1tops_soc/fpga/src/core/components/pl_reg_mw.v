// =============================================================================
// Module: pl_reg_mw
// Purpose: Pipeline Register M -> W with Stall Enable for AHB Wait-States
// =============================================================================

module pl_reg_mw (
    input             clk,
    input             reset,
    input             StallW,       // AHB global pipeline stall enable
    input             RegWriteM,
    input [2:0]       ResultSrcM,
    input [31:0]      ALUResultM, ReadDataM, PCPlus4M,
    input [4:0]       RdM,
    input [31:0]      PCM, WriteDataM, lAuiPCM, CSRReadValM,
    input             ValidM,
    output reg        RegWriteW,
    output reg [2:0]  ResultSrcW,
    output reg [31:0] ALUResultW, ReadDataW, PCPlus4W,
    output reg [4:0]  RdW,
    output reg [31:0] PCW, WriteDataW, lAuiPCW, CSRReadValW,
    output reg        ValidW
);

always @(posedge clk) begin
    if (reset) begin
        RegWriteW   <= 0;
        ResultSrcW  <= 0;
        ALUResultW  <= 0;
        ReadDataW   <= 0;
        PCPlus4W    <= 0;
        RdW         <= 0;
        PCW         <= 0;
        WriteDataW  <= 0;
        lAuiPCW     <= 0;
        CSRReadValW <= 0;
        ValidW      <= 0;
    end else if (!StallW) begin
        RegWriteW   <= RegWriteM;
        ResultSrcW  <= ResultSrcM;
        ALUResultW  <= ALUResultM;
        ReadDataW   <= ReadDataM;
        PCPlus4W    <= PCPlus4M;
        RdW         <= RdM;
        PCW         <= PCM;
        WriteDataW  <= WriteDataM;
        lAuiPCW     <= lAuiPCM;
        CSRReadValW <= CSRReadValM;
        ValidW      <= ValidM;
    end
end

endmodule
